import XCTest
@testable import NetColors

@MainActor
final class ModeDeterminationTests: XCTestCase {

    // MARK: - Helpers

    private func endpoint(_ domain: String, group: ProbeGroup) -> ProbeEndpoint {
        ProbeEndpoint(domain: domain, group: group)
    }

    private func result(
        _ domain: String,
        group: ProbeGroup,
        status: ProbeStatus,
        cutOffDetected: Bool = false
    ) -> ProbeResult {
        ProbeResult(
            endpoint: endpoint(domain, group: group),
            status: status,
            latencyMs: 50,
            bytesReceived: status == .success ? 50_000 : 0,
            cutOffDetected: cutOffDetected
        )
    }

    // MARK: - Full Shutdown

    func testFullShutdown_NothingWorks() {
        let results = [
            result("1.1.1.1", group: .dns, status: .timeout),
            result("8.8.8.8", group: .dns, status: .timeout),
            result("ya.ru", group: .whitelist, status: .timeout),
            result("google.com", group: .usuallyAvailable, status: .timeout),
            result("telegram.org", group: .usuallyUnavailable, status: .timeout),
        ]
        XCTAssertEqual(ProbeEngine.determineMode(from: results), .fullShutdown)
    }

    func testFullShutdown_DNSFailure() {
        let results = [
            result("1.1.1.1", group: .dns, status: .dnsFailure),
            result("ya.ru", group: .whitelist, status: .dnsFailure),
            result("google.com", group: .usuallyAvailable, status: .dnsFailure),
        ]
        XCTAssertEqual(ProbeEngine.determineMode(from: results), .fullShutdown)
    }

    // MARK: - Whitelist Mode

    func testWhitelist_RussianServicesWork_InternationalUnavailable() {
        let results = [
            result("1.1.1.1", group: .dns, status: .success),
            result("ya.ru", group: .whitelist, status: .success),
            result("vk.com", group: .whitelist, status: .success),
            result("google.com", group: .usuallyAvailable, status: .connectionReset),
            result("github.com", group: .usuallyAvailable, status: .timeout),
            result("telegram.org", group: .usuallyUnavailable, status: .timeout),
        ]
        XCTAssertEqual(ProbeEngine.determineMode(from: results), .whitelist)
    }

    func testWhitelist_MajorityStandardFails() {
        // Majority of standard endpoints fail → whitelist
        let results = [
            result("1.1.1.1", group: .dns, status: .success),
            result("ya.ru", group: .whitelist, status: .success),
            result("google.com", group: .usuallyAvailable, status: .connectionReset),
            result("github.com", group: .usuallyAvailable, status: .connectionReset),
            result("apple.com", group: .usuallyAvailable, status: .success),
            result("telegram.org", group: .usuallyUnavailable, status: .timeout),
        ]
        XCTAssertEqual(ProbeEngine.determineMode(from: results), .whitelist)
    }

    // MARK: - Restricted (normal RU internet)

    func testRestricted_AvailableWorksUnavailableFails() {
        let results = [
            result("1.1.1.1", group: .dns, status: .success),
            result("ya.ru", group: .whitelist, status: .success),
            result("google.com", group: .usuallyAvailable, status: .success),
            result("github.com", group: .usuallyAvailable, status: .success),
            result("telegram.org", group: .usuallyUnavailable, status: .timeout),
            result("instagram.com", group: .usuallyUnavailable, status: .connectionReset),
        ]
        XCTAssertEqual(ProbeEngine.determineMode(from: results), .restricted)
    }

    // MARK: - Unrestricted (VPN active)

    func testUnrestricted_EverythingWorks() {
        let results = [
            result("1.1.1.1", group: .dns, status: .success),
            result("ya.ru", group: .whitelist, status: .success),
            result("google.com", group: .usuallyAvailable, status: .success),
            result("telegram.org", group: .usuallyUnavailable, status: .success),
            result("instagram.com", group: .usuallyUnavailable, status: .success),
        ]
        XCTAssertEqual(ProbeEngine.determineMode(from: results), .unrestricted)
    }

    // MARK: - Edge Cases

    func testEmptyResults_FullShutdown() {
        XCTAssertEqual(ProbeEngine.determineMode(from: []), .fullShutdown)
    }

    func testOnlyDNSWorks_FullShutdown() {
        let results = [
            result("1.1.1.1", group: .dns, status: .success),
            result("ya.ru", group: .whitelist, status: .timeout),
            result("google.com", group: .usuallyAvailable, status: .timeout),
        ]
        XCTAssertEqual(ProbeEngine.determineMode(from: results), .fullShutdown)
    }

