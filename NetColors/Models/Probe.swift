import Foundation
import SwiftUI
import SwiftData

// MARK: - Internet Access Mode

enum AccessMode: String, Codable, CaseIterable {
    case fullShutdown = "shutdown"
    case whitelist = "whitelist"
    case restricted = "restricted"  // Most sites work, the usually-unavailable group doesn't
    case unrestricted = "unrestricted"

    var color: Color {
        switch self {
        case .fullShutdown: .black
        case .whitelist: .red
        case .restricted: .orange
        case .unrestricted: .green
        }
    }

    var title: String {
        switch self {
        case .fullShutdown: L10n.tr("No Internet")
        case .whitelist: L10n.tr("Only Selected Services")
        case .restricted: L10n.tr("Some Sites Unavailable")
        case .unrestricted: L10n.tr("Full Access")
        }
    }

    var statusDescription: String {
        switch self {
        case .fullShutdown:
            L10n.tr("No site responds, including Russian ones.")
        case .whitelist:
            L10n.tr("Only some Russian services respond. Most other sites are unavailable.")
        case .restricted:
            L10n.tr("Most sites work. Some international services are unavailable.")
        case .unrestricted:
            L10n.tr("All checked sites respond.")
        }
    }

    var iconName: String {
        switch self {
        case .fullShutdown: "xmark.circle"
        case .whitelist: "exclamationmark.triangle"
        case .restricted: "lock.fill"
        case .unrestricted: "checkmark.circle"
        }
    }
}

/// Codable mirror of DiagnosticSnapshot for JSON export.
struct ExportableSnapshot: Codable {
    let timestamp: Date
    let mode: String
    let carrier: String
    let networkType: String
    let vpnActive: Bool
    let geohash: String?
    let cutOffThresholdBytes: Int?
    let probeResults: [ProbeResult]
    let interpretations: [ProbeInterpretation]?

    init(from snapshot: DiagnosticSnapshot) {
        self.timestamp = snapshot.timestamp
        self.mode = snapshot.mode
        self.carrier = snapshot.carrier
        self.networkType = snapshot.networkType
        self.vpnActive = snapshot.vpnActive ?? false
        self.geohash = snapshot.geohash
        self.cutOffThresholdBytes = snapshot.cutOffThresholdBytes
        self.probeResults = snapshot.probeResults
        let interps = snapshot.interpretations
        self.interpretations = interps.isEmpty ? nil : interps
    }
}

// MARK: - Probe Definition

struct ProbeEndpoint: Identifiable, Codable, Hashable {
    let id: UUID
    let domain: String
    let group: ProbeGroup
    let isDefault: Bool  // Default probes cannot be removed

    init(domain: String, group: ProbeGroup, isDefault: Bool = true) {
        self.id = UUID()
        self.domain = domain
        self.group = group
        self.isDefault = isDefault
    }
}

/// Groups are defined by how sites usually behave under restrictions, not by topic.
/// Raw values are persisted in history and must not change.
enum ProbeGroup: String, Codable, CaseIterable {
    case dns = "DNS"
    case whitelist = "Whitelist"
    case usuallyAvailable = "UsuallyAvailable"
    case usuallyUnavailable = "UsuallyUnavailable"
    case vpn = "VPN"
    case custom = "Custom"

    var title: String {
        switch self {
        case .dns: L10n.tr("DNS Servers")
        case .whitelist: L10n.tr("Whitelist")
        case .usuallyAvailable: L10n.tr("Usually Available")
        case .usuallyUnavailable: L10n.tr("Usually Unavailable")
        case .vpn: L10n.tr("VPN")
        case .custom: L10n.tr("Custom")
        }
    }
}

// MARK: - Observation Layer (what happened — facts only)

enum ProbeOutcome: String, Codable {
    case success
    case failure
}

enum FailureStage: String, Codable, CaseIterable {
    case dns            // failed during name resolution
    case tcpConnect     // failed during TCP handshake
    case tlsHandshake   // failed during TLS negotiation
    case httpResponse   // connected but HTTP error / no response
    case transfer       // partial data, then the connection was cut
    case unknown        // could not determine stage
}

struct PhaseTimings: Codable, Equatable {
    let dnsMs: Double?
    let connectMs: Double?
    let tlsMs: Double?
    let requestMs: Double?
    let responseMs: Double?
    let totalMs: Double?
}

