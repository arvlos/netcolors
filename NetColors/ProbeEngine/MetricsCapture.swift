import Foundation

// MARK: - Protocol for testability

/// Abstraction over URLSessionTaskTransactionMetrics for unit testing.
protocol TransactionMetricsProtocol {
    var domainLookupStartDate: Date? { get }
    var domainLookupEndDate: Date? { get }
    var connectStartDate: Date? { get }
    var connectEndDate: Date? { get }
    var secureConnectionStartDate: Date? { get }
    var secureConnectionEndDate: Date? { get }
    var requestStartDate: Date? { get }
    var requestEndDate: Date? { get }
    var responseStartDate: Date? { get }
    var responseEndDate: Date? { get }
}

extension URLSessionTaskTransactionMetrics: TransactionMetricsProtocol {}

// MARK: - Phase extraction

enum MetricsCapture {
    static func determineFailureStage(from metrics: some TransactionMetricsProtocol) -> FailureStage {
        if metrics.domainLookupEndDate == nil { return .dns }
        if metrics.connectEndDate == nil { return .tcpConnect }
        if metrics.secureConnectionEndDate == nil { return .tlsHandshake }
        if metrics.responseStartDate == nil { return .httpResponse }
        if metrics.responseEndDate == nil { return .transfer }
        return .unknown
    }

    static func extractPhaseTimings(from metrics: some TransactionMetricsProtocol, totalMs: Double?) -> PhaseTimings {
        PhaseTimings(
            dnsMs: interval(metrics.domainLookupStartDate, metrics.domainLookupEndDate),
            connectMs: interval(metrics.connectStartDate, metrics.connectEndDate),
            tlsMs: interval(metrics.secureConnectionStartDate, metrics.secureConnectionEndDate),
            requestMs: interval(metrics.requestStartDate, metrics.requestEndDate),
            responseMs: interval(metrics.responseStartDate, metrics.responseEndDate),
            totalMs: totalMs
        )
    }

    private static func interval(_ start: Date?, _ end: Date?) -> Double? {
        guard let s = start, let e = end else { return nil }
        return e.timeIntervalSince(s) * 1000
    }
}

// MARK: - Per-probe delegate

/// Lightweight delegate capturing URLSessionTaskMetrics for a single probe.
final class ProbeMetricsDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    nonisolated(unsafe) private var _metrics: URLSessionTaskMetrics?

    var capturedMetrics: URLSessionTaskMetrics? { _metrics }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        _metrics = metrics
    }
}
