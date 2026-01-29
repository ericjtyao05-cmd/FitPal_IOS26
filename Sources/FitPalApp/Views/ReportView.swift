import SwiftUI

struct ReportView: View {
    let report: AnalysisReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Lift: \(report.liftType.displayName)")
                Text("Reps: \(report.repCount)")
                Text("Conclusion: \(report.summaryIssues.isEmpty ? "No major issues detected." : report.summaryIssues.joined(separator: ", "))")
            }
            .font(.subheadline)
        }
    }
}
