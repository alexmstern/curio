import Foundation
import SwiftData

/// One scanned object in the user's collection.
@Model
final class CollectedObject {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    /// e.g. `"Scans/<id>/model.usdz"`, relative to `URL.documentsDirectory`.
    var modelPath: String

    // Where the object was scanned. Optional if location access is denied.
    var latitude: Double?
    var longitude: Double?
    var placeName: String?

    init(
        id: UUID,
        createdAt: Date = .now,
        modelPath: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        placeName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modelPath = modelPath
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
    }

    var modelURL: URL {
        URL.documentsDirectory.appending(path: modelPath, directoryHint: .notDirectory)
    }
}
