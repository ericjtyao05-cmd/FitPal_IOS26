import Foundation
import CoreGraphics

struct RepMetrics {
    let index: Int
    let angles: AngleMetrics
    let rom: ROMMetrics
    let speeds: SpeedMetrics
    let segment: RepSegment
}

struct MetricsCalculator {
    static func calculate(series: PoseSeries, segments: [RepSegment], liftType: LiftType) -> [RepMetrics] {
        var results: [RepMetrics] = []
        for (index, segment) in segments.enumerated() {
            guard segment.endIndex < series.frames.count else { continue }
            let bottom = series.frames[segment.bottomIndex]
            let start = series.frames[segment.startIndex]
            let end = series.frames[segment.endIndex]

            let angles = computeAngles(bottomFrame: bottom, liftType: liftType)
            let rom = computeROM(startFrame: start, bottomFrame: bottom, endFrame: end, liftType: liftType)
            let speeds = computeSpeeds(series: series, segment: segment, liftType: liftType)

            results.append(RepMetrics(index: index, angles: angles, rom: rom, speeds: speeds, segment: segment))
        }
        return results
    }

    private static func computeAngles(bottomFrame: PoseFrame, liftType: LiftType) -> AngleMetrics {
        switch liftType {
        case .squat:
            let hipAngle = angle(bottomFrame, a: .shoulder, b: .hip, c: .knee)
            let kneeAngle = angle(bottomFrame, a: .hip, b: .knee, c: .ankle)
            let torsoAngle = torsoAngle(bottomFrame)
            return AngleMetrics(bottomHipAngle: hipAngle, bottomKneeAngle: kneeAngle, bottomElbowAngle: nil, bottomTorsoAngle: torsoAngle)
        case .bench:
            let elbow = angle(bottomFrame, a: .shoulder, b: .elbow, c: .wrist)
            return AngleMetrics(bottomHipAngle: nil, bottomKneeAngle: nil, bottomElbowAngle: elbow, bottomTorsoAngle: nil)
        case .deadlift:
            let hipAngle = angle(bottomFrame, a: .shoulder, b: .hip, c: .knee)
            let kneeAngle = angle(bottomFrame, a: .hip, b: .knee, c: .ankle)
            let torsoAngle = torsoAngle(bottomFrame)
            return AngleMetrics(bottomHipAngle: hipAngle, bottomKneeAngle: kneeAngle, bottomElbowAngle: nil, bottomTorsoAngle: torsoAngle)
        }
    }

    private static func computeROM(startFrame: PoseFrame, bottomFrame: PoseFrame, endFrame: PoseFrame, liftType: LiftType) -> ROMMetrics {
        switch liftType {
        case .squat:
            let depth = depthScore(bottomFrame)
            return ROMMetrics(depthScore: depth, depthPass: nil, lockoutPass: nil)
        case .bench:
            let touch = benchTouchScore(bottomFrame)
            let lockout = elbowLockout(endFrame)
            return ROMMetrics(depthScore: touch, depthPass: nil, lockoutPass: lockout)
        case .deadlift:
            let lockout = deadliftLockout(endFrame)
            return ROMMetrics(depthScore: nil, depthPass: nil, lockoutPass: lockout)
        }
    }

    private static func computeSpeeds(series: PoseSeries, segment: RepSegment, liftType: LiftType) -> SpeedMetrics {
        let joint: Joint = (liftType == .bench) ? .wrist : .hip
        let frames = series.frames
        let start = segment.startIndex
        let bottom = segment.bottomIndex
        let end = segment.endIndex
        let fps = series.fps

        func velocities(from: Int, to: Int) -> [Double] {
            guard to > from else { return [] }
            var result: [Double] = []
            for i in from..<(to) {
                guard let y1 = frames[i].points[joint]?.y, let y2 = frames[i + 1].points[joint]?.y else { continue }
                let v = Double(y2 - y1) * fps
                result.append(v)
            }
            return result
        }

        let ecc = velocities(from: start, to: bottom)
        let con = velocities(from: bottom, to: end)
        let eccAvg = ecc.isEmpty ? 0 : ecc.reduce(0, +) / Double(ecc.count)
        let conAvg = con.isEmpty ? 0 : abs(con.reduce(0, +) / Double(con.count))
        let eccStd = standardDeviation(values: ecc)
        return SpeedMetrics(eccentricAvg: abs(eccAvg), concentricAvg: conAvg, eccentricStd: eccStd)
    }

    private static func angle(_ frame: PoseFrame, a: Joint, b: Joint, c: Joint) -> Double? {
        guard let pa = frame.points[a], let pb = frame.points[b], let pc = frame.points[c] else { return nil }
        return angleDegrees(a: pa, b: pb, c: pc)
    }

    private static func torsoAngle(_ frame: PoseFrame) -> Double? {
        guard let hip = frame.points[.hip], let shoulder = frame.points[.shoulder] else { return nil }
        return angleFromVerticalDegrees(a: hip, b: shoulder)
    }

    private static func depthScore(_ frame: PoseFrame) -> Double? {
        guard let hip = frame.points[.hip], let knee = frame.points[.knee] else { return nil }
        return Double(hip.y - knee.y)
    }

    private static func benchTouchScore(_ frame: PoseFrame) -> Double? {
        guard let wrist = frame.points[.wrist], let shoulder = frame.points[.shoulder] else { return nil }
        return Double(wrist.y - shoulder.y)
    }

    private static func elbowLockout(_ frame: PoseFrame) -> Bool? {
        guard let elbow = angle(frame, a: .shoulder, b: .elbow, c: .wrist) else { return nil }
        return elbow >= LiftStandards.default.bench.elbowLockoutMin
    }

    private static func deadliftLockout(_ frame: PoseFrame) -> Bool? {
        guard let hip = angle(frame, a: .shoulder, b: .hip, c: .knee),
              let knee = angle(frame, a: .hip, b: .knee, c: .ankle) else { return nil }
        return hip >= LiftStandards.default.deadlift.hipLockoutMin && knee >= LiftStandards.default.deadlift.kneeLockoutMin
    }
}
