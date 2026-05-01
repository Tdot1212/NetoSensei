//
//  NetworkHistoryManager.swift
//  NetoSensei
//
//  Persists diagnostic results for trend analysis
//

import Foundation
import SwiftUI

// MARK: - Entry Type

enum HistoryEntryType: String, Codable {
    case diagnostic = "diagnostic"
    case speedTest = "speedTest"
    case manual = "manual"
}

// MARK: - Network History Entry

struct NetworkHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let healthScore: Int           // 0-100
    let downloadSpeed: Double?     // Mbps
    let uploadSpeed: Double?       // Mbps
    let latency: Double            // ms (external)
    let gatewayLatency: Double     // ms
    let dnsLatency: Double         // ms
    let jitter: Double?            // ms
    let packetLoss: Double?        // %
    let vpnActive: Bool
    let vpnOverhead: Double?       // ms
    let rootCause: String          // "VPN Slow", "ISP Congestion", etc.
    let connectionType: String     // "WiFi", "Cellular"

    // NEW: WiFi context
    let wifiSSID: String?          // WiFi network name (nil for cellular/unknown)
    let wifiBSSID: String?         // Router MAC address

    // NEW: VPN context
    let vpnServerLocation: String? // VPN server city/country

    // NEW: Entry classification
    let entryType: HistoryEntryType

    // NEW: User data management
    var isBookmarked: Bool
    var userNote: String?

    // CodingKeys for backward compatibility
    private enum CodingKeys: String, CodingKey {
        case id, timestamp, healthScore, downloadSpeed, uploadSpeed
        case latency, gatewayLatency, dnsLatency, jitter, packetLoss
        case vpnActive, vpnOverhead, rootCause, connectionType
        case wifiSSID, wifiBSSID, vpnServerLocation, entryType
        case isBookmarked, userNote
    }

    // Custom decoder for backward compatibility with old entries
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode existing fields
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        healthScore = try container.decode(Int.self, forKey: .healthScore)
        downloadSpeed = try container.decodeIfPresent(Double.self, forKey: .downloadSpeed)
        uploadSpeed = try container.decodeIfPresent(Double.self, forKey: .uploadSpeed)
        latency = try container.decode(Double.self, forKey: .latency)
        gatewayLatency = try container.decode(Double.self, forKey: .gatewayLatency)
        dnsLatency = try container.decode(Double.self, forKey: .dnsLatency)
        jitter = try container.decodeIfPresent(Double.self, forKey: .jitter)
        packetLoss = try container.decodeIfPresent(Double.self, forKey: .packetLoss)
        vpnActive = try container.decode(Bool.self, forKey: .vpnActive)
        vpnOverhead = try container.decodeIfPresent(Double.self, forKey: .vpnOverhead)
        rootCause = try container.decode(String.self, forKey: .rootCause)
        connectionType = try container.decode(String.self, forKey: .connectionType)

        // Decode NEW fields with fallbacks for old data
        wifiSSID = try container.decodeIfPresent(String.self, forKey: .wifiSSID)
        wifiBSSID = try container.decodeIfPresent(String.self, forKey: .wifiBSSID)
        vpnServerLocation = try container.decodeIfPresent(String.self, forKey: .vpnServerLocation)
        entryType = try container.decodeIfPresent(HistoryEntryType.self, forKey: .entryType) ?? .diagnostic
        isBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
        userNote = try container.decodeIfPresent(String.self, forKey: .userNote)
    }

    // Convenience initializer for creating entries
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        healthScore: Int,
        downloadSpeed: Double?,
        uploadSpeed: Double?,
        latency: Double,
        gatewayLatency: Double,
        dnsLatency: Double,
        jitter: Double?,
        packetLoss: Double?,
        vpnActive: Bool,
        vpnOverhead: Double?,
        rootCause: String,
        connectionType: String,
        wifiSSID: String? = nil,
        wifiBSSID: String? = nil,
        vpnServerLocation: String? = nil,
        entryType: HistoryEntryType = .diagnostic,
        isBookmarked: Bool = false,
        userNote: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.healthScore = healthScore
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.latency = latency
        self.gatewayLatency = gatewayLatency
        self.dnsLatency = dnsLatency
        self.jitter = jitter
        self.packetLoss = packetLoss
        self.vpnActive = vpnActive
        self.vpnOverhead = vpnOverhead
        self.rootCause = rootCause
        self.connectionType = connectionType
        self.wifiSSID = wifiSSID
        self.wifiBSSID = wifiBSSID
        self.vpnServerLocation = vpnServerLocation
        self.entryType = entryType
        self.isBookmarked = isBookmarked
        self.userNote = userNote
    }

    // Create from NetworkStatus and optional SpeedTestResult
    init(
        from status: NetworkStatus,
        speedTest: SpeedTestResult? = nil,
        rootCause: String = "Unknown",
        entryType: HistoryEntryType = .diagnostic,
        vpnServerLocation: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()

        // Calculate health score from status
        self.healthScore = Self.calculateHealthScore(from: status)

        self.downloadSpeed = speedTest?.downloadSpeed
        self.uploadSpeed = speedTest?.uploadSpeed
        self.latency = status.internet.latencyToExternal ?? 0
        self.gatewayLatency = status.router.latency ?? 0
        self.dnsLatency = status.dns.latency ?? 0
        self.jitter = status.router.jitter
        self.packetLoss = status.router.packetLoss
        self.vpnActive = status.vpn.isActive
        self.vpnOverhead = status.vpn.isActive ? (status.vpn.tunnelLatency ?? 0) - (status.router.latency ?? 0) : nil
        self.rootCause = rootCause
        self.connectionType = status.connectionType?.displayName ?? "Unknown"

        // NEW: WiFi context from status
        self.wifiSSID = status.wifi.ssid
        self.wifiBSSID = status.wifi.bssid

        // NEW: VPN context
        self.vpnServerLocation = vpnServerLocation

        // NEW: Entry type and user data
        self.entryType = entryType
        self.isBookmarked = false
        self.userNote = nil
    }

    private static func calculateHealthScore(from status: NetworkStatus) -> Int {
        var score = 100

        // Deduct for latency issues
        if let latency = status.internet.latencyToExternal {
            if latency > 200 { score -= 30 }
            else if latency > 100 { score -= 15 }
            else if latency > 50 { score -= 5 }
        } else {
            score -= 40 // No connectivity
        }

        // Deduct for gateway issues
        if let gateway = status.router.latency {
            if gateway > 50 { score -= 20 }
            else if gateway > 20 { score -= 10 }
        }

        // Deduct for packet loss
        if let loss = status.router.packetLoss, loss > 2 {
            score -= Int(loss * 5)
        }

        // Deduct for DNS issues
        if let dns = status.dns.latency, dns > 100 {
            score -= 10
        }

        return max(0, min(100, score))
    }
}

