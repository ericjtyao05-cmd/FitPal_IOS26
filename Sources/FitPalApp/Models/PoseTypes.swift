import Foundation
import CoreGraphics

enum Joint: String, CaseIterable, Codable {
    case hip
    case knee
    case ankle
    case shoulder
    case elbow
    case wrist
}

struct PoseFrame: Identifiable {
    let id: Int
    let time: Double
    let points: [Joint: CGPoint]
}

struct PoseSeries {
    let fps: Double
    let frames: [PoseFrame]
}

enum PoseError: Error {
    case missingJoint(Joint)
    case invalidData
    case missingVideoTrack
    case cannotReadVideo
    case noPoseDetected
    case assetReaderFailed
}

extension PoseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingJoint(let joint):
            return "Missing joint data: \(joint.rawValue)."
        case .invalidData:
            return "Invalid pose data."
        case .missingVideoTrack:
            return "No video track found in the file."
        case .cannotReadVideo:
            return "Unable to read video frames from this file."
        case .noPoseDetected:
            return "No pose detected in the video."
        case .assetReaderFailed:
            return "Video reader failed while decoding."
        }
    }
}

struct Vector2 {
    let x: CGFloat
    let y: CGFloat

    static func -(lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    func dot(_ other: Vector2) -> CGFloat {
        x * other.x + y * other.y
    }

    var magnitude: CGFloat {
        sqrt(x * x + y * y)
    }
}

extension CGPoint {
    var vector: Vector2 { Vector2(x: x, y: y) }
}

func angleDegrees(a: CGPoint, b: CGPoint, c: CGPoint) -> Double {
    let ba = a.vector - b.vector
    let bc = c.vector - b.vector
    let denom = max(ba.magnitude * bc.magnitude, 0.0001)
    let cosine = max(min(ba.dot(bc) / denom, 1.0), -1.0)
    return Double(acos(cosine) * 180.0 / .pi)
}

func angleFromVerticalDegrees(a: CGPoint, b: CGPoint) -> Double {
    let v = b.vector - a.vector
    let vertical = Vector2(x: 0, y: 1)
    let denom = max(v.magnitude * vertical.magnitude, 0.0001)
    let cosine = max(min(v.dot(vertical) / denom, 1.0), -1.0)
    return Double(acos(cosine) * 180.0 / .pi)
}
