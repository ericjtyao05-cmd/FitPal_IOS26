import Foundation
import CoreGraphics

struct AnalysisPipeline {
    static func analyze(series: PoseSeries, liftType: LiftType) -> AnalysisReport {
        let segments = RepSegmenter.segment(series: series, liftType: liftType)
        let metrics = MetricsCalculator.calculate(series: series, segments: segments, liftType: liftType)
        let reps = RuleEngine.evaluate(metrics: metrics, liftType: liftType)
        let summaryIssues = reps.flatMap { $0.issues }
        return AnalysisReport(liftType: liftType, reps: reps, summaryIssues: Array(Set(summaryIssues)).sorted())
    }
}
