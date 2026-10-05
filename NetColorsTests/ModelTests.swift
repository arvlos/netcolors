import XCTest
@testable import NetColors

@MainActor
final class ModelTests: XCTestCase {

    // MARK: - AccessMode

    func testAccessModeRawValues() {
        XCTAssertEqual(AccessMode.fullShutdown.rawValue, "shutdown")
        XCTAssertEqual(AccessMode.whitelist.rawValue, "whitelist")
        XCTAssertEqual(AccessMode.restricted.rawValue, "restricted")
        XCTAssertEqual(AccessMode.unrestricted.rawValue, "unrestricted")
    }

    func testAccessModeCodable() throws {
        for mode in AccessMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(AccessMode.self, from: data)
            XCTAssertEqual(mode, decoded)
        }
    }

    func testAccessModeAllCasesCount() {
        XCTAssertEqual(AccessMode.allCases.count, 4)
    }

    // MARK: - ProbeEndpoint

    func testProbeEndpointInit() {
        let ep = ProbeEndpoint(domain: "google.com", group: .usuallyAvailable)
        XCTAssertEqual(ep.domain, "google.com")
        XCTAssertEqual(ep.group, .usuallyAvailable)
        XCTAssertTrue(ep.isDefault)
    }

    func testProbeEndpointCustom() {
        let ep = ProbeEndpoint(domain: "mysite.com", group: .custom, isDefault: false)
        XCTAssertFalse(ep.isDefault)
        XCTAssertEqual(ep.group, .custom)
    }

    func testProbeEndpointUniqueIDs() {
        let ep1 = ProbeEndpoint(domain: "a.com", group: .dns)
        let ep2 = ProbeEndpoint(domain: "a.com", group: .dns)
        XCTAssertNotEqual(ep1.id, ep2.id, "Each endpoint should have a unique UUID")
    }

    func testProbeEndpointCodable() throws {
        let ep = ProbeEndpoint(domain: "ya.ru", group: .whitelist)
        let data = try JSONEncoder().encode(ep)
        let decoded = try JSONDecoder().decode(ProbeEndpoint.self, from: data)
        XCTAssertEqual(decoded.domain, ep.domain)
        XCTAssertEqual(decoded.group, ep.group)
        XCTAssertEqual(decoded.isDefault, ep.isDefault)
    }

    // MARK: - ProbeGroup

    func testProbeGroupAllCases() {
        let groups = ProbeGroup.allCases
        XCTAssertEqual(groups.count, 6)
        XCTAssertTrue(groups.contains(.dns))
        XCTAssertTrue(groups.contains(.whitelist))
        XCTAssertTrue(groups.contains(.usuallyAvailable))
        XCTAssertTrue(groups.contains(.usuallyUnavailable))
        XCTAssertTrue(groups.contains(.vpn))
        XCTAssertTrue(groups.contains(.custom))
    }

    // MARK: - ProbeResult

    func testProbeResultDefaults() {
        let ep = ProbeEndpoint(domain: "test.com", group: .usuallyAvailable)
        let result = ProbeResult(endpoint: ep, status: .success)
        XCTAssertNil(result.latencyMs)
        XCTAssertEqual(result.bytesReceived, 0)
        XCTAssertFalse(result.cutOffDetected)
        XCTAssertNil(result.cutOffThresholdBytes)
    }

    func testProbeResultWithCutOff() {
        let ep = ProbeEndpoint(domain: "google.com", group: .usuallyAvailable)
        let result = ProbeResult(
            endpoint: ep,
            status: .cutOff,
            latencyMs: 120.5,
            bytesReceived: 14_336,
            cutOffDetected: true,
            cutOffThresholdBytes: 14_336
        )
        XCTAssertTrue(result.cutOffDetected)
        XCTAssertEqual(result.cutOffThresholdBytes, 14_336)
        XCTAssertEqual(result.status, .cutOff)
    }

    func testProbeResultCodable() throws {
        let ep = ProbeEndpoint(domain: "github.com", group: .usuallyAvailable)
        let original = ProbeResult(
            endpoint: ep,
            status: .success,
            latencyMs: 85.3,
            bytesReceived: 52_000
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProbeResult.self, from: data)
        XCTAssertEqual(decoded.endpoint.domain, original.endpoint.domain)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.bytesReceived, original.bytesReceived)
    }

    // MARK: - ProbeStatus

    func testProbeStatusRawValues() {
        XCTAssertEqual(ProbeStatus.success.rawValue, "success")
        XCTAssertEqual(ProbeStatus.timeout.rawValue, "timeout")
        XCTAssertEqual(ProbeStatus.connectionReset.rawValue, "connectionReset")
        XCTAssertEqual(ProbeStatus.connectionRefused.rawValue, "connectionRefused")
        XCTAssertEqual(ProbeStatus.tlsFailure.rawValue, "tlsFailure")
        XCTAssertEqual(ProbeStatus.networkLost.rawValue, "networkLost")
        XCTAssertEqual(ProbeStatus.cutOff.rawValue, "cutOff")
        XCTAssertEqual(ProbeStatus.dnsFailure.rawValue, "dnsFailure")
        XCTAssertEqual(ProbeStatus.error.rawValue, "error")
    }

    func testProbeStatusLabels() {
        UserDefaults.standard.set(AppLanguage.en.rawValue, forKey: AppLanguage.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey) }

        XCTAssertEqual(ProbeStatus.success.label, "OK")
        XCTAssertEqual(ProbeStatus.timeout.label, "No Response")
        XCTAssertEqual(ProbeStatus.connectionReset.label, "Connection Reset")
        XCTAssertEqual(ProbeStatus.connectionRefused.label, "Connection Refused")
        XCTAssertEqual(ProbeStatus.tlsFailure.label, "TLS Failed")
        XCTAssertEqual(ProbeStatus.networkLost.label, "Connection Lost")
        XCTAssertEqual(ProbeStatus.cutOff.label, "Cut Off")
        XCTAssertEqual(ProbeStatus.dnsFailure.label, "DNS Failure")
        XCTAssertEqual(ProbeStatus.error.label, "Error")
    }

    // MARK: - DiagnosticSnapshot

    func testDiagnosticSnapshotInit() {
        let snapshot = DiagnosticSnapshot(
            mode: .restricted,
            carrier: "MTS",
            networkType: "LTE",
            geohash: "ucfv0j"
        )
        XCTAssertEqual(snapshot.mode, "restricted")
        XCTAssertEqual(snapshot.accessMode, .restricted)
        XCTAssertEqual(snapshot.carrier, "MTS")
        XCTAssertEqual(snapshot.networkType, "LTE")
        XCTAssertEqual(snapshot.geohash, "ucfv0j")
    }

    func testDiagnosticSnapshotProbeResults() {
        let ep = ProbeEndpoint(domain: "ya.ru", group: .whitelist)
        let probeResult = ProbeResult(endpoint: ep, status: .success, latencyMs: 30)

        let snapshot = DiagnosticSnapshot(
            mode: .restricted,
            carrier: "Beeline",
            networkType: "5G",
            probeResults: [probeResult]
        )

        let decoded = snapshot.probeResults
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.endpoint.domain, "ya.ru")
        XCTAssertEqual(decoded.first?.status, .success)
    }

    func testDiagnosticSnapshotEmptyProbes() {
        let snapshot = DiagnosticSnapshot(
            mode: .fullShutdown,
            carrier: "Unknown",
            networkType: "None"
        )
        XCTAssertTrue(snapshot.probeResults.isEmpty)
    }

    func testDiagnosticSnapshotAccessModeUnknown() {
        let snapshot = DiagnosticSnapshot(
            mode: .unrestricted,
            carrier: "T2",
            networkType: "WiFi"
        )
        // Manually corrupt the mode
        snapshot.mode = "invalid_mode"
        XCTAssertEqual(snapshot.accessMode, .fullShutdown, "Unknown mode should default to fullShutdown")
    }

    // MARK: - Default Endpoints

    func testDefaultEndpointsCount() {
        let endpoints = ProbeEngine.defaultEndpoints
        XCTAssertGreaterThanOrEqual(endpoints.count, 25, "Should have at least 25 default endpoints")
    }

    func testDefaultEndpointsGroups() {
        let endpoints = ProbeEngine.defaultEndpoints
        let dns = endpoints.filter { $0.group == .dns }
        let whitelist = endpoints.filter { $0.group == .whitelist }
        let standard = endpoints.filter { $0.group == .usuallyAvailable }
        let unavailable = endpoints.filter { $0.group == .usuallyUnavailable }

        XCTAssertEqual(dns.count, 3)
        XCTAssertEqual(whitelist.count, 10)
        XCTAssertEqual(standard.count, 7)
        XCTAssertGreaterThanOrEqual(unavailable.count, 6, "Usually unavailable should have at least 6 endpoints")
    }

    func testDefaultEndpointsAllDefault() {
        for ep in ProbeEngine.defaultEndpoints {
            XCTAssertTrue(ep.isDefault, "\(ep.domain) should be marked as default")
        }
    }
}
