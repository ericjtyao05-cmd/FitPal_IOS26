import Foundation

struct RuleEngine {
    static func evaluate(metrics: [RepMetrics], liftType: LiftType) -> [RepAnalysis] {
        let standards = LiftStandards.default
        return metrics.map { metric in
            var issues: [String] = []
            var rom = metric.rom

            switch liftType {
            case .squat:
                if let depth = metric.rom.depthScore {
                    let pass = depth >= standards.squat.depthThreshold
                    rom = ROMMetrics(depthScore: depth, depthPass: pass, lockoutPass: nil)
                    if !pass { issues.append("Depth too shallow") }
                }
                if let knee = metric.angles.bottomKneeAngle, knee > standards.squat.kneeAngleMax {
                    issues.append("Knee angle too open")
                }
                if let hip = metric.angles.bottomHipAngle, hip > standards.squat.hipAngleMax {
                    issues.append("Hip angle too open")
                }
                if let torso = metric.angles.bottomTorsoAngle, torso > standards.squat.torsoAngleMax {
                    issues.append("Excessive forward lean")
                }
                if !standards.squat.eccentricRange.contains(metric.speeds.eccentricAvg) {
                    issues.append("Eccentric speed out of range")
                }
                if !standards.squat.concentricRange.contains(metric.speeds.concentricAvg) {
                    issues.append("Concentric speed out of range")
                }
                if metric.speeds.eccentricStd > 0.25 {
                    issues.append("Eccentric tempo unstable")
                }
            case .bench:
                if let depth = metric.rom.depthScore {
                    let pass = depth >= standards.bench.touchThreshold
                    let lockout = metric.rom.lockoutPass
                    rom = ROMMetrics(depthScore: depth, depthPass: pass, lockoutPass: lockout)
                    if !pass { issues.append("Touch depth short") }
                }
                if let lockout = metric.rom.lockoutPass, lockout == false {
                    issues.append("Lockout incomplete")
                }
                if !standards.bench.eccentricRange.contains(metric.speeds.eccentricAvg) {
                    issues.append("Eccentric speed out of range")
                }
                if !standards.bench.concentricRange.contains(metric.speeds.concentricAvg) {
                    issues.append("Concentric speed out of range")
                }
                if metric.speeds.eccentricStd > 0.25 {
                    issues.append("Eccentric tempo unstable")
                }
            case .deadlift:
                let lockout = metric.rom.lockoutPass
                rom = ROMMetrics(depthScore: nil, depthPass: nil, lockoutPass: lockout)
                if let lockout, lockout == false {
                    issues.append("Lockout incomplete")
                }
                if let torso = metric.angles.bottomTorsoAngle, torso > standards.deadlift.torsoAngleMax {
                    issues.append("Back angle too horizontal")
                }
                if !standards.deadlift.eccentricRange.contains(metric.speeds.eccentricAvg) {
                    issues.append("Eccentric speed out of range")
                }
                if !standards.deadlift.concentricRange.contains(metric.speeds.concentricAvg) {
                    issues.append("Concentric speed out of range")
                }
                if metric.speeds.eccentricStd > 0.25 {
                    issues.append("Eccentric tempo unstable")
                }
            }

            return RepAnalysis(
                index: metric.index,
                angles: metric.angles,
                rom: rom,
                speeds: metric.speeds,
                issues: issues
            )
        }
    }
}
