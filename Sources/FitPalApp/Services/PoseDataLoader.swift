import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UIKit
import Vision

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

struct PoseDataLoader {
    static func loadSample(for lift: LiftType) throws -> PoseSeries {
        let fileName = "sample_\(lift.rawValue)_side"
        guard let url = Bundle.fitpalResourceURL(name: fileName, ext: "json") else {
            throw PoseError.invalidData
        }
        let data = try Data(contentsOf: url)
        return try decodePoseSeries(from: data)
    }

    private static func decodePoseSeries(from data: Data) throws -> PoseSeries {
        let decoded = try JSONDecoder().decode(PoseSampleJSON.self, from: data)
        let frames = decoded.frames.enumerated().map { index, frame in
            PoseFrame(id: index, time: frame.t, points: frame.points.toJointMap())
        }
        return PoseSeries(fps: decoded.fps, frames: frames)
    }
}

struct VideoPoseExtractor {
    static func extractPoseSeries(from url: URL, preferredSide: PoseSide = .right, targetFPS: Double = 15.0) throws -> PoseSeries {
#if canImport(MediaPipeTasksVision)
        if let modelURL = Bundle.fitpalResourceURL(name: "pose_landmarker", ext: "task") {
            return try extractPoseSeriesWithMediaPipe(from: url, modelURL: modelURL, preferredSide: preferredSide, targetFPS: targetFPS)
        }
#endif
        return try extractPoseSeriesWithVision(from: url, preferredSide: preferredSide, targetFPS: targetFPS)
    }

    static func renderOverlayVideo(from url: URL, preferredSide: PoseSide = .right, targetFPS: Double = 15.0) throws -> URL {
#if canImport(MediaPipeTasksVision)
        guard let modelURL = Bundle.fitpalResourceURL(name: "pose_landmarker", ext: "task") else {
            throw PoseError.invalidData
        }
        return try renderOverlayVideoWithMediaPipe(from: url, modelURL: modelURL, preferredSide: preferredSide, targetFPS: targetFPS)
#else
        throw PoseError.invalidData
#endif
    }

    private static func extractPoseSeriesWithVision(from url: URL, preferredSide: PoseSide, targetFPS: Double) throws -> PoseSeries {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw PoseError.missingVideoTrack
        }

        let nominalFPS = Double(track.nominalFrameRate)
        let sourceFPS = nominalFPS > 0 ? nominalFPS : 30.0
        let stride = max(1, Int(round(sourceFPS / targetFPS)))
        let orientation = imageOrientation(from: track.preferredTransform)

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw PoseError.cannotReadVideo
        }
        reader.add(output)
        if !reader.startReading() {
            throw PoseError.assetReaderFailed
        }

        let request = VNDetectHumanBodyPoseRequest()

        var frames: [PoseFrame] = []
        var times: [Double] = []
        var frameIndex = 0

        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else { break }
            defer { frameIndex += 1 }
            if frameIndex % stride != 0 { continue }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            let timeSeconds = CMTimeGetSeconds(timestamp)

            let handler = VNImageRequestHandler(cmSampleBuffer: sample, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continue
            }

            guard let observation = request.results?.first as? VNHumanBodyPoseObservation else { continue }
            guard let joints = try joints(from: observation, preferredSide: preferredSide) else { continue }

            let frame = PoseFrame(id: frames.count, time: timeSeconds, points: joints)
            frames.append(frame)
            times.append(timeSeconds)
        }

        if reader.status == .failed || reader.status == .cancelled {
            throw PoseError.assetReaderFailed
        }

        if frames.isEmpty {
            throw PoseError.noPoseDetected
        }

        let fps = estimatedFPS(from: times) ?? min(targetFPS, sourceFPS)
        return PoseSeries(fps: fps, frames: frames)
    }

