import SwiftUI
import SwiftData
import RealityKit
import QuickLook

/// Full-screen scanning experience: live Object Capture camera plus step-by-step controls,
/// followed by on-device reconstruction of the captured photos into a 3D model.
struct ScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var captureModel = CaptureModel()
    @State private var previewModelURL: URL?
    /// Fetched when the scanner opens, since that's where the object is.
    @State private var scanLocation: ScanLocation?

    var body: some View {
        Group {
            if !CaptureModel.isSupported {
                ContentUnavailableView(
                    "Scanning Not Supported",
                    systemImage: "camera.metering.unknown",
                    description: Text("Object Capture requires an iPhone or iPad with LiDAR.")
                )
            } else if let errorMessage = captureModel.setupErrorMessage {
                ScanStatusView(
                    title: "Couldn't Start Scan",
                    message: errorMessage,
                    buttonTitle: "Try Again",
                    action: captureModel.restart
                )
            } else if case .notStarted = captureModel.reconstructionStatus {
                captureContent
            } else {
                reconstructionContent
            }
        }
        .task {
            if CaptureModel.isSupported, captureModel.session == nil {
                captureModel.startNewScan()
            }
            scanLocation = await ScanLocation.current()
        }
        .onDisappear {
            captureModel.cancelScan()
        }
        .onChange(of: captureModel.reconstructionStatus) { _, newStatus in
            if case .finished = newStatus {
                saveToCollection()
            }
        }
        .quickLookPreview($previewModelURL)
    }

    private func saveToCollection() {
        guard let scanFolder = captureModel.scanFolder else { return }
        modelContext.insert(CollectedObject(
            id: scanFolder.id,
            modelPath: scanFolder.relativeModelPath,
            latitude: scanLocation?.latitude,
            longitude: scanLocation?.longitude,
            placeName: scanLocation?.placeName
        ))
    }

    // MARK: - Capture

    @ViewBuilder
    private var captureContent: some View {
        if let session = captureModel.session, captureModel.state.showsCameraFeed {
            // The camera fills the screen edge to edge, but the controls stay inside
            // the safe area so the home indicator's gesture zone can't swallow taps.
            ZStack {
                ObjectCaptureView(session: session)
                    .ignoresSafeArea()

                VStack {
                    HStack(alignment: .top) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                        Spacer()
                        #if DEBUG
                        ScanDebugLabel(session: session)
                        #endif
                    }
                    .padding(.horizontal)
                    Spacer()
                    ScanControlsView(captureModel: captureModel)
                        .padding(.bottom, 16)
                }
            }
        } else if case .failed(let error) = captureModel.state {
            ScanStatusView(
                title: "Scan Failed",
                message: error.localizedDescription,
                buttonTitle: "Try Again",
                action: captureModel.restart
            )
        } else {
            // `.finishing` / `.completed`: photos are being flushed before reconstruction begins.
            ProgressView("Saving photos…")
        }
    }

    // MARK: - Reconstruction

    @ViewBuilder
    private var reconstructionContent: some View {
        switch captureModel.reconstructionStatus {
        case .notStarted:
            EmptyView()
        case .inProgress(let fractionComplete):
            ReconstructionProgressView(
                fractionComplete: fractionComplete,
                imageCount: captureModel.scanFolder?.imageCount ?? 0
            )
        case .finished(let modelURL):
            ContentUnavailableView {
                Label("Model Ready", systemImage: "cube.transparent")
            } description: {
                Text("Your scan has been added to your collection.")
            } actions: {
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                Button("View Model") { previewModelURL = modelURL }
                    .buttonStyle(.glass)
            }
        case .failed(let message):
            ScanStatusView(
                title: "Couldn't Build Model",
                message: message,
                buttonTitle: "Try Again",
                action: captureModel.restart
            )
        }
    }
}

/// Progress bar shown while photogrammetry turns the captured photos into a model.
private struct ReconstructionProgressView: View {
    let fractionComplete: Double
    let imageCount: Int

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: fractionComplete) {
                Text("Building your model…")
                    .font(.headline)
            } currentValueLabel: {
                Text(fractionComplete, format: .percent.precision(.fractionLength(0)))
            }
            Text("Processing \(imageCount) photos. Keep Curio open — this can take a few minutes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

/// The single primary action for the current capture step.
private struct ScanControlsView: View {
    let captureModel: CaptureModel

    var body: some View {
        switch captureModel.state {
        case .ready:
            Button("Continue", action: captureModel.startDetecting)
                .buttonStyle(.glassProminent)
        case .detecting:
            Button("Start Capture", action: captureModel.startCapturing)
                .buttonStyle(.glassProminent)
        case .capturing:
            Button("Finish", action: captureModel.finishCapturing)
                .buttonStyle(.glassProminent)
        default:
            EmptyView()
        }
    }
}

#if DEBUG
/// Temporary on-screen readout of the session's state and live feedback hints.
private struct ScanDebugLabel: View {
    let session: ObjectCaptureSession

    var body: some View {
        VStack(alignment: .leading) {
            Text("State: \(String(describing: session.state))")
            Text("Feedback: \(session.feedback.map { String(describing: $0) }.sorted().joined(separator: ", "))")
        }
        .font(.caption.monospaced())
        .padding(8)
        .background(.black.opacity(0.6), in: .rect(cornerRadius: 8))
        .foregroundStyle(.white)
    }
}
#endif

/// Simple centered message with one action, used for completion and error states.
private struct ScanStatusView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Text(title)
        } description: {
            Text(message)
        } actions: {
            Button(buttonTitle, action: action)
                .buttonStyle(.glassProminent)
        }
    }
}

private extension ObjectCaptureSession.CaptureState {
    /// The live camera is only shown while the user is actively framing or capturing.
    var showsCameraFeed: Bool {
        switch self {
        case .initializing, .ready, .detecting, .capturing:
            true
        default:
            false
        }
    }
}