    func testPartialWhitelist_SomeWhitelistFails() {
        // Even if some whitelist endpoints fail, if at least one works + standard fails → whitelist mode
        let results = [
            result("1.1.1.1", group: .dns, status: .success),
            result("ya.ru", group: .whitelist, status: .success),
            result("gosuslugi.ru", group: .whitelist, status: .timeout),
            result("google.com", group: .usuallyAvailable, status: .connectionReset),
            result("telegram.org", group: .usuallyUnavailable, status: .timeout),
        ]
        XCTAssertEqual(ProbeEngine.determineMode(from: results), .whitelist)
    }

    func testMixed_MinorityUnavailableWorks_Restricted() {
        // Only 1 of 3 usually-unavailable works = not enough for unrestricted
        let results = [
            result("1.1.1.1", group: .dns, status: .success),
            result("ya.ru", group: .whitelist, status: .success),
            result("google.com", group: .usuallyAvailable, status: .success),
            result("telegram.org", group: .usuallyUnavailable, status: .success),
            result("instagram.com", group: .usuallyUnavailable, status: .timeout),
            result("facebook.com", group: .usuallyUnavailable, status: .timeout),
        ]
        XCTAssertEqual(ProbeEngine.determineMode(from: results), .restricted)
    }

    func testMixed_MajorityUnavailableWorks_Unrestricted() {
        // 2 of 3 usually-unavailable works = majority → unrestricted
        let results = [
            result("1.1.1.1", group: .dns, status: .success),
            result("ya.ru", group: .whitelist, status: .success),
            result("google.com", group: .usuallyAvailable, status: .success),
            result("telegram.org", group: .usuallyUnavailable, status: .success),
            result("instagram.com", group: .usuallyUnavailable, status: .success),
            result("facebook.com", group: .usuallyUnavailable, status: .timeout),
        ]
        XCTAssertEqual(ProbeEngine.determineMode(from: results), .unrestricted)
    }

    // MARK: - Notification Logic

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: "notificationsEnabled")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "notificationsEnabled")
        super.tearDown()
    }

    func testShouldNotify_DegradationToShutdown() {
        XCTAssertTrue(BackgroundMonitor.shouldNotify(previous: .restricted, current: .fullShutdown))
        XCTAssertTrue(BackgroundMonitor.shouldNotify(previous: .unrestricted, current: .fullShutdown))
    }

    func testShouldNotify_DegradationToWhitelist() {
        XCTAssertTrue(BackgroundMonitor.shouldNotify(previous: .restricted, current: .whitelist))
        XCTAssertTrue(BackgroundMonitor.shouldNotify(previous: .unrestricted, current: .whitelist))
    }

    func testShouldNotify_VPNToggle_NoNotification() {
        // Green ↔ yellow is VPN on/off, not degradation
        XCTAssertFalse(BackgroundMonitor.shouldNotify(previous: .unrestricted, current: .restricted))
        XCTAssertFalse(BackgroundMonitor.shouldNotify(previous: .restricted, current: .unrestricted))
    }

    func testShouldNotify_StayingDegraded_NoNotification() {
        // Already in degraded state — don't re-notify
        XCTAssertFalse(BackgroundMonitor.shouldNotify(previous: .whitelist, current: .whitelist))
        XCTAssertFalse(BackgroundMonitor.shouldNotify(previous: .fullShutdown, current: .fullShutdown))
        XCTAssertFalse(BackgroundMonitor.shouldNotify(previous: .whitelist, current: .fullShutdown))
    }

    func testShouldNotify_Recovery_NoNotification() {
        // Coming back from degraded — no notification needed
        XCTAssertFalse(BackgroundMonitor.shouldNotify(previous: .fullShutdown, current: .restricted))
        XCTAssertFalse(BackgroundMonitor.shouldNotify(previous: .whitelist, current: .unrestricted))
    }

    func testShouldNotify_FirstRun_NilPrevious() {
        // First run, no previous state — notify if degraded
        XCTAssertTrue(BackgroundMonitor.shouldNotify(previous: nil, current: .fullShutdown))
        XCTAssertTrue(BackgroundMonitor.shouldNotify(previous: nil, current: .whitelist))
        XCTAssertFalse(BackgroundMonitor.shouldNotify(previous: nil, current: .restricted))
        XCTAssertFalse(BackgroundMonitor.shouldNotify(previous: nil, current: .unrestricted))
    }

    func testShouldNotify_Disabled_NoNotification() {
        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        XCTAssertFalse(BackgroundMonitor.shouldNotify(previous: .unrestricted, current: .fullShutdown))
        XCTAssertFalse(BackgroundMonitor.shouldNotify(previous: .restricted, current: .whitelist))
        // Restore for other tests
        UserDefaults.standard.set(true, forKey: "notificationsEnabled")
    }
}
