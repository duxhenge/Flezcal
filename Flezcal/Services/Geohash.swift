import Foundation

/// Computes a geohash string for the given coordinates.
/// Used to group spots by region (~20 km cells at precision 4)
/// for computing regional average analytics.
enum Geohash {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Returns the first `precision` characters of the geohash for (lat, lon).
    /// Default precision 4 gives ~20 km x 20 km cells.
    static func encode(latitude: Double, longitude: Double, precision: Int = 4) -> String {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var bits = 0
        var charIndex = 0
        var isEven = true

        while hash.count < precision {
            if isEven {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid {
                    charIndex = charIndex * 2 + 1
                    lonRange.0 = mid
                } else {
                    charIndex *= 2
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid {
                    charIndex = charIndex * 2 + 1
                    latRange.0 = mid
                } else {
                    charIndex *= 2
                    latRange.1 = mid
                }
            }
            isEven.toggle()
            bits += 1
            if bits == 5 {
                hash.append(base32[charIndex])
                bits = 0
                charIndex = 0
            }
        }
        return hash
    }
}
