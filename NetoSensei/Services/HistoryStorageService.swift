//
//  HistoryStorageService.swift
//  NetoSensei
//
//  File-based storage for history entries with atomic writes and migration support
//

import Foundation

// MARK: - History Storage Service

actor HistoryStorageService {
    static let shared = HistoryStorageService()

    private let maxEntries = 1000
    private let storageURL: URL?
    private let defaults: UserDefaults
    private var latestRevision = -1

    init(fileURL: URL? = nil, userDefaults: UserDefaults = .standard) {
        storageURL = fileURL
        defaults = userDefaults
    }

    private var fileURL: URL {
        if let storageURL { return storageURL }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("network_history_v3.json")
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Load

    func load() async -> [NetworkHistoryEntry] {
        // First try reading from v3 file
        if let entries = try? readFromFile() {
            return entries
        }

        // Preserve unreadable data before a later save could replace it.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("history-corrupt-\(UUID().uuidString).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }
        return await migrateFromUserDefaults()
    }

    private func readFromFile() throws -> [NetworkHistoryEntry] {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([NetworkHistoryEntry].self, from: data)
    }

    // MARK: - Save (atomic write to prevent corruption)

    @discardableResult
    func save(_ entries: [NetworkHistoryEntry], revision: Int? = nil) async -> Bool {
        if let revision {
            guard revision > latestRevision else { return false }
            latestRevision = revision
        }
        // Trim to max entries, keeping bookmarked entries and newest entries
        let trimmed = trimEntries(entries, maxCount: maxEntries)

        do {
            let data = try encoder.encode(trimmed)

            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            debugLog("HistoryStorageService: save failed - \(error.localizedDescription)")
            return false
        }
    }

    private func trimEntries(_ entries: [NetworkHistoryEntry], maxCount: Int) -> [NetworkHistoryEntry] {
        guard entries.count > maxCount else { return entries }

        // Separate bookmarked and non-bookmarked
        let bookmarked = entries.filter { $0.isBookmarked }
        let nonBookmarked = entries.filter { !$0.isBookmarked }

        // Keep all bookmarked entries + newest non-bookmarked up to max
        let remainingSlots = maxCount - bookmarked.count
        let sortedNonBookmarked = nonBookmarked.sorted { $0.timestamp > $1.timestamp }
        let keptNonBookmarked = Array(sortedNonBookmarked.prefix(max(0, remainingSlots)))

        return (bookmarked + keptNonBookmarked).sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Migration from UserDefaults

    private func migrateFromUserDefaults() async -> [NetworkHistoryEntry] {
        let legacyKey = "network_history_v2"

        guard let data = defaults.data(forKey: legacyKey) else {
            return []
        }

        do {
            // Try decoding with the default decoder (non-ISO8601 dates)
            let legacyDecoder = JSONDecoder()
            let entries = try legacyDecoder.decode([NetworkHistoryEntry].self, from: data)

            debugLog("HistoryStorageService: migrating \(entries.count) entries from UserDefaults")

            // Save to new file format
            if await save(entries) {
                defaults.removeObject(forKey: legacyKey)
            }

            return entries
        } catch {
            debugLog("HistoryStorageService: migration failed - \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Export CSV

    func exportCSV(entries: [NetworkHistoryEntry]) -> String {
        var csv = "Timestamp,Health Score,Download (Mbps),Upload (Mbps),"
        csv += "Latency (ms),Gateway (ms),DNS (ms),Jitter (ms),"
        csv += "Packet Loss (%),VPN Active,VPN Location,Connection Type,"
        csv += "WiFi SSID,Root Cause,Bookmarked,Note\n"

        let dateFormatter = ISO8601DateFormatter()

        for entry in entries {
            let fields: [String] = [
                dateFormatter.string(from: entry.timestamp),
                entry.healthScore.map(String.init) ?? "",
                entry.downloadSpeed.map { String(format: "%.2f", $0) } ?? "",
                entry.uploadSpeed.map { String(format: "%.2f", $0) } ?? "",
                entry.latency.map { String(format: "%.0f", $0) } ?? "",
                entry.gatewayLatency.map { String(format: "%.0f", $0) } ?? "",
                entry.dnsLatency.map { String(format: "%.0f", $0) } ?? "",
                entry.jitter.map { String(format: "%.1f", $0) } ?? "",
                entry.packetLoss.map { String(format: "%.1f", $0) } ?? "",
                entry.vpnActive ? "Yes" : "No",
                entry.vpnServerLocation ?? "",
                entry.connectionType,
                entry.wifiSSID ?? "",
                entry.rootCause,
                entry.isBookmarked ? "Yes" : "No",
                entry.userNote ?? ""
            ]

            // Escape fields for CSV (wrap in quotes if contains comma, quote, or newline)
            let escapedFields = fields.map { field -> String in
                if field.contains(",") || field.contains("\"") || field.contains("\n") {
                    return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return field
            }

            csv += escapedFields.joined(separator: ",") + "\n"
        }

        return csv
    }

    // MARK: - Delete All

    func deleteAll() async {
        try? FileManager.default.removeItem(at: fileURL)
        defaults.removeObject(forKey: "network_history_v2")
    }
}
