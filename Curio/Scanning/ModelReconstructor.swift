import Foundation
import RealityKit

/// Turns a folder of Object Capture photos into a 3D model (`.usdz`) on-device.
enum ModelReconstructor {
    enum ReconstructionError: LocalizedError {
        case endedWithoutResult

        var errorDescription: String? {
            "Reconstruction ended before a model was produced."
        }
    }

    /// Runs photogrammetry on `scanFolder`'s images and writes the result to `scanFolder.modelURL`.
    static func reconstruct(
        scanFolder: ScanFolder,
        onProgress: (Double) -> Void
    ) async throws -> URL {
        var configuration = PhotogrammetrySession.Configuration()
        configuration.checkpointDirectory = scanFolder.checkpointsURL

        let session = try PhotogrammetrySession(input: scanFolder.imagesURL, configuration: configuration)
        try session.process(requests: [.modelFile(url: scanFolder.modelURL)])

        for try await output in session.outputs {
            switch output {
            case .requestProgress(_, let fractionComplete):
                onProgress(fractionComplete)
            case .requestError(_, let error):
                throw error
            case .processingCancelled:
                throw CancellationError()
            case .processingComplete:
                return scanFolder.modelURL
            default:
                break
            }
        }
        throw ReconstructionError.endedWithoutResult
    }
}
