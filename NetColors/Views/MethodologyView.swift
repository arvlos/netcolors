import SwiftUI

struct MethodologyView: View {
    var body: some View {
        List {
            Section(L10n.tr("Network Modes")) {
                modeRow(.unrestricted)
                modeRow(.restricted)
                modeRow(.whitelist)
                modeRow(.fullShutdown)
            }

            Section(L10n.tr("How the Mode Is Determined")) {
                Text(L10n.tr("The app sends HTTPS requests to %lld sites in four groups: DNS servers, whitelist services, and international sites that are usually available or usually unavailable on Russian networks. Which groups respond determines the current mode.", ProbeEngine.defaultEndpoints.count))
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 8) {
                    rule(L10n.tr("Nothing responds → No Internet"))
                    rule(L10n.tr("Whitelist services work, most usually available sites don't → Only Selected Services"))
                    rule(L10n.tr("Most usually available sites work, usually unavailable ones don't → Some Sites Unavailable"))
                    rule(L10n.tr("Most usually unavailable sites respond too → Full Access"))
                }
                .font(.subheadline)
            }

            Section(L10n.tr("Two Layers of Analysis")) {
                Text(L10n.tr("Each check goes through two layers:"))
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 8) {
                    rule(L10n.tr("Layer 1 — observation: what happened — success or failure, the stage where it failed, the timing of each phase."))
                    rule(L10n.tr("Layer 2 — interpretation: compares failed requests with successful control requests from the same check to find where the connection failed, and flags requests that are much slower than the controls."))
                }
                .font(.subheadline)

                Text(L10n.tr("Facts are kept separate from conclusions. Results are compared with control requests from the same check rather than with fixed thresholds, so the method works across networks, carriers and VPNs."))
                .font(.subheadline)
            }

            Section(L10n.tr("Where the Connection Failed")) {
                ForEach(FailurePattern.allCases, id: \.self) { pattern in
                    patternRow(pattern)
                }
            }

            Section(L10n.tr("Connection Stages")) {
                Text(L10n.tr("When a request fails, the system's network metrics show which phase failed. This is more reliable than guessing from error codes."))
                .font(.subheadline)

                ForEach(FailureStage.allCases, id: \.self) { stage in
                    stageRow(stage)
                }
            }

            Section(L10n.tr("Confidence")) {
                VStack(alignment: .leading, spacing: 8) {
                    rule(L10n.tr("High — control requests succeeded and the failure pattern is clear"))
                    rule(L10n.tr("Medium — likely, but some metrics are missing or control requests partly failed"))
                    rule(L10n.tr("Low — the cause can't be determined reliably"))
                }
                .font(.subheadline)

                Text(L10n.tr("If no control request succeeds, failures are attributed to a general network problem rather than to individual sites."))
                .font(.subheadline)
            }

            Section(L10n.tr("Cut-off Threshold")) {
                Text(L10n.tr("In the Only Selected Services mode the app runs an extra test: three requests to an international site, counting how many bytes arrive before the connection is cut. The median is shown as “Cut off after N KB”."))
                .font(.subheadline)
            }

            Section(L10n.tr("Background Checks")) {
                Text(L10n.tr("The app checks the connection in the background roughly every 10–60 minutes; iOS decides exactly when. A notification is sent only when access drops to Only Selected Services or No Internet. Turning a VPN on or off doesn't trigger notifications."))
                .font(.subheadline)
            }
        }
        .navigationTitle(L10n.tr("How It Works"))
    }

    // MARK: - Helpers

    private func modeRow(_ mode: AccessMode) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(mode.color)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(mode.statusDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func patternRow(_ pattern: FailurePattern) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pattern.label)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(pattern.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func stageRow(_ stage: FailureStage) -> some View {
        HStack(spacing: 8) {
            Text(stageIcon(stage))
                .font(.caption)
                .frame(width: 84, alignment: .leading)
            Text(stageDescription(stage))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func stageIcon(_ stage: FailureStage) -> String {
        switch stage {
        case .dns: "DNS"
        case .tcpConnect: "TCP"
        case .tlsHandshake: "TLS"
        case .httpResponse: "HTTP"
        case .transfer: L10n.tr("Transfer")
        case .unknown: L10n.tr("Unknown")
        }
    }

    private func stageDescription(_ stage: FailureStage) -> String {
        switch stage {
        case .dns: L10n.tr("The site's address could not be resolved")
        case .tcpConnect: L10n.tr("The connection could not be established")
        case .tlsHandshake: L10n.tr("The secure connection could not be set up")
        case .httpResponse: L10n.tr("Connected, but no response")
        case .transfer: L10n.tr("Data started arriving, then the connection was cut")
        case .unknown: L10n.tr("Could not determine where it failed")
        }
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(verbatim: "•")
            Text(text)
        }
    }
}
