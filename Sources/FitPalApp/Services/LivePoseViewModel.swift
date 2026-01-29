import AVFoundation
import Combine
import Foundation
import CoreImage
import UIKit

final class LivePoseViewModel: ObservableObject {
    @Published var selectedLift: LiftType = .squat
    @Published var report: AnalysisReport?
    @Published var isRunning: Bool = false
    @Published var statusMessage: String = "Idle"
    @Published var errorMessage: String?
    @Published var latestJoints: [Joint: CGPoint]?
    @Published var repCount: Int = 0
    @Published var feedbackMessage: String = "Waiting..."
    @Published var isRecording: Bool = false
    @Published var recordingURL: URL?

    let cameraService = CameraService()
    private let poseService = MediaPipePoseService()
    private let frameQueue = DispatchQueue(label: "fitpal.frame.buffer")
    private let recordingQueue = DispatchQueue(label: "fitpal.recording.queue")
    private let ciContext = CIContext()

    private var frames: [PoseFrame] = []
    private var nextFrameId: Int = 0
    private let bufferDuration: Double = 6.0
    private var latestJointsSnapshot: [Joint: CGPoint] = [:]
    private var feedbackCounter: Int = 0

    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var writerAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartTime: CMTime?
    private var recordingFrameIndex: Int = 0

    init() {
        cameraService.onSampleBuffer = { [weak self] sampleBuffer in
            self?.poseService.process(sampleBuffer: sampleBuffer)
            self?.handleSampleBufferForRecording(sampleBuffer)
        }

        poseService.onPoseLandmarks = { [weak self] joints, timestampMs in
            self?.handleLandmarks(joints: joints, timestampMs: timestampMs)
        }
    }

    func start() {
        errorMessage = nil
        statusMessage = "Starting..."
        report = nil
        feedbackMessage = "Waiting..."
        repCount = 0
        latestJoints = nil
        recordingURL = nil

        guard poseService.isAvailable else {
            errorMessage = "MediaPipeTasksVision not available. Install via CocoaPods."
            statusMessage = "Unavailable"
            return
        }

        guard let modelURL = Bundle.fitpalResourceURL(name: "pose_landmarker", ext: "task") else {
            errorMessage = "Missing pose_landmarker.task in app bundle."
            statusMessage = "Model missing"
            return
        }

        do {
            try poseService.start(modelPath: modelURL.path)
            resetBuffer()
            cameraService.start()
            isRunning = true
            statusMessage = "Running"
        } catch {
            errorMessage = "Failed to start MediaPipe: \(error)"
            statusMessage = "Error"
        }
    }

    func stop() {
        cameraService.stop()
        poseService.stop()
        isRunning = false
        statusMessage = "Stopped"
        stopRecording()
    }

    func analyzeRecent() {
        errorMessage = nil
        let currentFrames = frameQueue.sync { frames }
        guard currentFrames.count > 15 else {
            errorMessage = "Not enough frames captured."
            return
        }
        let normalized = normalizeFrames(frames: currentFrames)
        let fps = estimateFPS(frames: normalized) ?? 30
        let series = PoseSeries(fps: fps, frames: normalized)
        report = AnalysisPipeline.analyze(series: series, liftType: selectedLift)
    }

