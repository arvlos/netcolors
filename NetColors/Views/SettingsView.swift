import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval = 60
    @AppStorage("dataRetentionDays") private var dataRetentionDays = 14
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue

    @Query private var allSnapshots: [DiagnosticSnapshot]

    @State private var showEraseConfirmation = false
    @State private var showEraseSuccess = false
    @State private var exportFileURL: URL?
    @State private var showExportShare = false
    @State private var showMailFallback = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("Language")) {
                    Picker(L10n.tr("Language"), selection: $appLanguage) {
                        Text(L10n.tr("System")).tag(AppLanguage.system.rawValue)
                        // Language names are shown in their own language.
                        Text(verbatim: "English").tag(AppLanguage.en.rawValue)
                        Text(verbatim: "Русский").tag(AppLanguage.ru.rawValue)
                    }
                }

                Section(L10n.tr("Checks")) {
                    Picker(L10n.tr("Auto-refresh"), selection: $autoRefreshInterval) {
                        Text(L10n.tr("30 seconds")).tag(30)
                        Text(L10n.tr("1 minute")).tag(60)
                        Text(L10n.tr("5 minutes")).tag(300)
                        Text(L10n.tr("Manual only")).tag(0)
                    }
                }

                Section(L10n.tr("Data")) {
                    Picker(L10n.tr("Keep history for"), selection: $dataRetentionDays) {
                        Text(L10n.tr("7 days")).tag(7)
                        Text(L10n.tr("14 days")).tag(14)
                        Text(L10n.tr("30 days")).tag(30)
                    }

                    LabeledContent(L10n.tr("Stored checks"), value: "\(allSnapshots.count)")

                    Button(L10n.tr("Erase All Data"), role: .destructive) {
                        showEraseConfirmation = true
                    }
                }

                Section(L10n.tr("Notifications")) {
                    Toggle(L10n.tr("Alert when access drops"), isOn: $notificationsEnabled)
                    if notificationsEnabled {
                        Text(L10n.tr("Notifies when most sites become unavailable or the internet goes down. Turning a VPN on or off doesn't trigger alerts."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(L10n.tr("About")) {
                    NavigationLink(L10n.tr("How It Works")) {
                        MethodologyView()
                    }

                    Button(L10n.tr("Write to the Developer")) {
                        writeToDeveloper()
                    }

                    Button(L10n.tr("Export Data (JSON)")) {
                        exportData()
                    }
                    .disabled(allSnapshots.isEmpty)

                    LabeledContent(L10n.tr("Version"), value: Feedback.appVersion)
                }
            }
            .navigationTitle(L10n.tr("Settings"))
            .confirmationDialog(
                L10n.tr("Erase all check history and reset settings?"),
                isPresented: $showEraseConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.tr("Erase Everything"), role: .destructive) {
                    performPanicWipe()
                }
            }
            .alert(L10n.tr("All data erased"), isPresented: $showEraseSuccess) {
                Button(L10n.tr("OK")) {}
            }
            .alert(L10n.tr("Mail is not set up"), isPresented: $showMailFallback) {
                Button(L10n.tr("Copy Address")) {
                    UIPasteboard.general.string = Feedback.address
                }
                Button(L10n.tr("OK"), role: .cancel) {}
            } message: {
                Text(L10n.tr("Write to %@", Feedback.address))
            }
            .sheet(isPresented: $showExportShare) {
                if let url = exportFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    /// Opens a prepared e-mail; without a mail app, shows the address to copy instead.
    private func writeToDeveloper() {
        guard let url = Feedback.mailURL() else {
            showMailFallback = true
            return
        }
        openURL(url) { accepted in
            if !accepted { showMailFallback = true }
        }
    }

    private func performPanicWipe() {
        try? modelContext.delete(model: DiagnosticSnapshot.self)
        try? modelContext.save()

        autoRefreshInterval = 60
        dataRetentionDays = 14
        notificationsEnabled = true

        showEraseSuccess = true
    }

    private func exportData() {
        let exportable = allSnapshots.map { ExportableSnapshot(from: $0) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(exportable) else { return }

        let fileName = "netcolors_export_\(ISO8601DateFormatter().string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        guard (try? data.write(to: url)) != nil else { return }

        exportFileURL = url
        showExportShare = true
    }
}

/// UIActivityViewController wrapper for share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