#if canImport(MediaPipeTasksVision)
    private static func renderOverlayVideoWithMediaPipe(
        from url: URL,
        modelURL: URL,
        preferredSide: PoseSide,
        targetFPS: Double
    ) throws -> URL {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw PoseError.missingVideoTrack
        }

        let nominalFPS = Double(track.nominalFrameRate)
        let sourceFPS = nominalFPS > 0 ? nominalFPS : 30.0
        let stride = max(1, Int(round(sourceFPS / targetFPS)))
        let orientation = imageOrientation(from: track.preferredTransform)
        let uiOrientation = uiImageOrientation(from: orientation)
        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        let outputSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("pose_overlay_\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outputSize.width,
                kCVPixelBufferHeightKey as String: outputSize.height,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferCGImageCompatibilityKey as String: true
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw PoseError.cannotReadVideo
        }
        writer.add(writerInput)

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw PoseError.cannotReadVideo
        }
        reader.add(output)

        let options = PoseLandmarkerOptions()
        let baseOptions = BaseOptions()
        baseOptions.modelAssetPath = modelURL.path
        options.baseOptions = baseOptions
        options.runningMode = .video
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.2
        options.minPosePresenceConfidence = 0.2
        options.minTrackingConfidence = 0.2
        let landmarker = try PoseLandmarker(options: options)

        let ciContext = CIContext()

        guard writer.startWriting() else {
            throw PoseError.assetReaderFailed
        }
        writer.startSession(atSourceTime: .zero)

        guard reader.startReading() else {
            throw PoseError.assetReaderFailed
        }

        var frameIndex = 0
        var outputIndex = 0

        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else { break }
            defer { frameIndex += 1 }
            if frameIndex % stride != 0 { continue }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            let timestampMs = Int(CMTimeGetSeconds(timestamp) * 1000.0)

            let mpImage = try MPImage(pixelBuffer: pixelBuffer, orientation: uiOrientation)
            let result = try landmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
            let joints =
                result.landmarks.first.flatMap { mapLandmarks($0, preferredSide: preferredSide, minVisibility: 0.1, minJoints: 2) }
                ?? result.landmarks.first.flatMap { mapLandmarks($0, preferredSide: (preferredSide == .right ? .left : .right), minVisibility: 0.1, minJoints: 2) }

            guard let pool = adaptor.pixelBufferPool else { break }
            var outputBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
            guard let outputBuffer else { continue }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
            ciContext.render(ciImage, to: outputBuffer)

            if let joints {
                drawOverlay(into: outputBuffer, joints: joints)
            }

            let presentationTime = CMTime(value: CMTimeValue(outputIndex), timescale: CMTimeScale(targetFPS))
            outputIndex += 1

            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }
            adaptor.append(outputBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()
        let finishSemaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            finishSemaphore.signal()
        }
        finishSemaphore.wait()

        if reader.status == .failed || reader.status == .cancelled || writer.status == .failed {
            throw PoseError.assetReaderFailed
        }

        return outputURL
    }

    private static func extractPoseSeriesWithMediaPipe(
        from url: URL,
        modelURL: URL,
        preferredSide: PoseSide,
        targetFPS: Double
    ) throws -> PoseSeries {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw PoseError.missingVideoTrack
        }

        let nominalFPS = Double(track.nominalFrameRate)
        let sourceFPS = nominalFPS > 0 ? nominalFPS : 30.0
        let stride = max(1, Int(round(sourceFPS / targetFPS)))
        let orientation = imageOrientation(from: track.preferredTransform)
        let uiOrientation = uiImageOrientation(from: orientation)

        let options = PoseLandmarkerOptions()
        let baseOptions = BaseOptions()
        baseOptions.modelAssetPath = modelURL.path
        options.baseOptions = baseOptions
        options.runningMode = .video
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.3
        options.minPosePresenceConfidence = 0.3
        options.minTrackingConfidence = 0.3

        let landmarker = try PoseLandmarker(options: options)

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw PoseError.cannotReadVideo
        }
        reader.add(output)
        if !reader.startReading() {
            throw PoseError.assetReaderFailed
        }

        var frames: [PoseFrame] = []
        var times: [Double] = []
        var frameIndex = 0

        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else { break }
            defer { frameIndex += 1 }
            if frameIndex % stride != 0 { continue }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            let timeSeconds = CMTimeGetSeconds(timestamp)
            let timestampMs = Int(timeSeconds * 1000.0)

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let image = try MPImage(pixelBuffer: pixelBuffer, orientation: uiOrientation)
            let result = try landmarker.detect(videoFrame: image, timestampInMilliseconds: timestampMs)
            guard let landmarks = result.landmarks.first else { continue }

            let joints =
                mapLandmarks(landmarks, preferredSide: preferredSide, minVisibility: 0.2, minJoints: 4)
                ?? mapLandmarks(landmarks, preferredSide: (preferredSide == .right ? .left : .right), minVisibility: 0.2, minJoints: 4)
            guard let joints else { continue }
            let frame = PoseFrame(id: frames.count, time: timeSeconds, points: joints)
            frames.append(frame)
            times.append(timeSeconds)
        }

        if reader.status == .failed || reader.status == .cancelled {
            throw PoseError.assetReaderFailed
        }

        if frames.isEmpty {
            throw PoseError.noPoseDetected
        }

        let fps = estimatedFPS(from: times) ?? min(targetFPS, sourceFPS)
        return PoseSeries(fps: fps, frames: frames)
    }

    private static func mapLandmarks(
        _ landmarks: [NormalizedLandmark],
        preferredSide: PoseSide,
        minVisibility: Float,
        minJoints: Int
    ) -> [Joint: CGPoint]? {
        let indexMap: [Joint: Int]
        switch preferredSide {
        case .left:
            indexMap = [
                .shoulder: 11,
                .elbow: 13,
                .wrist: 15,
                .hip: 23,
                .knee: 25,
                .ankle: 27
            ]
        case .right:
            indexMap = [
                .shoulder: 12,
                .elbow: 14,
                .wrist: 16,
                .hip: 24,
                .knee: 26,
                .ankle: 28
            ]
        }

        var joints: [Joint: CGPoint] = [:]
        for (joint, index) in indexMap {
            guard index < landmarks.count else { continue }
            let landmark = landmarks[index]
            let visibility = landmark.visibility?.floatValue ?? 1.0
            let presence = landmark.presence?.floatValue ?? 1.0
            guard visibility >= minVisibility, presence >= minVisibility else { continue }
            joints[joint] = CGPoint(x: CGFloat(landmark.x), y: CGFloat(landmark.y))
        }
        guard joints.count >= minJoints else { return nil }
        return joints
    }
