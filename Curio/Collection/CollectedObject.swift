import Foundation
import SwiftData

/// One scanned object in the user's collection.
@Model
final class CollectedObject {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    /// e.g. `"Scans/<id>/model.usdz"`, relative to `URL.documentsDirectory`.
    var modelPath: String

    init(id: UUID, createdAt: Date = .now, modelPath: String) {
        self.id = id
        self.createdAt = createdAt
        self.modelPath = modelPath
    }

    var modelURL: URL {
        URL.documentsDirectory.appending(path: modelPath, directoryHint: .notDirectory)
    }
}
