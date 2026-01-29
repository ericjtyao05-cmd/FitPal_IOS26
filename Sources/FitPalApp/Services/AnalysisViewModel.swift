import Foundation
import Combine

final class AnalysisViewModel: ObservableObject {
    @Published var selectedLift: LiftType = .squat
    @Published var report: AnalysisReport?
    @Published var isAnalyzing: Bool = false
    @Published var errorMessage: String?
    @Published var sourceLabel: String?
    @Published var overlayURL: URL?

    func analyzeSample() {
        isAnalyzing = true
        errorMessage = nil
        report = nil
        overlayURL = nil
        sourceLabel = "Built-in demo"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let series = try PoseDataLoader.loadSample(for: self.selectedLift)
                let report = AnalysisPipeline.analyze(series: series, liftType: self.selectedLift)
                DispatchQueue.main.async {
                    self.report = report
                    self.isAnalyzing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load sample data: \(error.localizedDescription)"
                    self.isAnalyzing = false
                }
            }
        }
    }

    func analyzeVideo(url: URL) {
        isAnalyzing = true
        errorMessage = nil
        report = nil
        overlayURL = nil
        sourceLabel = url.lastPathComponent

        DispatchQueue.global(qos: .userInitiated).async {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            var overlayURL: URL?
            var report: AnalysisReport?
            var errorMessage: String?

            do {
                overlayURL = try VideoPoseExtractor.renderOverlayVideo(from: url, preferredSide: .right, targetFPS: 15.0)
            } catch {
                errorMessage = "Failed to render overlay: \(error.localizedDescription)"
            }

            if errorMessage == nil {
                do {
                    let series = try VideoPoseExtractor.extractPoseSeries(from: url, preferredSide: .right, targetFPS: 15.0)
                    report = AnalysisPipeline.analyze(series: series, liftType: self.selectedLift)
                } catch {
                    errorMessage = "Failed to analyze video: \(error.localizedDescription)"
                }
            }

            DispatchQueue.main.async {
                self.overlayURL = overlayURL
                self.report = report
                self.errorMessage = errorMessage
                self.isAnalyzing = false
            }
        }
    }
}