#endif

    private static func joints(from observation: VNHumanBodyPoseObservation, preferredSide: PoseSide) throws -> [Joint: CGPoint]? {
        let points = try observation.recognizedPoints(.all)
        let minConfidence: VNConfidence = 0.3
        if let mapped = mapPoints(points, side: preferredSide, minConfidence: minConfidence) {
            return mapped
        }
        let fallback: PoseSide = (preferredSide == .right) ? .left : .right
        return mapPoints(points, side: fallback, minConfidence: minConfidence)
    }

    private static func mapPoints(
        _ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
        side: PoseSide,
        minConfidence: VNConfidence
    ) -> [Joint: CGPoint]? {
        let mapping: [(Joint, VNHumanBodyPoseObservation.JointName)]
        switch side {
        case .left:
            mapping = [
                (.shoulder, .leftShoulder),
                (.elbow, .leftElbow),
                (.wrist, .leftWrist),
                (.hip, .leftHip),
                (.knee, .leftKnee),
                (.ankle, .leftAnkle)
            ]
        case .right:
            mapping = [
                (.shoulder, .rightShoulder),
                (.elbow, .rightElbow),
                (.wrist, .rightWrist),
                (.hip, .rightHip),
                (.knee, .rightKnee),
                (.ankle, .rightAnkle)
            ]
        }

        var joints: [Joint: CGPoint] = [:]
        for (joint, name) in mapping {
            guard let point = points[name], point.confidence >= minConfidence else {
                return nil
            }
            let location = point.location
            joints[joint] = CGPoint(x: location.x, y: 1.0 - location.y)
        }
        return joints
    }

    private static func estimatedFPS(from times: [Double]) -> Double? {
        guard times.count >= 2 else { return nil }
        var deltas: [Double] = []
        deltas.reserveCapacity(times.count - 1)
        for i in 1..<times.count {
            let delta = times[i] - times[i - 1]
            if delta > 0 {
                deltas.append(delta)
            }
        }
        guard !deltas.isEmpty else { return nil }
        let avg = deltas.reduce(0, +) / Double(deltas.count)
        return avg > 0 ? (1.0 / avg) : nil
    }

    private static func imageOrientation(from transform: CGAffineTransform) -> CGImagePropertyOrientation {
        func approx(_ value: CGFloat, _ target: CGFloat) -> Bool {
            abs(value - target) < 0.001
        }

        let a = transform.a
        let b = transform.b
        let c = transform.c
        let d = transform.d

        if approx(a, 0) && approx(b, 1) && approx(c, -1) && approx(d, 0) { return .right }
        if approx(a, 0) && approx(b, -1) && approx(c, 1) && approx(d, 0) { return .left }
        if approx(a, 1) && approx(b, 0) && approx(c, 0) && approx(d, 1) { return .up }
        if approx(a, -1) && approx(b, 0) && approx(c, 0) && approx(d, -1) { return .down }

        if approx(a, -1) && approx(b, 0) && approx(c, 0) && approx(d, 1) { return .upMirrored }
        if approx(a, 1) && approx(b, 0) && approx(c, 0) && approx(d, -1) { return .downMirrored }
        if approx(a, 0) && approx(b, 1) && approx(c, 1) && approx(d, 0) { return .rightMirrored }
        if approx(a, 0) && approx(b, -1) && approx(c, -1) && approx(d, 0) { return .leftMirrored }

        return .up
    }

    private static func uiImageOrientation(from orientation: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private static func drawOverlay(into buffer: CVPixelBuffer, joints: [Joint: CGPoint]) {
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
            let x = p.x * size.width
            let y = (1.0 - p.y) * size.height
            return CGPoint(x: x, y: y)
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

private struct PoseSampleJSON: Decodable {
    let fps: Double
    let frames: [PoseSampleFrame]
}

private struct PoseSampleFrame: Decodable {
    let t: Double
    let points: [String: [Double]]
}

private extension Dictionary where Key == String, Value == [Double] {
    func toJointMap() -> [Joint: CGPoint] {
        var map: [Joint: CGPoint] = [:]
        for (key, value) in self {
            guard let joint = Joint(rawValue: key), value.count >= 2 else { continue }
            map[joint] = CGPoint(x: value[0], y: value[1])
        }
        return map
    }
}
