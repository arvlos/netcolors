import Foundation
import CoreLocation

/// Converts GPS coordinates to geohash for privacy-preserving location sharing.
/// Precision 6 = ~1.2km x 0.6km cell (default for sharing).
/// Precision 5 = ~4.9km x 4.9km cell (extra privacy).
struct GeoHasher {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Encode latitude/longitude to geohash string.
    static func encode(latitude: Double, longitude: Double, precision: Int = 6) -> String {
        var latRange: (min: Double, max: Double) = (-90.0, 90.0)
        var lonRange: (min: Double, max: Double) = (-180.0, 180.0)

        var hash = ""
        var bit = 0
        var charIndex = 0
        var isEven = true

        while hash.count < precision {
            if isEven {
                let mid = (lonRange.min + lonRange.max) / 2
                if longitude >= mid {
                    charIndex = charIndex | (1 << (4 - bit))
                    lonRange.min = mid
                } else {
                    lonRange.max = mid
                }
            } else {
                let mid = (latRange.min + latRange.max) / 2
                if latitude >= mid {
                    charIndex = charIndex | (1 << (4 - bit))
                    latRange.min = mid
                } else {
                    latRange.max = mid
                }
            }

            isEven.toggle()
            bit += 1

            if bit == 5 {
                hash.append(base32[charIndex])
                bit = 0
                charIndex = 0
            }
        }

        return hash
    }
}
