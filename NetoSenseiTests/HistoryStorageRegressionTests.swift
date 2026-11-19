import Testing
import Foundation
@testable import NetoSensei

struct HistoryStorageRegressionTests {
    @Test func atomicRoundTripAndOutOfOrderSaveDoesNotLoseNewest() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStorageService(fileURL: folder.appendingPathComponent("history.json"))
        let older = entry(note: "old"), newer = entry(note: "new")
        #expect(await store.save([newer], revision: 2))
        #expect(!(await store.save([older], revision: 1)))
        let loaded = await store.load()
        #expect(loaded.count == 1 && loaded[0].id == newer.id)
        #expect(loaded[0].gatewayLatency == nil && loaded[0].healthScore == nil)
        #expect(await store.save([], revision: 3))
        #expect(await store.load().isEmpty)
    }

    @Test func failedMigrationPreservesLegacyCopy() async throws {
        let suite = "NetoSenseiTest-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = [entry(note: "retain")]
        defaults.set(try JSONEncoder().encode(original), forKey: "network_history_v2")
        // Deliberately unwritable: missing parent directory in a test-only location.
        let impossible = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("missing/history.json")
        let store = HistoryStorageService(fileURL: impossible, userDefaults: defaults)
        let loaded = await store.load()
        #expect(loaded.count == 1)
        #expect(defaults.data(forKey: "network_history_v2") != nil)
    }

    @Test func successfulMigrationRemovesLegacyOnlyAfterWritingAndCSVKeepsUnknownBlank() async throws {
        let suite = "NetoSenseiTest-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let record = entry(note: "Comma, quote\" and\nnewline")
        defaults.set(try JSONEncoder().encode([record]), forKey: "network_history_v2")
        let store = HistoryStorageService(fileURL: folder.appendingPathComponent("history.json"), userDefaults: defaults)
        #expect(await store.load().count == 1)
        #expect(defaults.data(forKey: "network_history_v2") == nil)
        let csv = await store.exportCSV(entries: [record])
        #expect(!csv.contains("Optional") && !csv.contains("nil"))
        #expect(csv.contains("\"Comma, quote\"\" and\nnewline\""))
        await store.deleteAll()
        #expect(await store.load().isEmpty)
    }

    private func entry(note: String) -> NetworkHistoryEntry {
        NetworkHistoryEntry(healthScore: nil, downloadSpeed: nil, uploadSpeed: nil, latency: nil,
            gatewayLatency: nil, dnsLatency: nil, jitter: nil, packetLoss: nil, vpnActive: false,
            vpnOverhead: nil, rootCause: "Unknown", connectionType: "WiFi", userNote: note)
    }
}
