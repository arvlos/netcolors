import SwiftUI

struct SnapshotDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let snapshot: DiagnosticSnapshot

    var body: some View {
        List {
            Section {
                HStack {
                    Circle()
                        .fill(snapshot.accessMode.color)
                        .frame(width: 14, height: 14)
                    Text(snapshot.accessMode.title)
                        .font(.headline)
                }

                LabeledContent(L10n.tr("Time"), value: snapshot.timestamp.formatted(.dateTime.locale(AppLanguage.current.locale)))
                LabeledContent(L10n.tr("Carrier"), value: L10n.networkName(snapshot.carrier))
                LabeledContent(L10n.tr("Network"), value: L10n.networkName(snapshot.networkType))
                LabeledContent(L10n.tr("VPN"), value: (snapshot.vpnActive ?? false) ? L10n.tr("On") : L10n.tr("Off"))

                if let threshold = snapshot.cutOffThresholdBytes {
                    LabeledContent(L10n.tr("Cut-off Threshold"), value: L10n.tr("%lld KB", threshold / 1024))
                }
            }

            // Prefer new interpretations; fall back to legacy ProbeResult for old snapshots
            let interps = snapshot.interpretations
            if !interps.isEmpty {
                ForEach(ProbeGroup.allCases, id: \.self) { group in
                    let groupInterps = interps.filter { $0.observation.endpoint.group == group }
                    if !groupInterps.isEmpty {
                        Section(group.title) {
                            ForEach(groupInterps) { interp in
                                ProbeRow(interpretation: interp)
                            }
                        }
                    }
                }
            } else {
                let results = snapshot.probeResults
                ForEach(ProbeGroup.allCases, id: \.self) { group in
                    let groupResults = results.filter { $0.endpoint.group == group }
                    if !groupResults.isEmpty {
                        Section(group.title) {
                            ForEach(groupResults) { result in
                                ProbeRow(legacyResult: result)
                            }
                        }
                    }
                }
            }

            Section {
                Button(L10n.tr("Delete Check"), role: .destructive) {
                    modelContext.delete(snapshot)
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .navigationTitle(L10n.tr("Check"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
