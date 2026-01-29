import AVKit
import SwiftUI

struct LivePoseView: View {
    @ObservedObject var viewModel: LivePoseViewModel
    @Binding var selectedLift: LiftType

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                CameraPreview(session: viewModel.cameraService.captureSession)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if let joints = viewModel.latestJoints {
                    PoseOverlayView(joints: joints)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(height: 280)
            .overlay(alignment: .topLeading) {
                Text(viewModel.statusMessage)
                    .font(.caption.weight(.semibold))
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(10)
            }

            HStack(spacing: 12) {
                Button(viewModel.isRunning ? "Stop" : "Start") {
                    if viewModel.isRunning {
                        viewModel.stop()
                    } else {
                        viewModel.start()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Analyze Recent") {
                    viewModel.analyzeRecent()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isRunning)
            }

            HStack(spacing: 12) {
                Button(viewModel.isRecording ? "Stop Recording" : "Record") {
                    if viewModel.isRecording {
                        viewModel.stopRecording()
                    } else {
                        viewModel.startRecording()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isRunning)

                if viewModel.isRecording {
                    Text("Recording...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Text("Reps: \(viewModel.repCount)")
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.feedbackMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }

            if let recordingURL = viewModel.recordingURL {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording Preview")
                        .font(.headline)
                    VideoPlayer(player: AVPlayer(url: recordingURL))
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if let report = viewModel.report {
                ReportView(report: report)
            } else {
                Text("Capture a few reps then tap Analyze Recent.")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            viewModel.selectedLift = selectedLift
        }
        .onChange(of: selectedLift) { newValue in
            viewModel.selectedLift = newValue
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

struct PoseOverlayView: View {
    let joints: [Joint: CGPoint]

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let connections: [(Joint, Joint)] = [
                    (.shoulder, .elbow),
                    (.elbow, .wrist),
                    (.shoulder, .hip),
                    (.hip, .knee),
                    (.knee, .ankle)
                ]

                func point(_ joint: Joint) -> CGPoint? {
                    guard let p = joints[joint] else { return nil }
                    return CGPoint(x: p.x * size.width, y: p.y * size.height)
                }

                var path = Path()
                for (a, b) in connections {
                    if let pa = point(a), let pb = point(b) {
                        path.move(to: pa)
                        path.addLine(to: pb)
                    }
                }
                context.stroke(path, with: .color(.black), lineWidth: 2.5)

                for joint in [Joint.shoulder, .elbow, .wrist, .hip, .knee, .ankle] {
                    if let p = point(joint) {
                        let rect = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: rect), with: .color(.red))
                    }
                }
            }
        }
    }
}
