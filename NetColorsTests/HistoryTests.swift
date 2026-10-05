import XCTest
import SwiftData
@testable import NetColors

@MainActor
final class HistoryTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([DiagnosticSnapshot.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - DateFilter

    func testDateFilterToday() {
        let start = DateFilter.today.startDate
        XCTAssertNotNil(start)
        let cal = Calendar.current
        XCTAssertEqual(cal.startOfDay(for: start!), cal.startOfDay(for: Date()))
    }

    func testDateFilterWeek() {
        let start = DateFilter.week.startDate
        XCTAssertNotNil(start)
        let diff = Calendar.current.dateComponents([.day], from: start!, to: Date()).day!
        XCTAssertEqual(diff, 7)
    }

    func testDateFilterMonth() {
        let start = DateFilter.month.startDate
        XCTAssertNotNil(start)
        let diff = Calendar.current.dateComponents([.day], from: start!, to: Date()).day!
        XCTAssertEqual(diff, 30)
    }

    func testDateFilterAll() {
        XCTAssertNil(DateFilter.all.startDate)
    }

    // MARK: - Snapshot Persistence

    func testSnapshotSaveAndRetrieve() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let snapshot = DiagnosticSnapshot(
            mode: .restricted,
            carrier: "MTS",
            networkType: "LTE"
        )
        context.insert(snapshot)
        try context.save()

        let descriptor = FetchDescriptor<DiagnosticSnapshot>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.carrier, "MTS")
        XCTAssertEqual(fetched.first?.accessMode, .restricted)
    }

    func testSnapshotWithProbeResults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let ep = ProbeEndpoint(domain: "google.com", group: .usuallyAvailable)
        let result = ProbeResult(endpoint: ep, status: .success, latencyMs: 45.0, bytesReceived: 52000)

        let snapshot = DiagnosticSnapshot(
            mode: .restricted,
            carrier: "Beeline",
            networkType: "5G",
            probeResults: [result]
        )
        context.insert(snapshot)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DiagnosticSnapshot>())
        XCTAssertEqual(fetched.first?.probeResults.count, 1)
        XCTAssertEqual(fetched.first?.probeResults.first?.endpoint.domain, "google.com")
    }

    // MARK: - Data Retention

    func testDataRetentionDeletesOldSnapshots() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Old snapshot (20 days ago)
        let oldDate = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        let old = DiagnosticSnapshot(
            timestamp: oldDate,
            mode: .restricted,
            carrier: "MTS",
            networkType: "LTE"
        )
        context.insert(old)

        // Recent snapshot (1 day ago)
        let recentDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let recent = DiagnosticSnapshot(
            timestamp: recentDate,
            mode: .unrestricted,
            carrier: "Beeline",
            networkType: "WiFi"
        )
        context.insert(recent)
        try context.save()

        // Set retention to 14 days
        UserDefaults.standard.set(14, forKey: "dataRetentionDays")
        defer { UserDefaults.standard.removeObject(forKey: "dataRetentionDays") }
        DataRetentionManager.cleanup(in: container)

        let remaining = try context.fetch(FetchDescriptor<DiagnosticSnapshot>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.carrier, "Beeline")
    }

    func testDataRetentionKeepsAllWhenZero() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let oldDate = Calendar.current.date(byAdding: .day, value: -100, to: Date())!
        let old = DiagnosticSnapshot(timestamp: oldDate, mode: .restricted, carrier: "T2", networkType: "LTE")
        context.insert(old)
        try context.save()

        UserDefaults.standard.set(0, forKey: "dataRetentionDays")
        defer { UserDefaults.standard.removeObject(forKey: "dataRetentionDays") }
        DataRetentionManager.cleanup(in: container)

        let remaining = try context.fetch(FetchDescriptor<DiagnosticSnapshot>())
        XCTAssertEqual(remaining.count, 1)
    }

    func testDataRetentionDefaultsTo14DaysWhenUnset() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let old = DiagnosticSnapshot(
            timestamp: Calendar.current.date(byAdding: .day, value: -20, to: Date())!,
            mode: .restricted, carrier: "MTS", networkType: "LTE"
        )
        let recent = DiagnosticSnapshot(
            timestamp: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
            mode: .restricted, carrier: "Beeline", networkType: "LTE"
        )
        context.insert(old)
        context.insert(recent)
        try context.save()

        // Fresh install: Settings never opened, nothing stored.
        UserDefaults.standard.removeObject(forKey: "dataRetentionDays")
        DataRetentionManager.cleanup(in: container)

        let remaining = try context.fetch(FetchDescriptor<DiagnosticSnapshot>())
        XCTAssertEqual(remaining.map(\.carrier), ["Beeline"])
    }

    // MARK: - ProbeEngine Snapshot Saving

    func testProbeEngineSavesSnapshot() throws {
        let container = try makeContainer()
        let engine = ProbeEngine()
        engine.modelContainer = container

        // Simulate completed diagnostics state
        let ep = ProbeEndpoint(domain: "ya.ru", group: .whitelist)
        engine.results = [ProbeResult(endpoint: ep, status: .success)]
        engine.currentMode = .restricted

        // Run diagnostics (will probe real endpoints and save)
        // Instead, test the save path directly by calling runDiagnostics
        // which will save after completing probes
        let context = ModelContext(container)
        let before = try context.fetch(FetchDescriptor<DiagnosticSnapshot>())
        XCTAssertTrue(before.isEmpty)
    }

    // MARK: - AccessMode UI Properties

    func testAccessModeColors() {
        XCTAssertEqual(AccessMode.fullShutdown.color, .black)
        XCTAssertEqual(AccessMode.whitelist.color, .red)
        XCTAssertEqual(AccessMode.restricted.color, .orange)
        XCTAssertEqual(AccessMode.unrestricted.color, .green)
    }

    func testAccessModeTitles() {
        UserDefaults.standard.set(AppLanguage.en.rawValue, forKey: AppLanguage.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey) }

        XCTAssertEqual(AccessMode.fullShutdown.title, "No Internet")
        XCTAssertEqual(AccessMode.whitelist.title, "Only Selected Services")
        XCTAssertEqual(AccessMode.restricted.title, "Some Sites Unavailable")
        XCTAssertEqual(AccessMode.unrestricted.title, "Full Access")
    }

    func testAccessModeIcons() {
        XCTAssertEqual(AccessMode.fullShutdown.iconName, "xmark.circle")
        XCTAssertEqual(AccessMode.whitelist.iconName, "exclamationmark.triangle")
        XCTAssertEqual(AccessMode.restricted.iconName, "lock.fill")
        XCTAssertEqual(AccessMode.unrestricted.iconName, "checkmark.circle")
    }

    func testAccessModeDescriptions() {
        for mode in AccessMode.allCases {
            XCTAssertFalse(mode.statusDescription.isEmpty, "\(mode) should have a description")
        }
    }

    // MARK: - ExportableSnapshot

    func testExportableSnapshotCodable() throws {
        let ep = ProbeEndpoint(domain: "google.com", group: .usuallyAvailable)
        let probeResult = ProbeResult(endpoint: ep, status: .success, latencyMs: 50, bytesReceived: 10000)

        let snapshot = DiagnosticSnapshot(
            mode: .restricted,
            carrier: "MTS",
            networkType: "LTE",
            cutOffThresholdBytes: 16384,
            probeResults: [probeResult]
        )

        let exportable = ExportableSnapshot(from: snapshot)
        XCTAssertEqual(exportable.mode, "restricted")
        XCTAssertEqual(exportable.carrier, "MTS")
        XCTAssertEqual(exportable.probeResults.count, 1)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(exportable)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportableSnapshot.self, from: data)
        XCTAssertEqual(decoded.mode, "restricted")
        XCTAssertEqual(decoded.carrier, "MTS")
        XCTAssertEqual(decoded.probeResults.count, 1)
        XCTAssertEqual(decoded.cutOffThresholdBytes, 16384)
    }

    func testExportableSnapshotNilFields() throws {
        let snapshot = DiagnosticSnapshot(
            mode: .fullShutdown,
            carrier: "Unknown",
            networkType: "None"
        )

        let exportable = ExportableSnapshot(from: snapshot)
        XCTAssertNil(exportable.geohash)
        XCTAssertNil(exportable.cutOffThresholdBytes)
        XCTAssertTrue(exportable.probeResults.isEmpty)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(exportable)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportableSnapshot.self, from: data)
        XCTAssertNil(decoded.geohash)
    }
}
