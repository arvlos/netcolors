import SwiftUI
import SwiftData

@main
struct NetColorsApp: App {
    @StateObject private var engine = ProbeEngine()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @State private var selectedTab: AppTab = .status

    let container: ModelContainer

    init() {
        let schema = Schema([DiagnosticSnapshot.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        BackgroundMonitor.registerTask()
    }

    var body: some Scene {
        WindowGroup {
            // Strings are looked up when views are built, so a language change rebuilds the tree.
            // The selected tab lives here and survives the rebuild.
            ContentView(selection: $selectedTab)
                .id(appLanguage)
                .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
                .environmentObject(engine)
                .modelContainer(container)
                .task {
                    engine.modelContainer = container
                    DataRetentionManager.cleanup(in: container)
                    engine.startAutoRefresh()
                    BackgroundMonitor.requestNotificationPermission()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                engine.stopAutoRefresh()
                BackgroundMonitor.scheduleNextRefresh()
            } else if newPhase == .active {
                engine.startAutoRefresh()
            }
        }
    }
}
