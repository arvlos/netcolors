import Foundation
import Network
import SwiftData

/// Core probe engine — runs HTTP(S) probes against endpoint groups
/// and determines the current internet access mode.
@MainActor
final class ProbeEngine: ObservableObject {
    @Published var currentMode: AccessMode = .fullShutdown
    @Published var lastCheckTime: Date?
    @Published var isRunning = false
    @Published var results: [ProbeResult] = []
    @Published var interpretations: [ProbeInterpretation] = []
    @Published var detectedCutOffThreshold: Int?
    @Published var carrierInfo: CarrierInfo = CarrierInfo(carrierName: "—", networkType: "—", vpnActive: false, vpnName: nil)

    var modelContainer: ModelContainer?
    private var refreshTask: Task<Void, Never>?
    private let session: URLSession

    // MARK: - Default Probe Endpoints

    static let defaultEndpoints: [ProbeEndpoint] = [
        // DNS
        ProbeEndpoint(domain: "1.1.1.1", group: .dns),
        ProbeEndpoint(domain: "8.8.8.8", group: .dns),
        ProbeEndpoint(domain: "9.9.9.9", group: .dns),

        // Whitelist (Russian services likely on whitelist)
        ProbeEndpoint(domain: "gosuslugi.ru", group: .whitelist),
        ProbeEndpoint(domain: "ya.ru", group: .whitelist),
        ProbeEndpoint(domain: "vk.com", group: .whitelist),
        ProbeEndpoint(domain: "sberbank.ru", group: .whitelist),
        ProbeEndpoint(domain: "mos.ru", group: .whitelist),
        ProbeEndpoint(domain: "nalog.ru", group: .whitelist),
        ProbeEndpoint(domain: "mail.ru", group: .whitelist),
        ProbeEndpoint(domain: "taxi.yandex.ru", group: .whitelist),
        ProbeEndpoint(domain: "ozon.ru", group: .whitelist),
        ProbeEndpoint(domain: "wildberries.ru", group: .whitelist),

        // Usually available (international sites that normally open)
        ProbeEndpoint(domain: "google.com", group: .usuallyAvailable),
        ProbeEndpoint(domain: "github.com", group: .usuallyAvailable),
        ProbeEndpoint(domain: "stackoverflow.com", group: .usuallyAvailable),
        ProbeEndpoint(domain: "wikipedia.org", group: .usuallyAvailable),
        ProbeEndpoint(domain: "apple.com", group: .usuallyAvailable),
        ProbeEndpoint(domain: "microsoft.com", group: .usuallyAvailable),
        ProbeEndpoint(domain: "reddit.com", group: .usuallyAvailable),

        // Usually unavailable (international sites that normally don't open without VPN)
        ProbeEndpoint(domain: "telegram.org", group: .usuallyUnavailable),
        ProbeEndpoint(domain: "instagram.com", group: .usuallyUnavailable),
        ProbeEndpoint(domain: "facebook.com", group: .usuallyUnavailable),
        ProbeEndpoint(domain: "x.com", group: .usuallyUnavailable),
        ProbeEndpoint(domain: "linkedin.com", group: .usuallyUnavailable),
        ProbeEndpoint(domain: "discord.com", group: .usuallyUnavailable),
    ]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Run All Probes

    func runDiagnostics(endpoints: [ProbeEndpoint]? = nil) async {
        guard !isRunning else { return }
        isRunning = true

        await waitForStableNetwork()

        let probeList = endpoints ?? Self.defaultEndpoints
        let urlSession = self.session

        // Layer 1: Collect observations (facts)
        let observations = await withTaskGroup(of: ProbeObservation.self) { group in
            for endpoint in probeList {
                group.addTask {
                    await Self.observe(endpoint: endpoint, session: urlSession)
                }
            }
            var collected: [ProbeObservation] = []
            for await obs in group {
                collected.append(obs)
            }
            return collected
        }

        // Layer 2: Interpret observations (relative comparison)
        let interps = InterpretationEngine.interpret(observations)
        self.interpretations = interps

        // Bridge to legacy results for mode determination + existing UI
        self.results = interps.map { $0.asLegacyResult }
        self.currentMode = Self.determineMode(from: results)
        self.carrierInfo = await CarrierInfo.current()
        self.lastCheckTime = Date()

        if currentMode == .whitelist {
            detectedCutOffThreshold = await Self.detectCutOffThreshold(session: urlSession)
        }

        saveSnapshot()
        UserDefaults.standard.set(currentMode.rawValue, forKey: "lastKnownMode")
        isRunning = false
    }

    // MARK: - Snapshot Persistence

    private func saveSnapshot() {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let snapshot = DiagnosticSnapshot(
            mode: currentMode,
            carrier: carrierInfo.carrierName,
            networkType: carrierInfo.networkType,
            vpnActive: carrierInfo.vpnActive,
            cutOffThresholdBytes: detectedCutOffThreshold,
            probeResults: results,
            interpretations: interpretations
        )
        context.insert(snapshot)
        try? context.save()

        DataRetentionManager.cleanup(in: container)
    }

