import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var engine: ProbeEngine

    var body: some View {
        NavigationStack {
            List {
                if engine.interpretations.isEmpty && engine.isRunning {
                    HStack {
                        Spacer()
                        ProgressView(L10n.tr("Running checks…"))
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(ProbeGroup.allCases, id: \.self) { group in
                    let groupInterps = engine.interpretations.filter {
                        $0.observation.endpoint.group == group
                    }
                    if !groupInterps.isEmpty {
                        Section(group.title) {
                            ForEach(groupInterps) { interp in
                                ProbeRow(interpretation: interp)
                            }
                        }
                    }
                }

                if engine.interpretations.isEmpty && !engine.isRunning {
                    ContentUnavailableView(
                        L10n.tr("No Results"),
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text(L10n.tr("Pull down or tap ▶ to run a check"))
                    )
                }
            }
            .navigationTitle(L10n.tr("Diagnostics"))
            .refreshable {
                await Task { @MainActor in
                    await engine.runDiagnostics()
                }.value
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await engine.runDiagnostics() }
                    } label: {
                        if engine.isRunning {
                            ProgressView()
                        } else {
                            Image(systemName: "play.fill")
                        }
                    }
                    .disabled(engine.isRunning)
                }
            }
        }
    }
}

struct ProbeRow: View {
    let interpretation: ProbeInterpretation

    /// Fallback initializer for legacy ProbeResult (old history snapshots).
    init(legacyResult: ProbeResult) {
        let obs = ProbeObservation(
            endpoint: legacyResult.endpoint,
            timestamp: legacyResult.timestamp,
            outcome: legacyResult.status == .success ? .success : .failure,
            latencyMs: legacyResult.latencyMs,
            bytesReceived: legacyResult.bytesReceived
        )
        self.interpretation = ProbeInterpretation(
            observation: obs,
            reasoning: legacyResult.status.label
        )
    }

    init(interpretation: ProbeInterpretation) {
        self.interpretation = interpretation
    }

    private var obs: ProbeObservation { interpretation.observation }

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(obs.endpoint.domain)
                    .font(.body)

                HStack(spacing: 8) {
                    if let latency = obs.latencyMs {
                        Text(L10n.tr("%lld ms", Int(latency)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if obs.bytesReceived > 0 {
                        Text(formatBytes(obs.bytesReceived))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let confidence = interpretation.confidence {
                        Text(confidence.label)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(confidenceColor(confidence))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(confidenceColor(confidence).opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(patternLabel)
                    .font(.caption)
                    .foregroundColor(statusColor)

                if let stage = obs.failureStage, obs.outcome == .failure {
                    Text(stageLabel(stage))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var patternLabel: String {
        if obs.outcome == .success {
            return interpretation.pattern?.label ?? L10n.tr("OK")
        }
        return interpretation.pattern?.label ?? L10n.tr("Failed")
    }

    private var statusColor: Color {
        if obs.outcome == .success {
            return interpretation.pattern == .slowdown ? .orange : .green
        }
        guard let pattern = interpretation.pattern else { return .gray }
        return switch pattern {
        case .dnsFailure, .connectionRefused, .tlsInterrupted, .cutOffMidTransfer: .red
        case .stubPage: .red
        case .slowdown: .orange
        case .networkIssue: .gray
        case .inconclusive: .gray
        }
    }

    private func confidenceColor(_ confidence: Confidence) -> Color {
        switch confidence {
        case .high: .primary
        case .medium: .orange
        case .low: .secondary
        }
    }

    private func stageLabel(_ stage: FailureStage) -> String {
        switch stage {
        case .dns: "@ DNS"
        case .tcpConnect: "@ TCP"
        case .tlsHandshake: "@ TLS"
        case .httpResponse: "@ HTTP"
        case .transfer: L10n.tr("@ Transfer")
        case .unknown: ""
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            return L10n.tr("%.1f MB", Double(bytes) / 1_048_576)
        } else if bytes >= 1024 {
            return L10n.tr("%.1f KB", Double(bytes) / 1024)
        }
        return L10n.tr("%lld B", bytes)
    }
}
