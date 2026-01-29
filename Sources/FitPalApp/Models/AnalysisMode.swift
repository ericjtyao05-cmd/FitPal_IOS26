import Foundation

enum AnalysisMode: String, CaseIterable, Identifiable {
    case sample
    case live

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sample: return "Analysis"
        case .live: return "Live Camera"
        }
    }
}
