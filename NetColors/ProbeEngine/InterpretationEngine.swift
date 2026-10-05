import Foundation

/// Interprets probe observations by comparing failures against
/// successful controls from the same diagnostic run.
/// Uses relative timing (not absolute thresholds) for robustness
/// across different networks, carriers, and VPN configurations.
enum InterpretationEngine {

    // MARK: - Public API

    static func interpret(_ observations: [ProbeObservation]) -> [ProbeInterpretation] {
        let baseline = buildBaseline(from: observations)
        return observations.map { interpret(observation: $0, baseline: baseline) }
    }

    // MARK: - Single observation interpretation

    private static func interpret(
        observation: ProbeObservation,
        baseline: ControlBaseline
    ) -> ProbeInterpretation {
        // Successful probes — check for slowdown
        if observation.outcome == .success {
            if let slowdown = checkSlowdown(observation: observation, baseline: baseline) {
                return slowdown
            }
            return ProbeInterpretation(
                observation: observation,
                reasoning: "Site responded successfully."
            )
        }

        // If no controls succeeded at all, it's a general network issue
        if !baseline.hasAnySuccess {
            return ProbeInterpretation(
                observation: observation,
                pattern: .networkIssue,
                confidence: .high,
                reasoning: "All probe groups failed. Likely a general connectivity problem."
            )
        }

        // Classify by failure stage (from URLSessionTaskMetrics)
        if let stage = observation.failureStage {
            switch stage {
            case .dns:
                return interpretDnsFailure(observation: observation, baseline: baseline)
            case .tcpConnect:
                return interpretTcpFailure(observation: observation, baseline: baseline)
            case .tlsHandshake:
                return interpretTlsFailure(observation: observation, baseline: baseline)
            case .transfer:
                return interpretTransferFailure(observation: observation, baseline: baseline)
            case .httpResponse:
                return interpretHttpFailure(observation: observation, baseline: baseline)
            case .unknown:
                break // fall through to URLError fallback
            }
        }

        // Fallback: classify by URLError code when metrics unavailable
        if let errorCode = observation.urlErrorCode {
            return interpretByErrorCode(observation: observation, errorCode: errorCode, baseline: baseline)
        }

        return ProbeInterpretation(
            observation: observation,
            pattern: .inconclusive,
            confidence: .low,
            reasoning: "Cannot determine failure cause. No metrics or error code available."
        )
    }

    // MARK: - Stage-based interpretation

    private static func interpretDnsFailure(
        observation: ProbeObservation,
        baseline: ControlBaseline
    ) -> ProbeInterpretation {
        let controlsDnsOk = baseline.successCountByGroup[.dns, default: 0] > 0
            || baseline.successCountByGroup[.whitelist, default: 0] > 0

        if controlsDnsOk {
            return ProbeInterpretation(
                observation: observation,
                pattern: .dnsFailure,
                confidence: .high,
                reasoning: "DNS resolution failed for this domain while control domains resolved successfully."
            )
        }
        return ProbeInterpretation(
            observation: observation,
            pattern: .networkIssue,
            confidence: .medium,
            reasoning: "DNS resolution failed. Control DNS probes also failed — likely a connectivity issue."
        )
    }

    private static func interpretTcpFailure(
        observation: ProbeObservation,
        baseline: ControlBaseline
    ) -> ProbeInterpretation {
        let controlsTcpOk = baseline.hasAnySuccess
        let confidence: Confidence = controlsTcpOk ? .high : .medium

        return ProbeInterpretation(
            observation: observation,
            pattern: .connectionRefused,
            confidence: confidence,
            reasoning: controlsTcpOk
                ? "TCP connection failed while controls connected successfully. The destination is unreachable from this network."
                : "TCP connection failed. Controls also had issues — likely a general connectivity problem."
        )
    }

    private static func interpretTlsFailure(
        observation: ProbeObservation,
        baseline: ControlBaseline
    ) -> ProbeInterpretation {
        let controlsTlsOk = baseline.hasAnySuccess

        if controlsTlsOk {
            return ProbeInterpretation(
                observation: observation,
                pattern: .tlsInterrupted,
                confidence: .high,
                reasoning: "TCP connected but TLS handshake failed while controls completed TLS normally."
            )
        }
        return ProbeInterpretation(
            observation: observation,
            pattern: .inconclusive,
            confidence: .low,
            reasoning: "TLS handshake failed but controls also had issues. Cause unclear."
        )
    }

    private static func interpretTransferFailure(
        observation: ProbeObservation,
        baseline: ControlBaseline
    ) -> ProbeInterpretation {
        let hasPartialData = observation.bytesReceived > 0
        let confidence: Confidence = hasPartialData && baseline.hasAnySuccess ? .high : .medium

        return ProbeInterpretation(
            observation: observation,
            pattern: .cutOffMidTransfer,
            confidence: confidence,
            reasoning: hasPartialData
                ? "Received \(observation.bytesReceived) bytes before the connection was cut."
                : "Connection established then lost during transfer."
        )
    }

