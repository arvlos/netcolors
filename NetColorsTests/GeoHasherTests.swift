import XCTest
@testable import NetColors

final class GeoHasherTests: XCTestCase {

    // MARK: - Known Values

    func testEncodeKnownCoordinate_Moscow() {
        // Red Square: 55.7539, 37.6208
        let hash = GeoHasher.encode(latitude: 55.7539, longitude: 37.6208, precision: 6)
        XCTAssertEqual(hash.count, 6)
        // Geohash for Red Square starts with "ucfv0"
        XCTAssertTrue(hash.hasPrefix("ucfv0"), "Expected Moscow geohash prefix 'ucfv0', got '\(hash)'")
    }

    func testEncodeKnownCoordinate_ZeroZero() {
        // Null Island (0, 0)
        let hash = GeoHasher.encode(latitude: 0.0, longitude: 0.0, precision: 6)
        XCTAssertEqual(hash.count, 6)
        XCTAssertTrue(hash.hasPrefix("s000"), "Expected 's000' prefix for (0,0), got '\(hash)'")
    }

    // MARK: - Precision

    func testPrecisionLength() {
        for precision in 1...9 {
            let hash = GeoHasher.encode(latitude: 55.7539, longitude: 37.6208, precision: precision)
            XCTAssertEqual(hash.count, precision, "Precision \(precision) should produce \(precision) characters")
        }
    }

    func testHigherPrecisionRefinesLower() {
        let low = GeoHasher.encode(latitude: 55.7539, longitude: 37.6208, precision: 4)
        let high = GeoHasher.encode(latitude: 55.7539, longitude: 37.6208, precision: 6)
        XCTAssertTrue(high.hasPrefix(low), "Higher precision '\(high)' should start with lower precision '\(low)'")
    }

    // MARK: - Edge Cases

    func testNorthPole() {
        let hash = GeoHasher.encode(latitude: 90.0, longitude: 0.0, precision: 6)
        XCTAssertEqual(hash.count, 6)
    }

    func testSouthPole() {
        let hash = GeoHasher.encode(latitude: -90.0, longitude: 0.0, precision: 6)
        XCTAssertEqual(hash.count, 6)
    }

    func testDateLine() {
        let hashEast = GeoHasher.encode(latitude: 0.0, longitude: 180.0, precision: 6)
        let hashWest = GeoHasher.encode(latitude: 0.0, longitude: -180.0, precision: 6)
        XCTAssertEqual(hashEast.count, 6)
        XCTAssertEqual(hashWest.count, 6)
    }

    // MARK: - Character Set

    func testBase32Characters() {
        let validChars = Set("0123456789bcdefghjkmnpqrstuvwxyz")
        let hash = GeoHasher.encode(latitude: 55.7539, longitude: 37.6208, precision: 9)
        for char in hash {
            XCTAssertTrue(validChars.contains(char), "Invalid base32 character: \(char)")
        }
    }

    // MARK: - Nearby Points

    func testNearbyPointsSameGeohashAtLowPrecision() {
        // Two points ~100m apart should share geohash at precision 6
        let hash1 = GeoHasher.encode(latitude: 55.7539, longitude: 37.6208, precision: 5)
        let hash2 = GeoHasher.encode(latitude: 55.7545, longitude: 37.6215, precision: 5)
        XCTAssertEqual(hash1, hash2, "Nearby points should share geohash at precision 5")
    }

    func testDistantPointsDifferentGeohash() {
        let moscow = GeoHasher.encode(latitude: 55.7539, longitude: 37.6208, precision: 4)
        let spb = GeoHasher.encode(latitude: 59.9343, longitude: 30.3351, precision: 4)
        XCTAssertNotEqual(moscow, spb, "Moscow and SPb should have different geohashes")
    }
}
