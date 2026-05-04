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

    private var fileURL: URL {
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

        // Fall back to UserDefaults v2 migration
        return await migrateFromUserDefaults()
    }

    private func readFromFile() throws -> [NetworkHistoryEntry] {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([NetworkHistoryEntry].self, from: data)
    }

    // MARK: - Save (atomic write to prevent corruption)

    func save(_ entries: [NetworkHistoryEntry]) async {
        // Trim to max entries, keeping bookmarked entries and newest entries
        let trimmed = trimEntries(entries, maxCount: maxEntries)

        do {
            let data = try encoder.encode(trimmed)

            // Write to temp file first, then atomically move
            let tempURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("history_temp_\(UUID().uuidString).json")

            try data.write(to: tempURL, options: .atomic)

            // Atomic rename/replace
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            debugLog("HistoryStorageService: save failed - \(error.localizedDescription)")
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

        guard let data = UserDefaults.standard.data(forKey: legacyKey) else {
            return []
        }

        do {
            // Try decoding with the default decoder (non-ISO8601 dates)
            let legacyDecoder = JSONDecoder()
            let entries = try legacyDecoder.decode([NetworkHistoryEntry].self, from: data)

            debugLog("HistoryStorageService: migrating \(entries.count) entries from UserDefaults")

            // Save to new file format
            await save(entries)

            // Clean up legacy storage
            UserDefaults.standard.removeObject(forKey: legacyKey)

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
                "\(entry.healthScore)",
                entry.downloadSpeed.map { String(format: "%.2f", $0) } ?? "",
                entry.uploadSpeed.map { String(format: "%.2f", $0) } ?? "",
                String(format: "%.0f", entry.latency),
                String(format: "%.0f", entry.gatewayLatency),
                String(format: "%.0f", entry.dnsLatency),
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
        UserDefaults.standard.removeObject(forKey: "network_history_v2")
    }
}
