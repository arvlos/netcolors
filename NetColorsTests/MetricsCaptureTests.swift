import XCTest
@testable import NetColors

final class MetricsCaptureTests: XCTestCase {

    // MARK: - Mock

    struct MockMetrics: TransactionMetricsProtocol {
        var domainLookupStartDate: Date?
        var domainLookupEndDate: Date?
        var connectStartDate: Date?
        var connectEndDate: Date?
        var secureConnectionStartDate: Date?
        var secureConnectionEndDate: Date?
        var requestStartDate: Date?
        var requestEndDate: Date?
        var responseStartDate: Date?
        var responseEndDate: Date?
    }

    private let t0 = Date(timeIntervalSince1970: 1000)

    private func date(_ offset: Double) -> Date {
        t0.addingTimeInterval(offset)
    }

    // MARK: - Failure Stage

    func testFailureStage_DnsPhase() {
        let m = MockMetrics(
            domainLookupStartDate: date(0),
            domainLookupEndDate: nil  // DNS didn't complete
        )
        XCTAssertEqual(MetricsCapture.determineFailureStage(from: m), .dns)
    }

    func testFailureStage_TcpPhase() {
        let m = MockMetrics(
            domainLookupStartDate: date(0),
            domainLookupEndDate: date(0.05),
            connectStartDate: date(0.05),
            connectEndDate: nil  // TCP didn't complete
        )
        XCTAssertEqual(MetricsCapture.determineFailureStage(from: m), .tcpConnect)
    }

    func testFailureStage_TlsPhase() {
        let m = MockMetrics(
            domainLookupStartDate: date(0),
            domainLookupEndDate: date(0.05),
            connectStartDate: date(0.05),
            connectEndDate: date(0.1),
            secureConnectionStartDate: date(0.1),
            secureConnectionEndDate: nil  // TLS didn't complete
        )
        XCTAssertEqual(MetricsCapture.determineFailureStage(from: m), .tlsHandshake)
    }

    func testFailureStage_HttpResponsePhase() {
        let m = MockMetrics(
            domainLookupStartDate: date(0),
            domainLookupEndDate: date(0.05),
            connectStartDate: date(0.05),
            connectEndDate: date(0.1),
            secureConnectionStartDate: date(0.1),
            secureConnectionEndDate: date(0.2),
            requestStartDate: date(0.2),
            requestEndDate: date(0.21),
            responseStartDate: nil  // no response received
        )
        XCTAssertEqual(MetricsCapture.determineFailureStage(from: m), .httpResponse)
    }

    func testFailureStage_TransferPhase() {
        let m = MockMetrics(
            domainLookupStartDate: date(0),
            domainLookupEndDate: date(0.05),
            connectStartDate: date(0.05),
            connectEndDate: date(0.1),
            secureConnectionStartDate: date(0.1),
            secureConnectionEndDate: date(0.2),
            requestStartDate: date(0.2),
            requestEndDate: date(0.21),
            responseStartDate: date(0.22),
            responseEndDate: nil  // transfer interrupted
        )
        XCTAssertEqual(MetricsCapture.determineFailureStage(from: m), .transfer)
    }

    func testFailureStage_AllCompleted_Unknown() {
        let m = MockMetrics(
            domainLookupStartDate: date(0),
            domainLookupEndDate: date(0.05),
            connectStartDate: date(0.05),
            connectEndDate: date(0.1),
            secureConnectionStartDate: date(0.1),
            secureConnectionEndDate: date(0.2),
            requestStartDate: date(0.2),
            requestEndDate: date(0.21),
            responseStartDate: date(0.22),
            responseEndDate: date(0.5)
        )
        XCTAssertEqual(MetricsCapture.determineFailureStage(from: m), .unknown)
    }

    // MARK: - Phase Timings Extraction

    func testExtractPhaseTimings() {
        let m = MockMetrics(
            domainLookupStartDate: date(0),
            domainLookupEndDate: date(0.05),     // 50ms DNS
            connectStartDate: date(0.05),
            connectEndDate: date(0.12),           // 70ms connect
            secureConnectionStartDate: date(0.12),
            secureConnectionEndDate: date(0.22),  // 100ms TLS
            requestStartDate: date(0.22),
            requestEndDate: date(0.23),           // 10ms request
            responseStartDate: date(0.23),
            responseEndDate: date(0.5)            // 270ms response
        )

        let timings = MetricsCapture.extractPhaseTimings(from: m, totalMs: 500)

        XCTAssertEqual(timings.dnsMs!, 50, accuracy: 0.1)
        XCTAssertEqual(timings.connectMs!, 70, accuracy: 0.1)
        XCTAssertEqual(timings.tlsMs!, 100, accuracy: 0.1)
        XCTAssertEqual(timings.requestMs!, 10, accuracy: 0.1)
        XCTAssertEqual(timings.responseMs!, 270, accuracy: 0.1)
        XCTAssertEqual(timings.totalMs!, 500, accuracy: 0.1)
    }

    func testExtractPhaseTimings_PartialData() {
        // Only DNS completed
        let m = MockMetrics(
            domainLookupStartDate: date(0),
            domainLookupEndDate: date(0.03)
        )

        let timings = MetricsCapture.extractPhaseTimings(from: m, totalMs: 100)

        XCTAssertEqual(timings.dnsMs!, 30, accuracy: 0.1)
        XCTAssertNil(timings.connectMs)
        XCTAssertNil(timings.tlsMs)
        XCTAssertEqual(timings.totalMs, 100)
    }
}