// MARK: - History Period

enum HistoryPeriod: String, CaseIterable {
    case last24h = "24h"
    case last7d = "7d"
    case last30d = "30d"

    var timeInterval: TimeInterval {
        switch self {
        case .last24h: return 86400
        case .last7d: return 604800
        case .last30d: return 2592000
        }
    }
}

// MARK: - Network History Manager

class NetworkHistoryManager: ObservableObject {
    static let shared = NetworkHistoryManager()

    @Published var entries: [NetworkHistoryEntry] = []

    // Now using file-based storage via HistoryStorageService
    // Supports 1000 entries with atomic writes and auto-migration from UserDefaults
    private let maxEntries = 1000

    private init() {
        loadHistory()
    }

    // MARK: - Add Entry

    func addEntry(_ entry: NetworkHistoryEntry) {
        entries.append(entry)

        // Trim old entries
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }

        saveHistory()
    }

    // Add from status (convenience method)
    func addEntry(from status: NetworkStatus, speedTest: SpeedTestResult? = nil, rootCause: String = "Unknown") {
        let entry = NetworkHistoryEntry(from: status, speedTest: speedTest, rootCause: rootCause)
        addEntry(entry)
    }

    // MARK: - Query Entries

    func entriesForPeriod(_ period: HistoryPeriod) -> [NetworkHistoryEntry] {
        let cutoff = Date().addingTimeInterval(-period.timeInterval)
        return entries.filter { $0.timestamp > cutoff }
    }

    // MARK: - Baseline Calculation

    /// Baseline: average of the best 20% of measurements
    var baseline: NetworkHistoryEntry? {
        guard entries.count >= 5 else { return nil }

        let sorted = entries.sorted { $0.healthScore > $1.healthScore }
        let topCount = max(1, sorted.count / 5)
        let topEntries = Array(sorted.prefix(topCount))

        // Calculate averages
        let avgHealth = topEntries.map { $0.healthScore }.reduce(0, +) / topCount
        let avgLatency = topEntries.map { $0.latency }.reduce(0, +) / Double(topCount)
        let avgGateway = topEntries.map { $0.gatewayLatency }.reduce(0, +) / Double(topCount)
        let avgDns = topEntries.map { $0.dnsLatency }.reduce(0, +) / Double(topCount)

        let downSpeeds = topEntries.compactMap { $0.downloadSpeed }
        let avgDownSpeed = downSpeeds.isEmpty ? nil : downSpeeds.reduce(0, +) / Double(downSpeeds.count)

        let upSpeeds = topEntries.compactMap { $0.uploadSpeed }
        let avgUpSpeed = upSpeeds.isEmpty ? nil : upSpeeds.reduce(0, +) / Double(upSpeeds.count)

        return NetworkHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            healthScore: avgHealth,
            downloadSpeed: avgDownSpeed,
            uploadSpeed: avgUpSpeed,
            latency: avgLatency,
            gatewayLatency: avgGateway,
            dnsLatency: avgDns,
            jitter: nil,
            packetLoss: nil,
            vpnActive: false,
            vpnOverhead: nil,
            rootCause: "Baseline",
            connectionType: "WiFi",
            wifiSSID: nil,
            wifiBSSID: nil,
            vpnServerLocation: nil,
            entryType: .diagnostic,
            isBookmarked: false,
            userNote: nil
        )
    }

    // MARK: - Statistics

    func averageHealthScore(for period: HistoryPeriod) -> Double? {
        let periodEntries = entriesForPeriod(period)
        guard !periodEntries.isEmpty else { return nil }
        return Double(periodEntries.map { $0.healthScore }.reduce(0, +)) / Double(periodEntries.count)
    }

    func averageLatency(for period: HistoryPeriod) -> Double? {
        let periodEntries = entriesForPeriod(period)
        guard !periodEntries.isEmpty else { return nil }
        return periodEntries.map { $0.latency }.reduce(0, +) / Double(periodEntries.count)
    }

    func averageDownloadSpeed(for period: HistoryPeriod) -> Double? {
        let periodEntries = entriesForPeriod(period)
        let speeds = periodEntries.compactMap { $0.downloadSpeed }
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    // Root cause breakdown
    func rootCauseBreakdown(for period: HistoryPeriod) -> [String: Int] {
        let periodEntries = entriesForPeriod(period)
        var breakdown: [String: Int] = [:]
        for entry in periodEntries {
            breakdown[entry.rootCause, default: 0] += 1
        }
        return breakdown
    }

    // MARK: - Persistence (using HistoryStorageService)

    private func saveHistory() {
        // Save in background using the file-based storage service
        let snapshot = entries
        Task.detached(priority: .utility) {
            await HistoryStorageService.shared.save(snapshot)
        }
    }

    private func loadHistory() {
        // Load asynchronously from file storage
        Task {
            let loaded = await HistoryStorageService.shared.load()
            await MainActor.run {
                self.entries = loaded
            }
        }
    }

    // MARK: - Clear History

    func clearHistory(keepBookmarked: Bool = false) {
        if keepBookmarked {
            entries = entries.filter { $0.isBookmarked }
            saveHistory()
        } else {
            entries.removeAll()
            Task.detached {
                await HistoryStorageService.shared.deleteAll()
            }
        }
    }

    // MARK: - Bookmark Management

    func toggleBookmark(for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isBookmarked.toggle()
        saveHistory()
    }

    func setNote(for id: UUID, note: String?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].userNote = note
        saveHistory()
    }

    // MARK: - Delete Entry

    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        saveHistory()
    }

    // MARK: - Network Filter Support

    /// All unique WiFi SSIDs seen in history (non-nil, non-empty only)
    var knownNetworks: [String] {
        let ssids = entries.compactMap { $0.wifiSSID }
            .filter { !$0.isEmpty && $0 != "Unknown" }
        return Array(Set(ssids)).sorted()
    }

    /// Query entries by period and optional network filter
    func entriesForPeriod(_ period: HistoryPeriod, filteredBy ssid: String? = nil) -> [NetworkHistoryEntry] {
        let cutoff = Date().addingTimeInterval(-period.timeInterval)
        var result = entries.filter { $0.timestamp > cutoff }
        if let ssid = ssid {
            result = result.filter { $0.wifiSSID == ssid }
        }
        return result.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Export

    /// Export entries to CSV format
    func exportCSV() async -> String {
        await HistoryStorageService.shared.exportCSV(entries: entries)
    }
}
