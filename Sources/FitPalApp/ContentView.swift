import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var sampleViewModel = AnalysisViewModel()
    @StateObject private var liveViewModel = LivePoseViewModel()
    @State private var selectedLift: LiftType = .squat
    @State private var mode: AnalysisMode = .sample
    @State private var showVideoImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    modePicker
                    liftPicker

                    if mode == .sample {
                        sampleControls
                        sampleStatus
                        if let overlayURL = sampleViewModel.overlayURL {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overlay Preview")
                                    .font(.headline)
                                VideoPlayer(player: AVPlayer(url: overlayURL))
                                    .frame(height: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        if let report = sampleViewModel.report {
                            ReportView(report: report)
                        }
                    } else {
                        LivePoseView(viewModel: liveViewModel, selectedLift: $selectedLift)
                    }

                    recordingGuide
                }
                .padding(20)
            }
            .navigationTitle("FitPal")
        }
        .onAppear {
            syncLift()
        }
        .onChange(of: selectedLift) { _ in
            syncLift()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Action Quality")
                .font(.title2.weight(.semibold))
            Text("Analyzes 2D pose data for squat / bench / deadlift.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(AnalysisMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var liftPicker: some View {
        Picker("Lift", selection: $selectedLift) {
            ForEach(LiftType.allCases) { lift in
                Text(lift.displayName).tag(lift)
            }
        }
        .pickerStyle(.segmented)
    }

    private var sampleControls: some View {
        VStack(spacing: 12) {
            Button {
                sampleViewModel.analyzeSample()
            } label: {
                Text(sampleViewModel.isAnalyzing ? "Analyzing..." : "Analyze")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sampleViewModel.isAnalyzing)

            Button {
                showVideoImporter = true
            } label: {
                Text("Upload Video (MP4/MOV)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(sampleViewModel.isAnalyzing)
        }
        .fileImporter(
            isPresented: $showVideoImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                sampleViewModel.analyzeVideo(url: url)
            case .failure(let error):
                sampleViewModel.errorMessage = "Failed to import video: \(error.localizedDescription)"
            }
        }
    }

    private var sampleStatus: some View {
        Group {
            if let error = sampleViewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else if let source = sampleViewModel.sourceLabel {
                Text("Source: \(source)")
                    .foregroundColor(.secondary)
            } else if sampleViewModel.isAnalyzing {
                Text("Processing video frames…")
                    .foregroundColor(.secondary)
            } else if sampleViewModel.report == nil {
                Text("Select a lift and run analysis to see results.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func syncLift() {
        sampleViewModel.selectedLift = selectedLift
        liveViewModel.selectedLift = selectedLift
    }

    private var recordingGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to record")
                .font(.headline)
            Text("Side view • Full body in frame • Camera at hip height • 6–10 ft away • Good lighting")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }
}
