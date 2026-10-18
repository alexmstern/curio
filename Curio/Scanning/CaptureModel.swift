import Foundation
import RealityKit
import SwiftUI
import UIKit

/// Data structure for the scanning and reconstruction process, including status and output path.
@Observable
final class CaptureModel {
    enum ReconstructionStatus: Equatable {
        case notStarted
        case inProgress(fractionComplete: Double)
        case finished(modelURL: URL)
        case failed(message: String)
    }

    /// Object Capture needs a LiDAR-equipped device (e.g. iPhone 12 Pro or later Pro models).
    static var isSupported: Bool { ObjectCaptureSession.isSupported }

    private(set) var session: ObjectCaptureSession?
    private(set) var scanFolder: ScanFolder?
    private(set) var setupErrorMessage: String?
    private(set) var reconstructionStatus: ReconstructionStatus = .notStarted

    /// Waits for capture to complete, then kicks off reconstruction.
    private var completionTask: Task<Void, Never>?

    var state: ObjectCaptureSession.CaptureState {
        session?.state ?? .initializing
    }

    // MARK: - Session lifecycle

    func startNewScan() {
        do {
            let folder = try ScanFolder.makeNew()

            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = folder.checkpointsURL

            let newSession = ObjectCaptureSession()
            newSession.start(imagesDirectory: folder.imagesURL, configuration: configuration)

            scanFolder = folder
            session = newSession
            setupErrorMessage = nil
            reconstructionStatus = .notStarted
            reconstructWhenCaptureCompletes(newSession)
        } catch {
            setupErrorMessage = error.localizedDescription
        }
    }

    /// Cancels any in-progress scan and starts a fresh one.
    func restart() {
        cancelScan()
        startNewScan()
    }

    /// Stops the current scan. Scans that produced a model are kept (they're collection items);
    /// partial ones are deleted from disk.
    func cancelScan() {
        let previousFolder = scanFolder
        tearDownSession()
        if let previousFolder, !previousFolder.hasModel {
            previousFolder.delete()
        }
    }

    private func tearDownSession() {
        completionTask?.cancel()
        completionTask = nil
        session?.cancel()
        session = nil
        scanFolder = nil
    }

    // MARK: - Capture steps

    /// `.ready` → `.detecting`: shows the bounding box so the user can frame the object.
    func startDetecting() {
        _ = session?.startDetecting()
    }

    /// `.detecting` → `.capturing`: starts taking photos as the user walks around the object.
    func startCapturing() {
        session?.startCapturing()
    }

    /// `.capturing` → `.finishing` → `.completed`: stops capture and flushes photos to disk.
    func finishCapturing() {
        session?.finish()
    }

    // MARK: - Reconstruction

    private func reconstructWhenCaptureCompletes(_ session: ObjectCaptureSession) {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            for await newState in session.stateUpdates {
                if case .completed = newState {
                    await self?.reconstructModel()
                    return
                }
            }
        }
    }

    private func reconstructModel() async {
        guard let scanFolder else { return }

        // Capture and photogrammetry can't run side by side on iPhone (memory/GPU),
        // so release the capture session before reconstructing.
        session = nil
        reconstructionStatus = .inProgress(fractionComplete: 0)

        // Reconstruction takes minutes; stop the screen from auto-locking and suspending the app.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        do {
            let modelURL = try await ModelReconstructor.reconstruct(scanFolder: scanFolder) { fraction in
                reconstructionStatus = .inProgress(fractionComplete: fraction)
            }
            reconstructionStatus = .finished(modelURL: modelURL)
        } catch {
            reconstructionStatus = .failed(message: error.localizedDescription)
        }
    }
}

/// On-disk layout for one scan: `Documents/Scans/<id>/` holding `Images/`, `Checkpoints/` and `model.usdz`.
struct ScanFolder {
    let id: UUID
    let rootURL: URL

    var imagesURL: URL { rootURL.appending(path: "Images/", directoryHint: .isDirectory) }
    var checkpointsURL: URL { rootURL.appending(path: "Checkpoints/", directoryHint: .isDirectory) }
    var modelURL: URL { rootURL.appending(path: "model.usdz", directoryHint: .notDirectory) }
    /// `modelURL` relative to Documents — what gets persisted, since absolute container paths can change.
    var relativeModelPath: String { "Scans/\(id.uuidString)/model.usdz" }

    var hasModel: Bool { FileManager.default.fileExists(atPath: modelURL.path()) }

    var imageCount: Int {
        let contents = try? FileManager.default.contentsOfDirectory(atPath: imagesURL.path())
        return contents?.count ?? 0
    }

    static func makeNew() throws -> ScanFolder {
        let id = UUID()
        let rootURL = URL.documentsDirectory
            .appending(path: "Scans/\(id.uuidString)/", directoryHint: .isDirectory)
        let folder = ScanFolder(id: id, rootURL: rootURL)

        for directoryURL in [folder.imagesURL, folder.checkpointsURL] {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return folder
    }

    func delete() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