    func startRecording() {
        guard isRunning else { return }
        errorMessage = nil
        recordingURL = nil
        isRecording = true
        recordingQueue.async {
            self.resetRecordingState()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingQueue.async {
            self.finishRecording()
        }
    }

    private func handleLandmarks(joints: [Joint: CGPoint], timestampMs: Int) {
        let time = Double(timestampMs) / 1000.0

        frameQueue.async {
            let frame = PoseFrame(id: self.nextFrameId, time: time, points: joints)
            self.nextFrameId += 1
            self.frames.append(frame)

            let cutoff = time - self.bufferDuration
            if let firstIndex = self.frames.firstIndex(where: { $0.time >= cutoff }) {
                self.frames = Array(self.frames[firstIndex...])
            }

            self.latestJointsSnapshot = joints
        }

        DispatchQueue.main.async {
            self.statusMessage = "Pose detected"
            self.latestJoints = joints
        }

        feedbackCounter += 1
        if feedbackCounter % 15 == 0 {
            updateFeedbackAsync()
        }
    }

    private func resetBuffer() {
        frameQueue.sync {
            frames.removeAll()
            nextFrameId = 0
        }
    }

    private func normalizeFrames(frames: [PoseFrame]) -> [PoseFrame] {
        guard let firstTime = frames.first?.time else { return frames }
        return frames.map { frame in
            PoseFrame(id: frame.id, time: frame.time - firstTime, points: frame.points)
        }
    }

    private func estimateFPS(frames: [PoseFrame]) -> Double? {
        guard frames.count > 4 else { return nil }
        var deltas: [Double] = []
        for idx in 1..<frames.count {
            let dt = frames[idx].time - frames[idx - 1].time
            if dt > 0 {
                deltas.append(dt)
            }
        }
        guard !deltas.isEmpty else { return nil }
        let median = deltas.sorted()[deltas.count / 2]
        if median <= 0 { return nil }
        return 1.0 / median
    }

    private func updateFeedbackAsync() {
        DispatchQueue.global(qos: .utility).async {
            let currentFrames = self.frameQueue.sync { self.frames }
            guard currentFrames.count > 15 else { return }
            let normalized = self.normalizeFrames(frames: currentFrames)
            let fps = self.estimateFPS(frames: normalized) ?? 30
            let series = PoseSeries(fps: fps, frames: normalized)
            let report = AnalysisPipeline.analyze(series: series, liftType: self.selectedLift)
            let count = report.repCount
            let message: String
            if let last = report.reps.last {
                message = last.issues.isEmpty ? "Good rep" : last.issues.joined(separator: ", ")
            } else {
                message = "Keep moving"
            }

            DispatchQueue.main.async {
                self.repCount = count
                self.feedbackMessage = message
            }
        }
    }

    private func handleSampleBufferForRecording(_ sampleBuffer: CMSampleBuffer) {
        recordingQueue.async {
            guard self.isRecording else { return }
            self.appendSampleBuffer(sampleBuffer)
        }
    }

    private func resetRecordingState() {
        assetWriter = nil
        writerInput = nil
        writerAdaptor = nil
        recordingStartTime = nil
        recordingFrameIndex = 0
    }

    private func finishRecording() {
        guard let writerInput, let assetWriter else { return }
        writerInput.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        assetWriter.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        let outputURL = assetWriter.outputURL
        DispatchQueue.main.async {
            self.recordingURL = outputURL
        }
        resetRecordingState()
    }

    private func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if assetWriter == nil {
            do {
                try setupWriter(with: pixelBuffer, startTime: timestamp)
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to start recording: \(error.localizedDescription)"
                    self.isRecording = false
                }
                return
            }
        }

        guard let writerInput, let writerAdaptor, let assetWriter else { return }
        if assetWriter.status == .failed || assetWriter.status == .cancelled { return }
        guard writerInput.isReadyForMoreMediaData else { return }

        guard let pool = writerAdaptor.pixelBufferPool else { return }
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard let outputBuffer else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        ciContext.render(ciImage, to: outputBuffer)

        let joints = frameQueue.sync { latestJointsSnapshot }
        if !joints.isEmpty {
            drawOverlay(into: outputBuffer, joints: joints)
        }

        let appendTime: CMTime
        if let start = recordingStartTime {
            appendTime = CMTimeSubtract(timestamp, start)
        } else {
            appendTime = .zero
        }
        recordingFrameIndex += 1
        writerAdaptor.append(outputBuffer, withPresentationTime: appendTime)
    }

    private func setupWriter(with pixelBuffer: CVPixelBuffer, startTime: CMTime) throws {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("live_overlay_\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferCGImageCompatibilityKey as String: true
            ]
        )

        guard writer.canAdd(input) else {
            throw PoseError.cannotReadVideo
        }
        writer.add(input)

        if writer.startWriting() == false {
            throw PoseError.assetReaderFailed
        }
        writer.startSession(atSourceTime: startTime)

        assetWriter = writer
        writerInput = input
        writerAdaptor = adaptor
        recordingStartTime = startTime
    }

    private func drawOverlay(into buffer: CVPixelBuffer, joints: [Joint: CGPoint]) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: baseAddress,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return }

        context.setLineWidth(2.5)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setFillColor(UIColor.red.cgColor)

        func point(_ joint: Joint) -> CGPoint? {
            guard let p = joints[joint] else { return nil }
            return CGPoint(x: p.x * size.width, y: p.y * size.height)
        }

        let connections: [(Joint, Joint)] = [
            (.shoulder, .elbow),
            (.elbow, .wrist),
            (.shoulder, .hip),
            (.hip, .knee),
            (.knee, .ankle)
        ]

        for (a, b) in connections {
            if let pa = point(a), let pb = point(b) {
                context.move(to: pa)
                context.addLine(to: pb)
                context.strokePath()
            }
        }

        for joint in [Joint.shoulder, .elbow, .wrist, .hip, .knee, .ankle] {
            if let p = point(joint) {
                let radius: CGFloat = 4.0
                let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
                context.fillEllipse(in: rect)
            }
        }
    }
}