    private static func interpretHttpFailure(
        observation: ProbeObservation,
        baseline: ControlBaseline
    ) -> ProbeInterpretation {
        ProbeInterpretation(
            observation: observation,
            pattern: .inconclusive,
            confidence: .low,
            reasoning: "Connection and TLS succeeded but no HTTP response received."
        )
    }

    // MARK: - Slowdown detection (for successful probes)

    private static func checkSlowdown(
        observation: ProbeObservation,
        baseline: ControlBaseline
    ) -> ProbeInterpretation? {
        guard let totalMs = observation.latencyMs ?? observation.phaseTimings?.totalMs,
              let medianMs = baseline.medianTotalMs,
              medianMs > 0 else { return nil }

        let ratio = totalMs / medianMs
        let absoluteDiff = totalMs - medianMs

        // Require both: >5x slower AND >1500ms absolute difference.
        // Mobile cellular variance is typically 2-4x; real slowdown is 10x+.
        guard ratio > 5.0 && absoluteDiff > 1500 else { return nil }

        let confidence: Confidence = ratio > 10.0 ? .high : .medium

        return ProbeInterpretation(
            observation: observation,
            pattern: .slowdown,
            confidence: confidence,
            reasoning: String(format: "Response took %.0fms (%.1fx slower than control median of %.0fms).", totalMs, ratio, medianMs)
        )
    }

    // MARK: - URLError code fallback (when metrics unavailable)

    private static func interpretByErrorCode(
        observation: ProbeObservation,
        errorCode: Int,
        baseline: ControlBaseline
    ) -> ProbeInterpretation {
        let controlsOk = baseline.hasAnySuccess

        // Map URLError codes to best-guess pattern
        switch errorCode {
        case -1003, -1006: // cannotFindHost, dnsLookupFailed
            return ProbeInterpretation(
                observation: observation,
                pattern: controlsOk ? .dnsFailure : .networkIssue,
                confidence: controlsOk ? .medium : .medium,
                reasoning: "DNS lookup failed. Stage unknown (no metrics). \(controlsOk ? "Controls succeeded — the failure is specific to this domain." : "Controls also failed.")"
            )

        case -1004: // cannotConnectToHost
            return ProbeInterpretation(
                observation: observation,
                pattern: controlsOk ? .connectionRefused : .networkIssue,
                confidence: controlsOk ? .medium : .medium,
                reasoning: "Connection refused. Stage unknown (no metrics). \(controlsOk ? "Controls connected — the failure is specific to this destination." : "Controls also failed.")"
            )

        case -1200: // secureConnectionFailed
            return ProbeInterpretation(
                observation: observation,
                pattern: controlsOk ? .tlsInterrupted : .inconclusive,
                confidence: controlsOk ? .medium : .low,
                reasoning: "Secure connection failed. Stage unknown (no metrics). \(controlsOk ? "Controls completed TLS — the failure is specific to this domain." : "Cannot determine cause.")"
            )

        case -1001: // timedOut
            return ProbeInterpretation(
                observation: observation,
                pattern: controlsOk ? .inconclusive : .networkIssue,
                confidence: .medium,
                reasoning: "Request timed out. \(controlsOk ? "Controls succeeded — packets may be silently dropped." : "Controls also timed out — connectivity issue.")"
            )

        case -1005: // networkConnectionLost
            return ProbeInterpretation(
                observation: observation,
                pattern: observation.bytesReceived > 0 ? .cutOffMidTransfer : .inconclusive,
                confidence: observation.bytesReceived > 0 ? .medium : .low,
                reasoning: observation.bytesReceived > 0
                    ? "Connection lost after receiving \(observation.bytesReceived) bytes."
                    : "Connection lost. No data received."
            )

        default:
            return ProbeInterpretation(
                observation: observation,
                pattern: .inconclusive,
                confidence: .low,
                reasoning: "URLError code \(errorCode). Cannot classify without metrics."
            )
        }
    }

    // MARK: - Control Baseline

    struct ControlBaseline {
        let medianTotalMs: Double?
        let hasAnySuccess: Bool
        let successCountByGroup: [ProbeGroup: Int]
    }

    static func buildBaseline(from observations: [ProbeObservation]) -> ControlBaseline {
        let successful = observations.filter { $0.outcome == .success }

        let totalTimes = successful.compactMap { $0.latencyMs ?? $0.phaseTimings?.totalMs }
        let medianTotal = median(totalTimes)

        var successByGroup: [ProbeGroup: Int] = [:]
        for obs in successful {
            successByGroup[obs.endpoint.group, default: 0] += 1
        }

        return ControlBaseline(
            medianTotalMs: medianTotal,
            hasAnySuccess: !successful.isEmpty,
            successCountByGroup: successByGroup
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
