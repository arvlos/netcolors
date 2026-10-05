import SwiftUI

enum AppTab: Hashable {
    case status
    case diagnostics
    case history
    case settings
}

struct ContentView: View {
    @Binding var selection: AppTab

    var body: some View {
        TabView(selection: $selection) {
            TrafficLightView()
                .tabItem {
                    Label(L10n.tr("Status"), systemImage: "circle.fill")
                }
                .tag(AppTab.status)

            DiagnosticsView()
                .tabItem {
                    Label(L10n.tr("Diagnostics"), systemImage: "list.bullet")
                }
                .tag(AppTab.diagnostics)

            HistoryView()
                .tabItem {
                    Label(L10n.tr("History"), systemImage: "clock")
                }
                .tag(AppTab.history)

            SettingsView()
                .tabItem {
                    Label(L10n.tr("Settings"), systemImage: "gear")
                }
                .tag(AppTab.settings)
        }
    }
}
