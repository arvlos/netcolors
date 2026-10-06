import SwiftUI
import SwiftData

@main
struct NetColorsApp: App {
    @StateObject private var engine: ProbeEngine
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @State private var selectedTab: AppTab

    let container: ModelContainer
    private let isDemo: Bool

    init() {
        #if DEBUG
        let demoMode = ScreenshotDemo.mode
        #else
        let demoMode: AccessMode? = nil
        #endif
        isDemo = demoMode != nil

        let schema = Schema([DiagnosticSnapshot.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isDemo)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        #if DEBUG
        if let demoMode {
            _engine = StateObject(wrappedValue: ScreenshotDemo.makeEngine(mode: demoMode))
            _selectedTab = State(initialValue: Self.tab(named: ScreenshotDemo.tab))
            ScreenshotDemo.fillHistory(in: container)
            return
        }
        #endif
        _engine = StateObject(wrappedValue: ProbeEngine())
        _selectedTab = State(initialValue: .status)
        BackgroundMonitor.registerTask()
    }

    var body: some Scene {
        WindowGroup {
            // Strings are looked up when views are built, so a language change rebuilds the tree.
            // The selected tab lives here and survives the rebuild.
            root
                .id(appLanguage)
                .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
                .environmentObject(engine)
                .modelContainer(container)
                .task {
                    guard !isDemo else { return }
                    engine.modelContainer = container
                    DataRetentionManager.cleanup(in: container)
                    engine.startAutoRefresh()
                    BackgroundMonitor.requestNotificationPermission()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !isDemo else { return }
            if newPhase == .background {
                engine.stopAutoRefresh()
                BackgroundMonitor.scheduleNextRefresh()
            } else if newPhase == .active {
                engine.startAutoRefresh()
            }
        }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if isDemo && ScreenshotDemo.tab == "howitworks" {
            NavigationStack { MethodologyView() }
        } else {
            ContentView(selection: $selectedTab)
        }
        #else
        ContentView(selection: $selectedTab)
        #endif
    }

    private static func tab(named name: String) -> AppTab {
        switch name {
        case "diagnostics": .diagnostics
        case "history": .history
        case "settings": .settings
        default: .status
        }
    }
}
