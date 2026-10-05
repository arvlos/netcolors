import XCTest
@testable import NetColors

@MainActor
final class InterpretationEngineTests: XCTestCase {

    // MARK: - Helpers

    private func obs(
        _ domain: String,
        group: ProbeGroup,
        outcome: ProbeOutcome,
        failureStage: FailureStage? = nil,
        urlErrorCode: Int? = nil,
        latencyMs: Double? = 100,
        bytesReceived: Int = 0
    ) -> ProbeObservation {
        ProbeObservation(
            endpoint: ProbeEndpoint(domain: domain, group: group),
            outcome: outcome,
            failureStage: failureStage,
            urlErrorCode: urlErrorCode,
            latencyMs: latencyMs,
            bytesReceived: bytesReceived
        )
    }

    private func successObs(_ domain: String, group: ProbeGroup, latencyMs: Double = 200) -> ProbeObservation {
        obs(domain, group: group, outcome: .success, latencyMs: latencyMs, bytesReceived: 50_000)
    }

    /// Typical set of successful controls for a restricted-mode scenario.
    private var standardControls: [ProbeObservation] {
        [
            successObs("1.1.1.1", group: .dns),
            successObs("ya.ru", group: .whitelist),
            successObs("google.com", group: .usuallyAvailable),
            successObs("github.com", group: .usuallyAvailable),
        ]
    }

    // MARK: - Success

