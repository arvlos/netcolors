import SwiftUI

struct TrafficLightView: View {
    @EnvironmentObject private var engine: ProbeEngine

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 60)

                    // Status icon
                    Image(systemName: engine.currentMode.iconName)
                        .font(.system(size: 80, weight: .light))
                        .foregroundColor(.white)
                        .contentTransition(.symbolEffect(.replace))

                    // Status text
                    Text(engine.currentMode.title)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)

                    Text(engine.currentMode.statusDescription)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // Cut-off threshold (if detected)
                    if let threshold = engine.detectedCutOffThreshold {
                        Text(L10n.tr("Cut off after %lld KB", threshold / 1024))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 60)

                    // Carrier & network info
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Text(connectionLine)

                            Text(engine.carrierInfo.vpnActive ? L10n.tr("VPN On") : L10n.tr("VPN Off"))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.white.opacity(engine.carrierInfo.vpnActive ? 0.25 : 0.12))
                                .clipShape(Capsule())
                        }
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))

                        if let lastCheck = engine.lastCheckTime {
                            Text(L10n.tr("Last check: %@", lastCheck.formatted(.relative(presentation: .named).locale(AppLanguage.current.locale))))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    // Refresh button
                    Button {
                        Task {
                            await engine.runDiagnostics()
                        }
                    } label: {
                        if engine.isRunning {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 56, height: 56)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                        }
                    }
                    .background(.white.opacity(0.2))
                    .clipShape(Circle())
                    .disabled(engine.isRunning)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)
                // Content must exceed viewport height for scroll bounce to work
                .frame(minHeight: geo.size.height + 1)
            }
            .scrollBounceBehavior(.always)
        }
        .background(engine.currentMode.color.ignoresSafeArea())
        .opacity(engine.isRunning ? 0.85 : 1.0)
        .animation(.easeInOut(duration: 0.5), value: engine.currentMode)
        .animation(.easeInOut(duration: 0.3), value: engine.isRunning)
        .refreshable {
            // Fire-and-forget: dismiss top spinner immediately,
            // the refresh button below shows its own ProgressView via engine.isRunning
            Task { @MainActor in
                await engine.runDiagnostics()
            }
        }
        .task {
            if engine.lastCheckTime == nil {
                await engine.runDiagnostics()
            }
        }
    }

    /// Carrier and network type; shown once when both are the same token (e.g. Wi-Fi).
    private var connectionLine: String {
        let carrier = L10n.networkName(engine.carrierInfo.carrierName)
        let network = L10n.networkName(engine.carrierInfo.networkType)
        return carrier == network ? carrier : "\(carrier) · \(network)"
    }
}
