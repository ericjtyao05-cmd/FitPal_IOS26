import Foundation

enum LiftType: String, CaseIterable, Identifiable {
    case squat
    case bench
    case deadlift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .squat: return "Squat"
        case .bench: return "Bench"
        case .deadlift: return "Deadlift"
        }
    }
}
