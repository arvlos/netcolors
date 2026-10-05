import SwiftUI
import SwiftData

enum DateFilter: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7d"
    case month = "30d"
    case all = "All"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: L10n.tr("Today")
        case .week: L10n.tr("7d")
        case .month: L10n.tr("30d")
        case .all: L10n.tr("All")
        }
    }

    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .today: return cal.startOfDay(for: Date())
        case .week: return cal.date(byAdding: .day, value: -7, to: Date())
        case .month: return cal.date(byAdding: .day, value: -30, to: Date())
        case .all: return nil
        }
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DiagnosticSnapshot.timestamp, order: .reverse)
    private var allSnapshots: [DiagnosticSnapshot]

    @State private var dateFilter: DateFilter = .all

    private var filteredSnapshots: [DiagnosticSnapshot] {
        guard let start = dateFilter.startDate else { return allSnapshots }
        return allSnapshots.filter { $0.timestamp >= start }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredSnapshots.isEmpty {
                    ContentUnavailableView(
                        L10n.tr("No History Yet"),
                        systemImage: "clock",
                        description: Text(L10n.tr("Results will appear here after your first check."))
                    )
                } else {
                    List {
                        ForEach(filteredSnapshots) { snapshot in
                            NavigationLink(value: snapshot) {
                                SnapshotRow(snapshot: snapshot)
                            }
                        }
                        .onDelete { offsets in
                            deleteSnapshots(at: offsets)
                        }
                    }
                }
            }
            .navigationTitle(L10n.tr("History"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker(L10n.tr("Filter"), selection: $dateFilter) {
                        ForEach(DateFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
            }
            .navigationDestination(for: DiagnosticSnapshot.self) { snapshot in
                SnapshotDetailView(snapshot: snapshot)
            }
        }
    }

    private func deleteSnapshots(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredSnapshots[index])
        }
        try? modelContext.save()
    }
}

struct SnapshotRow: View {
    let snapshot: DiagnosticSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(snapshot.accessMode.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.accessMode.title)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 6) {
                    Text(L10n.networkName(snapshot.carrier))
                    Text(verbatim: "·")
                    Text(L10n.networkName(snapshot.networkType))

                    if snapshot.vpnActive ?? false {
                        Text(verbatim: "VPN")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Text(snapshot.timestamp, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
