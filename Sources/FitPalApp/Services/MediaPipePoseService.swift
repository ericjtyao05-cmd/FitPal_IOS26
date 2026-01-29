import AVFoundation
import CoreGraphics
import Foundation

enum PoseSide {
    case left
    case right
}

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision

final class MediaPipePoseService: NSObject {
    enum ServiceError: Error {
        case modelMissing
        case failedToCreateLandmarker
    }

    var isAvailable: Bool { true }
    var onPoseLandmarks: (([Joint: CGPoint], Int) -> Void)?
    var preferredSide: PoseSide = .right

    private var landmarker: PoseLandmarker?

    func start(modelPath: String) throws {
        let options = PoseLandmarkerOptions()
        let baseOptions = BaseOptions()
        baseOptions.modelAssetPath = modelPath
        options.baseOptions = baseOptions
        options.runningMode = .liveStream
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.poseLandmarkerLiveStreamDelegate = self

        do {
            landmarker = try PoseLandmarker(options: options)
        } catch {
            throw ServiceError.failedToCreateLandmarker
        }
    }

    func stop() {
        landmarker = nil
    }

    func process(sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestampMs = Int(CMTimeGetSeconds(timestamp) * 1000.0)
        process(pixelBuffer: imageBuffer, timestampMs: timestampMs)
    }

    private func process(pixelBuffer: CVPixelBuffer, timestampMs: Int) {
        guard let landmarker else { return }
        do {
            let image = try MPImage(pixelBuffer: pixelBuffer)
            try landmarker.detectAsync(image: image, timestampInMilliseconds: timestampMs)
        } catch {
            return
        }
    }

    private func jointIndexMap() -> [Joint: Int] {
        switch preferredSide {
        case .left:
            return [
                .shoulder: 11,
                .elbow: 13,
                .wrist: 15,
                .hip: 23,
                .knee: 25,
                .ankle: 27
            ]
        case .right:
            return [
                .shoulder: 12,
                .elbow: 14,
                .wrist: 16,
                .hip: 24,
                .knee: 26,
                .ankle: 28
            ]
        }
    }
}

extension MediaPipePoseService: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        guard error == nil else { return }
        guard let landmarks = result?.landmarks.first else { return }

        var joints: [Joint: CGPoint] = [:]
        let indexMap = jointIndexMap()
        for (joint, index) in indexMap {
            guard index < landmarks.count else { continue }
            let landmark = landmarks[index]
            joints[joint] = CGPoint(x: CGFloat(landmark.x), y: CGFloat(landmark.y))
        }

        if !joints.isEmpty {
            onPoseLandmarks?(joints, timestampInMilliseconds)
        }
    }
}

#else

final class MediaPipePoseService {
    enum ServiceError: Error {
        case unavailable
    }

    var isAvailable: Bool { false }
    var onPoseLandmarks: (([Joint: CGPoint], Int) -> Void)?
    var preferredSide: PoseSide = .right

    func start(modelPath: String) throws {
        throw ServiceError.unavailable
    }

    func stop() {
    }

    func process(sampleBuffer: CMSampleBuffer) {
    }
}
#endif