    func testSuccess_NoPattern() {
        let observations = [successObs("google.com", group: .usuallyAvailable)]
        let results = InterpretationEngine.interpret(observations)
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].pattern)
        XCTAssertNil(results[0].confidence)
    }

    // MARK: - DNS Failure

    func testDnsFailure_WhenDnsFailsButControlsResolve() {
        var observations = standardControls
        observations.append(obs("telegram.org", group: .usuallyUnavailable, outcome: .failure, failureStage: .dns))

        let results = InterpretationEngine.interpret(observations)
        let failed = results.first { $0.observation.endpoint.domain == "telegram.org" }!

        XCTAssertEqual(failed.pattern, .dnsFailure)
        XCTAssertEqual(failed.confidence, .high)
    }

    func testDnsFailure_WhenAllDnsFails_NetworkIssue() {
        let observations = [
            obs("1.1.1.1", group: .dns, outcome: .failure, failureStage: .dns),
            obs("ya.ru", group: .whitelist, outcome: .failure, failureStage: .dns),
            obs("google.com", group: .usuallyAvailable, outcome: .failure, failureStage: .dns),
        ]
        let results = InterpretationEngine.interpret(observations)
        // All fail → networkIssue, not dnsFailure
        for r in results {
            XCTAssertEqual(r.pattern, .networkIssue)
        }
    }

    // MARK: - Connection Refused

    func testConnectionRefused_WhenConnectFailsButControlsConnect() {
        var observations = standardControls
        observations.append(obs("facebook.com", group: .usuallyUnavailable, outcome: .failure, failureStage: .tcpConnect))

        let results = InterpretationEngine.interpret(observations)
        let fb = results.first { $0.observation.endpoint.domain == "facebook.com" }!

        XCTAssertEqual(fb.pattern, .connectionRefused)
        XCTAssertEqual(fb.confidence, .high)
    }

    // MARK: - TLS Interrupted

    func testTlsInterrupted_WhenTlsFailsButControlsComplete() {
        var observations = standardControls
        observations.append(obs("linkedin.com", group: .usuallyUnavailable, outcome: .failure, failureStage: .tlsHandshake))

        let results = InterpretationEngine.interpret(observations)
        let li = results.first { $0.observation.endpoint.domain == "linkedin.com" }!

        XCTAssertEqual(li.pattern, .tlsInterrupted)
        XCTAssertEqual(li.confidence, .high)
    }

    func testTlsFailure_WhenControlsAlsoFail_Inconclusive() {
        let observations = [
            obs("ya.ru", group: .whitelist, outcome: .failure, failureStage: .tlsHandshake),
            obs("linkedin.com", group: .usuallyUnavailable, outcome: .failure, failureStage: .tlsHandshake),
        ]
        let results = InterpretationEngine.interpret(observations)
        let li = results.first { $0.observation.endpoint.domain == "linkedin.com" }!

        // No controls succeeded, so the cause can't be confirmed
        XCTAssertNotEqual(li.pattern, .tlsInterrupted)
    }

    // MARK: - Midstream Termination

    func testCutOffMidTransfer_PartialDataThenCut() {
        var observations = standardControls
        observations.append(obs("instagram.com", group: .usuallyUnavailable, outcome: .failure,
                                failureStage: .transfer, bytesReceived: 4096))

        let results = InterpretationEngine.interpret(observations)
        let ig = results.first { $0.observation.endpoint.domain == "instagram.com" }!

        XCTAssertEqual(ig.pattern, .cutOffMidTransfer)
        XCTAssertEqual(ig.confidence, .high)
    }

    // MARK: - Slowdown

    func testSlowdown_SlowRelativeToControls() {
        var observations = standardControls  // ~200ms each
        // 4000ms when controls are ~200ms = 20x, absoluteDiff = 3800ms
        observations.append(obs("discord.com", group: .usuallyUnavailable, outcome: .success,
                                latencyMs: 4000, bytesReceived: 50_000))

        let results = InterpretationEngine.interpret(observations)
        let dc = results.first { $0.observation.endpoint.domain == "discord.com" }!

        XCTAssertEqual(dc.pattern, .slowdown)
    }

    func testSlowdown_NotFlaggedWhenAllProbesSlow() {
        // All probes are slow — this is just a slow network, not slowdown
        let observations = [
            successObs("1.1.1.1", group: .dns, latencyMs: 1500),
            successObs("ya.ru", group: .whitelist, latencyMs: 1800),
            successObs("google.com", group: .usuallyAvailable, latencyMs: 1600),
            successObs("discord.com", group: .usuallyUnavailable, latencyMs: 2000),
        ]
        let results = InterpretationEngine.interpret(observations)
        let dc = results.first { $0.observation.endpoint.domain == "discord.com" }!

        XCTAssertNil(dc.pattern)
    }

    func testSlowdown_NotFlaggedForNormalCellularVariance() {
        // 3x slower with 1000ms diff — normal mobile variance, not slowdown
        var observations = standardControls  // ~200ms each
        observations.append(obs("vk.com", group: .whitelist, outcome: .success,
                                latencyMs: 1500, bytesReceived: 50_000))

        let results = InterpretationEngine.interpret(observations)
        let vk = results.first { $0.observation.endpoint.domain == "vk.com" }!

        XCTAssertNil(vk.pattern)
    }

    func testSlowdown_RequiresAbsoluteDifference() {
        // 6x slower but absolute diff < 1500ms — should NOT flag
        let observations = [
            successObs("1.1.1.1", group: .dns, latencyMs: 50),
            successObs("ya.ru", group: .whitelist, latencyMs: 60),
            successObs("google.com", group: .usuallyAvailable, latencyMs: 55),
            successObs("discord.com", group: .usuallyUnavailable, latencyMs: 400),  // 7x but only +345ms
        ]
        let results = InterpretationEngine.interpret(observations)
        let dc = results.first { $0.observation.endpoint.domain == "discord.com" }!

        XCTAssertNil(dc.pattern)
    }

    // MARK: - Network Issue

    func testNetworkIssue_WhenAllGroupsFail() {
        let observations = [
            obs("1.1.1.1", group: .dns, outcome: .failure, failureStage: .tcpConnect),
            obs("ya.ru", group: .whitelist, outcome: .failure, failureStage: .tcpConnect),
            obs("google.com", group: .usuallyAvailable, outcome: .failure, failureStage: .tcpConnect),
            obs("telegram.org", group: .usuallyUnavailable, outcome: .failure, failureStage: .tcpConnect),
        ]
        let results = InterpretationEngine.interpret(observations)
        for r in results {
            XCTAssertEqual(r.pattern, .networkIssue)
            XCTAssertEqual(r.confidence, .high)
        }
    }

    // MARK: - URLError Fallback

    func testFallback_DnsErrorCode_WithControls() {
        var observations = standardControls
        // failureStage is nil (no metrics), but urlErrorCode present
        observations.append(obs("telegram.org", group: .usuallyUnavailable, outcome: .failure,
                                failureStage: nil, urlErrorCode: -1003))  // cannotFindHost

        let results = InterpretationEngine.interpret(observations)
        let tg = results.first { $0.observation.endpoint.domain == "telegram.org" }!

        XCTAssertEqual(tg.pattern, .dnsFailure)
        XCTAssertEqual(tg.confidence, .medium)  // lower confidence without metrics
    }

    func testFallback_TimeoutErrorCode() {
        var observations = standardControls
        observations.append(obs("telegram.org", group: .usuallyUnavailable, outcome: .failure,
                                failureStage: nil, urlErrorCode: -1001))  // timedOut

        let results = InterpretationEngine.interpret(observations)
        let tg = results.first { $0.observation.endpoint.domain == "telegram.org" }!

        // Timeout is ambiguous — could be any stage
        XCTAssertEqual(tg.pattern, .inconclusive)
    }

    func testFallback_SecureConnectionFailed_WithControls() {
        var observations = standardControls
        observations.append(obs("linkedin.com", group: .usuallyUnavailable, outcome: .failure,
                                failureStage: nil, urlErrorCode: -1200))  // secureConnectionFailed

        let results = InterpretationEngine.interpret(observations)
        let li = results.first { $0.observation.endpoint.domain == "linkedin.com" }!

        XCTAssertEqual(li.pattern, .tlsInterrupted)
        XCTAssertEqual(li.confidence, .medium)  // lower without metrics
    }

    // MARK: - Edge Cases

    func testEmptyObservations() {
        let results = InterpretationEngine.interpret([])
        XCTAssertTrue(results.isEmpty)
    }

    func testSingleFailedObservation_NoControls() {
        let observations = [obs("telegram.org", group: .usuallyUnavailable, outcome: .failure, failureStage: .tlsHandshake)]
        let results = InterpretationEngine.interpret(observations)

        // No controls → networkIssue (cause can't be confirmed)
        XCTAssertEqual(results[0].pattern, .networkIssue)
    }

    // MARK: - Control Baseline

    func testControlBaseline_MedianComputation() {
        let observations = [
            successObs("a.com", group: .usuallyAvailable, latencyMs: 100),
            successObs("b.com", group: .usuallyAvailable, latencyMs: 200),
            successObs("c.com", group: .usuallyAvailable, latencyMs: 300),
        ]
        let baseline = InterpretationEngine.buildBaseline(from: observations)

        XCTAssertEqual(baseline.medianTotalMs, 200)
        XCTAssertTrue(baseline.hasAnySuccess)
        XCTAssertEqual(baseline.successCountByGroup[.usuallyAvailable], 3)
    }

    func testControlBaseline_Empty() {
        let baseline = InterpretationEngine.buildBaseline(from: [])
        XCTAssertNil(baseline.medianTotalMs)
        XCTAssertFalse(baseline.hasAnySuccess)
    }

    // MARK: - Legacy Bridge

    func testAsLegacyResult_SuccessMapping() {
        let interp = ProbeInterpretation(
            observation: successObs("google.com", group: .usuallyAvailable),
            reasoning: "OK"
        )
        XCTAssertEqual(interp.asLegacyResult.status, .success)
    }

    func testAsLegacyResult_PatternMapping() {
        let testCases: [(FailurePattern, ProbeStatus)] = [
            (.dnsFailure, .dnsFailure),
            (.connectionRefused, .connectionRefused),
            (.tlsInterrupted, .connectionReset),
            (.cutOffMidTransfer, .networkLost),
            (.networkIssue, .error),
            (.inconclusive, .error),
        ]

        for (pattern, expectedStatus) in testCases {
            let interp = ProbeInterpretation(
                observation: obs("test.com", group: .usuallyUnavailable, outcome: .failure, failureStage: .unknown),
                pattern: pattern,
                confidence: .high
            )
            XCTAssertEqual(interp.asLegacyResult.status, expectedStatus,
                           "\(pattern) should map to \(expectedStatus)")
        }
    }
}
