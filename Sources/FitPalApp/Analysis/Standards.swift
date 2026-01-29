import Foundation

struct SquatStandards {
    let depthThreshold: Double
    let kneeAngleMax: Double
    let hipAngleMax: Double
    let torsoAngleMax: Double
    let eccentricRange: ClosedRange<Double>
    let concentricRange: ClosedRange<Double>
}

struct BenchStandards {
    let touchThreshold: Double
    let elbowLockoutMin: Double
    let eccentricRange: ClosedRange<Double>
    let concentricRange: ClosedRange<Double>
}

struct DeadliftStandards {
    let hipLockoutMin: Double
    let kneeLockoutMin: Double
    let torsoAngleMax: Double
    let eccentricRange: ClosedRange<Double>
    let concentricRange: ClosedRange<Double>
}

struct LiftStandards {
    let squat: SquatStandards
    let bench: BenchStandards
    let deadlift: DeadliftStandards

    static let `default` = LiftStandards(
        squat: SquatStandards(
            depthThreshold: 0.02,
            kneeAngleMax: 110,
            hipAngleMax: 120,
            torsoAngleMax: 55,
            eccentricRange: 0.15...1.2,
            concentricRange: 0.15...1.2
        ),
        bench: BenchStandards(
            touchThreshold: 0.08,
            elbowLockoutMin: 165,
            eccentricRange: 0.12...1.2,
            concentricRange: 0.12...1.2
        ),
        deadlift: DeadliftStandards(
            hipLockoutMin: 165,
            kneeLockoutMin: 170,
            torsoAngleMax: 45,
            eccentricRange: 0.12...1.4,
            concentricRange: 0.12...1.4
        )
    )
}
