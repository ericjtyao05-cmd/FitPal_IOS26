import Foundation

struct RepAnalysis: Identifiable {
    let id = UUID()
    let index: Int
    let angles: AngleMetrics
    let rom: ROMMetrics
    let speeds: SpeedMetrics
    let issues: [String]

    var angleSummary: String {
        angles.summary
    }

    var romSummary: String {
        rom.summary
    }

    var speedSummary: String {
        speeds.summary
    }
}

struct AnalysisReport {
    let liftType: LiftType
    let reps: [RepAnalysis]
    let summaryIssues: [String]

    var repCount: Int { reps.count }
}

struct AngleMetrics {
    let bottomHipAngle: Double?
    let bottomKneeAngle: Double?
    let bottomElbowAngle: Double?
    let bottomTorsoAngle: Double?

    var summary: String {
        let parts: [String] = [
            formatted(name: "Hip", value: bottomHipAngle),
            formatted(name: "Knee", value: bottomKneeAngle),
            formatted(name: "Elbow", value: bottomElbowAngle),
            formatted(name: "Torso", value: bottomTorsoAngle)
        ].compactMap { $0 }
        return parts.isEmpty ? "n/a" : parts.joined(separator: ", ")
    }

    private func formatted(name: String, value: Double?) -> String? {
        guard let value else { return nil }
        return "\(name) \(String(format: "%.0f", value))°"
    }
}

struct ROMMetrics {
    let depthScore: Double?
    let depthPass: Bool?
    let lockoutPass: Bool?

    var summary: String {
        var parts: [String] = []
        if let depthScore {
            parts.append("Depth \(String(format: "%.3f", depthScore))")
        }
        if let depthPass {
            parts.append(depthPass ? "ROM OK" : "ROM Short")
        }
        if let lockoutPass {
            parts.append(lockoutPass ? "Lockout OK" : "Lockout Short")
        }
        return parts.isEmpty ? "n/a" : parts.joined(separator: ", ")
    }
}

struct SpeedMetrics {
    let eccentricAvg: Double
    let concentricAvg: Double
    let eccentricStd: Double

    var summary: String {
        let ecc = String(format: "%.3f", eccentricAvg)
        let con = String(format: "%.3f", concentricAvg)
        let varStr = String(format: "%.3f", eccentricStd)
        return "Ecc \(ecc), Con \(con), Var \(varStr)"
    }
}
