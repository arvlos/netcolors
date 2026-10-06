#if DEBUG
import Foundation
import SwiftData

/// Demo state for App Store screenshots, driven by launch arguments (Debug builds only):
///   -ScreenshotMode whitelist|restricted|unrestricted   the mode shown on the status screen
///   -ScreenshotTab status|diagnostics|history|settings|howitworks
/// Nothing touches the network, and history lives in memory, not in the real store.
enum ScreenshotDemo {
    static var mode: AccessMode? {
        UserDefaults.standard.string(forKey: "ScreenshotMode").flatMap(AccessMode.init(rawValue:))
    }

    static var tab: String { UserDefaults.standard.string(forKey: "ScreenshotTab") ?? "status" }

    static var isActive: Bool { mode != nil }

    @MainActor
    static func makeEngine(mode: AccessMode) -> ProbeEngine {
        let engine = ProbeEngine()
        engine.currentMode = mode
        engine.lastCheckTime = Date().addingTimeInterval(-120)
        engine.carrierInfo = CarrierInfo(carrierName: "Cellular", networkType: "LTE",
                                         vpnActive: mode == .unrestricted, vpnName: nil)
        engine.detectedCutOffThreshold = mode == .whitelist ? 16 * 1024 : nil
        engine.interpretations = interpretations(for: mode)
        engine.results = engine.interpretations.map(\.asLegacyResult)
        return engine
    }

    /// A plausible check for each mode: which groups respond and how the others fail.
    @MainActor
    static func interpretations(for mode: AccessMode) -> [ProbeInterpretation] {
        var failures: [(FailurePattern, FailureStage, Confidence, Int)] = [
            (.tlsInterrupted, .tlsHandshake, .high, 0),
            (.cutOffMidTransfer, .transfer, .medium, 16_384),
            (.connectionRefused, .tcpConnect, .high, 0),
            (.dnsFailure, .dns, .low, 0),
        ]
        func failed(_ endpoint: ProbeEndpoint) -> ProbeInterpretation {
            let (pattern, stage, confidence, bytes) = failures.removeFirst()
            failures.append((pattern, stage, confidence, bytes))
            let observation = ProbeObservation(endpoint: endpoint, outcome: .failure,
                                               failureStage: stage, bytesReceived: bytes)
            return ProbeInterpretation(observation: observation, pattern: pattern, confidence: confidence)
        }
        func succeeded(_ endpoint: ProbeEndpoint, _ index: Int) -> ProbeInterpretation {
            let latency = Double(40 + (index * 37) % 160)
            let observation = ProbeObservation(endpoint: endpoint, outcome: .success,
                                               latencyMs: latency, bytesReceived: 20_000 + index * 3_100)
            return ProbeInterpretation(observation: observation)
        }
        return ProbeEngine.defaultEndpoints.enumerated().map { index, endpoint in
            let responds: Bool = switch (mode, endpoint.group) {
            case (.unrestricted, _): true
            case (.restricted, .usuallyUnavailable): false
            case (.restricted, _): true
            case (.whitelist, .dns), (.whitelist, .whitelist): true
            case (.whitelist, _): false
            case (.fullShutdown, _): false
            }
            return responds ? succeeded(endpoint, index) : failed(endpoint)
        }
    }

    /// A day of checks on a phone that moves between mobile data and a VPN.
    @MainActor
    static func fillHistory(in container: ModelContainer) {
        let context = ModelContext(container)
        let day: [(Int, AccessMode, String, Bool)] = [
            (8 * 60 + 5, .restricted, "LTE", false),
            (9 * 60 + 40, .whitelist, "LTE", false),
            (10 * 60 + 15, .whitelist, "LTE", false),
            (11 * 60 + 30, .unrestricted, "LTE", true),
            (13 * 60 + 10, .restricted, "WiFi", false),
            (15 * 60 + 45, .whitelist, "LTE", false),
            (17 * 60 + 20, .fullShutdown, "LTE", false),
            (18 * 60 + 55, .restricted, "LTE", false),
        ]
        let start = Calendar.current.startOfDay(for: Date())
        for (minutes, mode, network, vpn) in day {
            let snapshot = DiagnosticSnapshot(
                timestamp: start.addingTimeInterval(TimeInterval(minutes * 60)),
                mode: mode, carrier: network == "WiFi" ? "WiFi" : "Cellular", networkType: network,
                vpnActive: vpn, cutOffThresholdBytes: mode == .whitelist ? 16 * 1024 : nil,
                interpretations: interpretations(for: mode)
            )
            context.insert(snapshot)
        }
        try? context.save()
    }
}
#endif
