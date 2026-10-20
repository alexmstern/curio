import CoreLocation
import MapKit

/// Where a scan happened: precise coordinates plus a human-readable city.
struct ScanLocation {
    let latitude: Double
    let longitude: Double
    let placeName: String?

    /// Asks for When-In-Use permission if needed, then returns the first location fix.
    /// Returns `nil` if the user denies access or no fix is available.
    static func current() async -> ScanLocation? {
        // Holding a service session prompts for (and keeps) When-In-Use authorization.
        let serviceSession = CLServiceSession(authorization: .whenInUse)
        defer { serviceSession.invalidate() }

        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    return nil
                }
                if let location = update.location {
                    return ScanLocation(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        placeName: await placeName(for: location)
                    )
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func placeName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let mapItems = try? await request.mapItems
        return mapItems?.first?.addressRepresentations?.cityWithContext
    }
}
