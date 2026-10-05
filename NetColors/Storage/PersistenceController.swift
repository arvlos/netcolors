import SwiftData
import Foundation

/// SwiftData persistence for diagnostic history.
struct PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    init() {
        let schema = Schema([DiagnosticSnapshot.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}

/// Deletes snapshots older than the configured retention period.
enum DataRetentionManager {
    static func cleanup(in container: ModelContainer) {
        // @AppStorage does not write its default, so an unset value means the Settings default (14).
        let days = UserDefaults.standard.object(forKey: "dataRetentionDays") as? Int ?? 14
        guard days > 0 else { return }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }

        let context = ModelContext(container)
        let predicate = #Predicate<DiagnosticSnapshot> { $0.timestamp < cutoff }
        try? context.delete(model: DiagnosticSnapshot.self, where: predicate)
        try? context.save()
    }
}