struct ProbeObservation: Identifiable, Codable {
    let id: UUID
    let endpoint: ProbeEndpoint
    let timestamp: Date
    let outcome: ProbeOutcome
    let failureStage: FailureStage?
    let urlErrorCode: Int?
    let httpStatusCode: Int?
    let latencyMs: Double?
    let phaseTimings: PhaseTimings?
    let bytesReceived: Int

    init(
        endpoint: ProbeEndpoint,
        timestamp: Date = Date(),
        outcome: ProbeOutcome,
        failureStage: FailureStage? = nil,
        urlErrorCode: Int? = nil,
        httpStatusCode: Int? = nil,
        latencyMs: Double? = nil,
        phaseTimings: PhaseTimings? = nil,
        bytesReceived: Int = 0
    ) {
        self.id = UUID()
        self.endpoint = endpoint
        self.timestamp = timestamp
        self.outcome = outcome
        self.failureStage = failureStage
        self.urlErrorCode = urlErrorCode
        self.httpStatusCode = httpStatusCode
        self.latencyMs = latencyMs
        self.phaseTimings = phaseTimings
        self.bytesReceived = bytesReceived
    }
}

// MARK: - Interpretation Layer (why — with confidence)

enum FailurePattern: String, Codable, CaseIterable {
    case dnsFailure         // Name not resolved while control domains resolve
    case connectionRefused  // TCP connection refused or reset before TLS while controls connect
    case tlsInterrupted     // TCP connected, TLS handshake failed while controls complete it
    case cutOffMidTransfer  // Partial data received, then the connection was cut
    case stubPage           // HTTP 200/30x, but the response is a provider stub page
    case slowdown           // Succeeds, but latency >> controls from the same run
    case networkIssue       // All groups fail — a general connectivity problem
    case inconclusive       // Cannot determine with confidence

    var label: String {
        switch self {
        case .dnsFailure: L10n.tr("DNS Failure")
        case .connectionRefused: L10n.tr("Connection Refused")
        case .tlsInterrupted: L10n.tr("TLS Interrupted")
        case .cutOffMidTransfer: L10n.tr("Cut Off Mid-Transfer")
        case .stubPage: L10n.tr("Stub Page")
        case .slowdown: L10n.tr("Slowed Down")
        case .networkIssue: L10n.tr("Network Problem")
        case .inconclusive: L10n.tr("Unclear")
        }
    }

    var explanation: String {
        switch self {
        case .dnsFailure:
            L10n.tr("The site's address could not be resolved, while control sites resolved normally.")
        case .connectionRefused:
            L10n.tr("The connection was refused or could not be established, while control sites connected normally.")
        case .tlsInterrupted:
            L10n.tr("The connection was set up, but the secure handshake failed, while control sites completed it normally.")
        case .cutOffMidTransfer:
            L10n.tr("Data started arriving, then the connection was abruptly cut.")
        case .stubPage:
            L10n.tr("The connection succeeded, but a stub page from the network provider came back instead of the site.")
        case .slowdown:
            L10n.tr("The connection succeeded but was more than 5× slower than control sites in the same check. Normal mobile variation (2–4×) is not flagged.")
        case .networkIssue:
            L10n.tr("Requests failed in every group, including control sites. This looks like a general connection problem.")
        case .inconclusive:
            L10n.tr("The failure pattern does not clearly match any known type.")
        }
    }
}