    // MARK: - Auto-Refresh

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = UserDefaults.standard.integer(forKey: "autoRefreshInterval")
                guard interval > 0 else {
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.runDiagnostics()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Network Readiness

    /// Brief pause to let the network path stabilize after VPN connect/disconnect.
    private func waitForStableNetwork() async {
        try? await Task.sleep(for: .milliseconds(300))
    }

    // MARK: - Single Probe (Layer 1: Observation)

    private static func observe(endpoint: ProbeEndpoint, session: URLSession) async -> ProbeObservation {
        let urlString = "https://\(endpoint.domain)"

        guard let url = URL(string: urlString) else {
            return ProbeObservation(endpoint: endpoint, outcome: .failure, failureStage: .unknown)
        }

        let metricsDelegate = ProbeMetricsDelegate()
        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (data, response) = try await session.data(from: url, delegate: metricsDelegate)
            let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000

            let httpStatus = (response as? HTTPURLResponse)?.statusCode
            let timings = extractTimings(from: metricsDelegate, totalMs: latency)

            return ProbeObservation(
                endpoint: endpoint,
                outcome: .success,
                httpStatusCode: httpStatus,
                latencyMs: latency,
                phaseTimings: timings,
                bytesReceived: data.count
            )
        } catch let error as URLError {
            let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000

            // Determine failure stage from metrics (precise) or fallback to URLError code
            let stage = stageFromMetrics(metricsDelegate) ?? stageFromErrorCode(error.code)
            let timings = extractTimings(from: metricsDelegate, totalMs: latency)

            return ProbeObservation(
                endpoint: endpoint,
                outcome: .failure,
                failureStage: stage,
                urlErrorCode: error.code.rawValue,
                latencyMs: latency,
                phaseTimings: timings
            )
        } catch {
            let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
            return ProbeObservation(
                endpoint: endpoint,
                outcome: .failure,
                failureStage: .unknown,
                latencyMs: latency
            )
        }
    }

    private static func extractTimings(from delegate: ProbeMetricsDelegate, totalMs: Double) -> PhaseTimings? {
        guard let metrics = delegate.capturedMetrics,
              let tx = metrics.transactionMetrics.last else { return nil }
        return MetricsCapture.extractPhaseTimings(from: tx, totalMs: totalMs)
    }

    private static func stageFromMetrics(_ delegate: ProbeMetricsDelegate) -> FailureStage? {
        guard let metrics = delegate.capturedMetrics,
              let tx = metrics.transactionMetrics.last else { return nil }
        let stage = MetricsCapture.determineFailureStage(from: tx)
        return stage == .unknown ? nil : stage  // nil = fallback to error code
    }

    /// Fallback stage inference when URLSessionTaskMetrics not available.
    private static func stageFromErrorCode(_ code: URLError.Code) -> FailureStage {
        switch code {
        case .cannotFindHost, .dnsLookupFailed: .dns
        case .cannotConnectToHost: .tcpConnect
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected: .tlsHandshake
        case .networkConnectionLost: .transfer
        case .timedOut: .unknown  // timeout can happen at any stage
        default: .unknown
        }
    }

    // MARK: - Adaptive Cut-off Threshold Detection

    private static func detectCutOffThreshold(session: URLSession) async -> Int? {
        guard let url = URL(string: "https://google.com") else { return nil }

        var thresholds: [Int] = []

        for _ in 0..<3 {
            do {
                let (data, _) = try await session.data(from: url)
                if data.count > 0 && data.count < 100_000 {
                    thresholds.append(data.count)
                }
            } catch {
                // Connection failed entirely — not a partial cut-off
            }
        }

        guard !thresholds.isEmpty else { return nil }
        let sorted = thresholds.sorted()
        return sorted[sorted.count / 2]  // median
    }

    // MARK: - Mode Determination

    static func determineMode(from results: [ProbeResult]) -> AccessMode {
        let dnsResults = results.filter { $0.endpoint.group == .dns }
        let whitelistResults = results.filter { $0.endpoint.group == .whitelist }
        let availableResults = results.filter { $0.endpoint.group == .usuallyAvailable }
        let unavailableResults = results.filter { $0.endpoint.group == .usuallyUnavailable }

        let dnsOk = dnsResults.contains { $0.status == .success }
        let whitelistOk = whitelistResults.contains { $0.status == .success }

        let availableSuccessCount = availableResults.filter { $0.status == .success }.count
        let availableMajorityOk = !availableResults.isEmpty
            && availableSuccessCount > availableResults.count / 2

        let unavailableSuccessCount = unavailableResults.filter { $0.status == .success }.count
        let unavailableMajorityOk = !unavailableResults.isEmpty
            && unavailableSuccessCount > unavailableResults.count / 2

        // Full shutdown: nothing works
        if !dnsOk && !whitelistOk {
            return .fullShutdown
        }

        // Whitelist mode: Russian services work, majority of international dead
        if whitelistOk && !availableMajorityOk {
            return .whitelist
        }

        // Unrestricted: most usually-unavailable sites respond (VPN on or no restrictions)
        if unavailableMajorityOk {
            return .unrestricted
        }

        // Restricted: usually-available sites work, usually-unavailable ones don't
        if availableMajorityOk {
            return .restricted
        }

        return .fullShutdown
    }
}