enum Confidence: String, Codable, Comparable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: L10n.tr("Low")
        case .medium: L10n.tr("Med")
        case .high: L10n.tr("High")
        }
    }

    static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        let order: [Confidence] = [.low, .medium, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

struct ProbeInterpretation: Identifiable, Codable {
    let id: UUID
    let observation: ProbeObservation
    let pattern: FailurePattern?
    let confidence: Confidence?
    let reasoning: String

    init(
        observation: ProbeObservation,
        pattern: FailurePattern? = nil,
        confidence: Confidence? = nil,
        reasoning: String = ""
    ) {
        self.id = UUID()
        self.observation = observation
        self.pattern = pattern
        self.confidence = confidence
        self.reasoning = reasoning
    }

    /// Bridge to legacy ProbeResult for backward compatibility.
    var asLegacyResult: ProbeResult {
        let status: ProbeStatus
        if observation.outcome == .success {
            status = .success
        } else {
            status = switch pattern {
            case .dnsFailure: .dnsFailure
            case .connectionRefused: .connectionRefused
            case .tlsInterrupted: .connectionReset
            case .cutOffMidTransfer: .networkLost
            case .stubPage: .connectionRefused
            case .networkIssue: .error
            case .inconclusive, .slowdown, .none: .error
            }
        }

        return ProbeResult(
            endpoint: observation.endpoint,
            timestamp: observation.timestamp,
            status: status,
            latencyMs: observation.latencyMs,
            bytesReceived: observation.bytesReceived
        )
    }
}

// MARK: - Probe Result (legacy)

struct ProbeResult: Identifiable, Codable {
    let id: UUID
    let endpoint: ProbeEndpoint
    let timestamp: Date
    let status: ProbeStatus
    let latencyMs: Double?
    let bytesReceived: Int
    let cutOffDetected: Bool
    let cutOffThresholdBytes: Int?

    init(
        endpoint: ProbeEndpoint,
        timestamp: Date = Date(),
        status: ProbeStatus,
        latencyMs: Double? = nil,
        bytesReceived: Int = 0,
        cutOffDetected: Bool = false,
        cutOffThresholdBytes: Int? = nil
    ) {
        self.id = UUID()
        self.endpoint = endpoint
        self.timestamp = timestamp
        self.status = status
        self.latencyMs = latencyMs
        self.bytesReceived = bytesReceived
        self.cutOffDetected = cutOffDetected
        self.cutOffThresholdBytes = cutOffThresholdBytes
    }
}

enum ProbeStatus: String, Codable {
    case success
    case timeout            // No response within deadline — packets dropped
    case connectionReset    // TCP RST during or after the TLS handshake
    case connectionRefused  // Immediate rejection or redirect to a stub page
    case tlsFailure         // TLS/SSL negotiation failed — certificate or protocol issue
    case networkLost        // Connection established then dropped — unstable link or VPN tunnel failure
    case cutOff             // Partial response received, then the connection was cut
    case dnsFailure         // DNS resolver returned no result for this domain or no connectivity
    case error              // Other URLSession error

    var label: String {
        switch self {
        case .success: L10n.tr("OK")
        case .timeout: L10n.tr("No Response")
        case .connectionReset: L10n.tr("Connection Reset")
        case .connectionRefused: L10n.tr("Connection Refused")
        case .tlsFailure: L10n.tr("TLS Failed")
        case .networkLost: L10n.tr("Connection Lost")
        case .cutOff: L10n.tr("Cut Off")
        case .dnsFailure: L10n.tr("DNS Failure")
        case .error: L10n.tr("Error")
        }
    }
}

// MARK: - Diagnostic Snapshot

@Model
final class DiagnosticSnapshot {
    var timestamp: Date
    var mode: String  // AccessMode rawValue
    var carrier: String
    var networkType: String  // LTE, 5G, WiFi
    var vpnActive: Bool?
    var geohash: String?  // Coarsened location
    var cutOffThresholdBytes: Int?
    var probeResultsData: Data?  // JSON-encoded [ProbeResult]
    var interpretationsData: Data?  // JSON-encoded [ProbeInterpretation]

    init(
        timestamp: Date = Date(),
        mode: AccessMode,
        carrier: String,
        networkType: String,
        vpnActive: Bool? = false,
        geohash: String? = nil,
        cutOffThresholdBytes: Int? = nil,
        probeResults: [ProbeResult] = [],
        interpretations: [ProbeInterpretation] = []
    ) {
        self.timestamp = timestamp
        self.mode = mode.rawValue
        self.carrier = carrier
        self.networkType = networkType
        self.vpnActive = vpnActive
        self.geohash = geohash
        self.cutOffThresholdBytes = cutOffThresholdBytes
        self.probeResultsData = try? JSONEncoder().encode(probeResults)
        self.interpretationsData = interpretations.isEmpty ? nil : try? JSONEncoder().encode(interpretations)
    }

    var accessMode: AccessMode {
        AccessMode(rawValue: mode) ?? .fullShutdown
    }

    var probeResults: [ProbeResult] {
        guard let data = probeResultsData else { return [] }
        return (try? JSONDecoder().decode([ProbeResult].self, from: data)) ?? []
    }

    var interpretations: [ProbeInterpretation] {
        guard let data = interpretationsData else { return [] }
        return (try? JSONDecoder().decode([ProbeInterpretation].self, from: data)) ?? []
    }
}
