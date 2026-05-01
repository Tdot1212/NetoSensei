//
//  VPNReliabilityTracker.swift
//  NetoSensei
//
//  VPN Reliability History Tracking - 100% Real Tracking
//  Tracks: Tunnel drops, Latency spikes, Region consistency, Stability score
//  Warns: "Your VPN region is unstable. Choose another region."
//

import Foundation

actor VPNReliabilityTracker {
    static let shared = VPNReliabilityTracker()

    private init() {}

    private let vpnHistoryKey = "vpn_connection_history"
    private let vpnRegionHistoryKey = "vpn_region_history"
    private let vpnLatencyHistoryKey = "vpn_latency_history"
    private let maxHistoryEntries = 100

    // MARK: - VPN Event Tracking

    func trackVPNConnection(region: String, serverIP: String) {
        let event = VPNConnectionEvent(
            timestamp: Date(),
            eventType: .connected,
            region: region,
            serverIP: serverIP,
            latency: nil
        )

        saveConnectionEvent(event)
        updateRegionHistory(region: region)
    }

    func trackVPNDisconnection(region: String, wasForced: Bool) {
        let event = VPNConnectionEvent(
            timestamp: Date(),
            eventType: wasForced ? .tunnelDrop : .disconnected,
            region: region,
            serverIP: nil,
            latency: nil
        )

        saveConnectionEvent(event)
    }

    func trackLatencyMeasurement(region: String, latency: Double) {
        let event = VPNConnectionEvent(
            timestamp: Date(),
            eventType: .latencyMeasurement,
            region: region,
            serverIP: nil,
            latency: latency
        )

        saveConnectionEvent(event)
        saveLatencyMeasurement(region: region, latency: latency)
    }

    // MARK: - Reliability Analysis

    func getReliabilityReport() -> VPNReliabilityReport {
        let events = loadConnectionEvents()

        // Calculate tunnel drops in last 24 hours
        let last24Hours = Date().addingTimeInterval(-24 * 3600)
        let recentEvents = events.filter { $0.timestamp > last24Hours }
        let tunnelDrops = recentEvents.filter { $0.eventType == .tunnelDrop }.count

        // Get region statistics
        let regionStats = calculateRegionStatistics(events: events)

        // Detect latency spikes
        let latencySpikes = detectLatencySpikes()

        // Check region consistency
        let regionConsistency = checkRegionConsistency(events: events)

        // Calculate overall stability score
        let stabilityScore = calculateStabilityScore(
            tunnelDrops: tunnelDrops,
            latencySpikes: latencySpikes.count,
            regionConsistency: regionConsistency
        )

        // Get current region
        let currentRegion = getCurrentRegion(events: events)

        // Get unstable regions
        let unstableRegions = regionStats.filter { $0.value.stabilityScore < 60 }.map { $0.key }

        // Get best region recommendation
        let bestRegion = findBestRegion(regionStats: regionStats)

        return VPNReliabilityReport(
            tunnelDropsLast24h: tunnelDrops,
            totalConnections: events.filter { $0.eventType == .connected }.count,
            averageConnectionDuration: calculateAverageConnectionDuration(events: events),
            latencySpikes: latencySpikes,
            regionConsistency: regionConsistency,
            stabilityScore: stabilityScore,
            currentRegion: currentRegion,
            regionStatistics: regionStats,
            unstableRegions: unstableRegions,
            recommendedRegion: bestRegion
        )
    }

    func getRegionReliability(region: String) -> RegionReliability? {
        let events = loadConnectionEvents()
        let regionEvents = events.filter { $0.region == region }

        guard !regionEvents.isEmpty else { return nil }

        let connections = regionEvents.filter { $0.eventType == .connected }.count
        let tunnelDrops = regionEvents.filter { $0.eventType == .tunnelDrop }.count
        let disconnects = regionEvents.filter { $0.eventType == .disconnected }.count

        let latencyHistory = loadLatencyHistory(region: region)
        let averageLatency = latencyHistory.isEmpty ? 0 : latencyHistory.reduce(0, +) / Double(latencyHistory.count)

        let dropRate = connections > 0 ? Double(tunnelDrops) / Double(connections) * 100 : 0
        let stabilityScore = calculateRegionStabilityScore(
            connections: connections,
            tunnelDrops: tunnelDrops,
            averageLatency: averageLatency
        )

        return RegionReliability(
            region: region,
            totalConnections: connections,
            tunnelDrops: tunnelDrops,
            normalDisconnects: disconnects,
            averageLatency: averageLatency,
            dropRate: dropRate,
            stabilityScore: stabilityScore,
            lastUsed: regionEvents.first?.timestamp ?? Date()
        )
    }

    // MARK: - Private Methods

    private func saveConnectionEvent(_ event: VPNConnectionEvent) {
        var events = loadConnectionEvents()
        events.insert(event, at: 0)

        // Keep only last N entries
        if events.count > maxHistoryEntries {
            events = Array(events.prefix(maxHistoryEntries))
        }

        // FIXED: Use safe save to prevent UserDefaults crash
        UserDefaults.standard.setSafe(events, forKey: vpnHistoryKey, maxItems: 100)
    }

    private func loadConnectionEvents() -> [VPNConnectionEvent] {
        guard let data = UserDefaults.standard.data(forKey: vpnHistoryKey),
              let events = try? JSONDecoder().decode([VPNConnectionEvent].self, from: data) else {
            return []
        }
        return events
    }

    private func updateRegionHistory(region: String) {
        var regions = UserDefaults.standard.stringArray(forKey: vpnRegionHistoryKey) ?? []

        // Add region if not already at the front
        if regions.first != region {
            regions.removeAll(where: { $0 == region })
            regions.insert(region, at: 0)
        }

        // Keep only last 20 unique regions
        if regions.count > 20 {
            regions = Array(regions.prefix(20))
        }

        UserDefaults.standard.set(regions, forKey: vpnRegionHistoryKey)
    }

    private func saveLatencyMeasurement(region: String, latency: Double) {
        let key = "\(vpnLatencyHistoryKey)_\(region)"
        var measurements = UserDefaults.standard.array(forKey: key) as? [Double] ?? []

        measurements.insert(latency, at: 0)

        // Keep only last 50 measurements per region
        if measurements.count > 50 {
            measurements = Array(measurements.prefix(50))
        }

        UserDefaults.standard.set(measurements, forKey: key)
    }

    private func loadLatencyHistory(region: String) -> [Double] {
        let key = "\(vpnLatencyHistoryKey)_\(region)"
        return UserDefaults.standard.array(forKey: key) as? [Double] ?? []
    }

    private func calculateRegionStatistics(events: [VPNConnectionEvent]) -> [String: RegionReliability] {
        let regions = Set(events.map { $0.region })
        var stats: [String: RegionReliability] = [:]

        for region in regions {
            if let reliability = getRegionReliability(region: region) {
                stats[region] = reliability
            }
        }

        return stats
    }

    private func detectLatencySpikes() -> [LatencySpike] {
        var spikes: [LatencySpike] = []
        let events = loadConnectionEvents()
        let latencyEvents = events.filter { $0.eventType == .latencyMeasurement && $0.latency != nil }

        // Group by region
        let regionGroups = Dictionary(grouping: latencyEvents, by: { $0.region })

        for (region, regionEvents) in regionGroups {
            let latencies = regionEvents.compactMap { $0.latency }

            guard latencies.count > 5 else { continue }

            // Calculate baseline (median of recent measurements)
            let sortedLatencies = latencies.sorted()
            let median = sortedLatencies[sortedLatencies.count / 2]

            // Detect spikes (latency > 2x median)
            for event in regionEvents {
                guard let latency = event.latency else { continue }

                if latency > median * 2 && latency > 100 {
                    spikes.append(LatencySpike(
                        timestamp: event.timestamp,
                        region: region,
                        baselineLatency: median,
                        spikeLatency: latency,
                        magnitude: latency - median
                    ))
                }
            }
        }

        return spikes.sorted(by: { $0.timestamp > $1.timestamp })
    }

    private func checkRegionConsistency(events: [VPNConnectionEvent]) -> RegionConsistency {
        let last24Hours = Date().addingTimeInterval(-24 * 3600)
        let recentEvents = events.filter { $0.timestamp > last24Hours }

        let connectionEvents = recentEvents.filter { $0.eventType == .connected }
        let uniqueRegions = Set(connectionEvents.map { $0.region })

        if uniqueRegions.count == 1 {
            return .stable
        } else if uniqueRegions.count <= 3 {
            return .moderate
        } else {
            return .inconsistent
        }
    }

    private func getCurrentRegion(events: [VPNConnectionEvent]) -> String? {
        // Find most recent connection event
        let connectionEvent = events.first(where: { $0.eventType == .connected })
        return connectionEvent?.region
    }

    private func calculateAverageConnectionDuration(events: [VPNConnectionEvent]) -> TimeInterval {
        var durations: [TimeInterval] = []
        var currentConnection: VPNConnectionEvent?

        // Iterate through events in chronological order
        for event in events.reversed() {
            switch event.eventType {
            case .connected:
                currentConnection = event
            case .disconnected, .tunnelDrop:
                if let connection = currentConnection {
                    let duration = event.timestamp.timeIntervalSince(connection.timestamp)
                    if duration > 0 && duration < 24 * 3600 {  // Max 24 hours
                        durations.append(duration)
                    }
                }
                currentConnection = nil
            default:
                break
            }
        }

        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }

    private func calculateStabilityScore(tunnelDrops: Int, latencySpikes: Int, regionConsistency: RegionConsistency) -> Int {
        var score = 100

        // Penalize for tunnel drops
        score -= tunnelDrops * 15

        // Penalize for latency spikes
        score -= latencySpikes * 5

        // Penalize for region inconsistency
        switch regionConsistency {
        case .stable:
            break  // No penalty
        case .moderate:
            score -= 10
        case .inconsistent:
            score -= 20
        }

        return max(0, min(100, score))
    }

    private func calculateRegionStabilityScore(connections: Int, tunnelDrops: Int, averageLatency: Double) -> Int {
        var score = 100

        // Penalize for high drop rate
        if connections > 0 {
            let dropRate = Double(tunnelDrops) / Double(connections)
            score -= Int(dropRate * 100)
        }

        // Penalize for high latency
        if averageLatency > 200 {
            score -= 30
        } else if averageLatency > 100 {
            score -= 15
        } else if averageLatency > 50 {
            score -= 5
        }

        return max(0, min(100, score))
    }

    private func findBestRegion(regionStats: [String: RegionReliability]) -> String? {
        guard !regionStats.isEmpty else { return nil }

        // Find region with highest stability score
        let sorted = regionStats.sorted { $0.value.stabilityScore > $1.value.stabilityScore }
        return sorted.first?.key
    }

    // MARK: - Clear History

    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: vpnHistoryKey)
        UserDefaults.standard.removeObject(forKey: vpnRegionHistoryKey)

        // Clear all latency history
        let regions = UserDefaults.standard.stringArray(forKey: vpnRegionHistoryKey) ?? []
        for region in regions {
            let key = "\(vpnLatencyHistoryKey)_\(region)"
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

// MARK: - VPN Connection Event

struct VPNConnectionEvent: Codable, Sendable {
    let timestamp: Date
    let eventType: VPNEventType
    let region: String
    let serverIP: String?
    let latency: Double?
}

enum VPNEventType: String, Codable, Sendable {
    case connected = "Connected"
    case disconnected = "Disconnected"
    case tunnelDrop = "Tunnel Drop"
    case latencyMeasurement = "Latency Measurement"
}

// MARK: - VPN Reliability Report

struct VPNReliabilityReport: Codable, Sendable {
    let tunnelDropsLast24h: Int
    let totalConnections: Int
    let averageConnectionDuration: TimeInterval
    let latencySpikes: [LatencySpike]
    let regionConsistency: RegionConsistency
    let stabilityScore: Int
    let currentRegion: String?
    let regionStatistics: [String: RegionReliability]
    let unstableRegions: [String]
    let recommendedRegion: String?

    /// Returns true if there is actual historical tracking data.
    /// If no connections have been tracked, stability score is meaningless.
    var hasHistoricalData: Bool {
        return totalConnections > 0 || tunnelDropsLast24h > 0 || !latencySpikes.isEmpty
    }

    var statusText: String {
        if stabilityScore >= 80 {
            return "🟢 VPN Reliability Excellent"
        } else if stabilityScore >= 60 {
            return "🟡 VPN Reliability Good"
        } else if stabilityScore >= 40 {
            return "🟠 VPN Reliability Fair"
        } else {
            return "🔴 VPN Reliability Poor"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if tunnelDropsLast24h > 5 {
            recs.append("⚠️ \(tunnelDropsLast24h) tunnel drops in last 24h")
            recs.append("Your VPN connection is very unstable")
        } else if tunnelDropsLast24h > 2 {
            recs.append("⚠️ \(tunnelDropsLast24h) tunnel drops detected")
            recs.append("Connection stability needs improvement")
        }

        if !unstableRegions.isEmpty {
            recs.append("⚠️ Unstable VPN regions detected:")
            recs.append(contentsOf: unstableRegions.map { "  • \($0)" })
            recs.append("Avoid these regions for better stability")
        }

        if let currentRegion = currentRegion,
           let currentStats = regionStatistics[currentRegion],
           currentStats.stabilityScore < 60 {
            recs.append("⚠️ Your current VPN region '\(currentRegion)' is unstable")
            recs.append("Stability score: \(currentStats.stabilityScore)/100")

            if let recommended = recommendedRegion, recommended != currentRegion {
                recs.append("Recommended: Switch to '\(recommended)'")
            }
        }

        if latencySpikes.count > 5 {
            recs.append("⚠️ \(latencySpikes.count) latency spikes detected")
            recs.append("Network quality is inconsistent")
        }

        switch regionConsistency {
        case .inconsistent:
            recs.append("⚠️ Frequent region switching detected")
            recs.append("Stay on one region for better stability")
        case .moderate:
            recs.append("Region switching detected")
            recs.append("Consider sticking to one reliable region")
        case .stable:
            break
        }

        if stabilityScore >= 80 {
            recs.append("✅ VPN reliability is excellent")
            if let region = currentRegion {
                recs.append("Current region '\(region)' is performing well")
            }
        }

        return recs
    }
}

// MARK: - Region Reliability

struct RegionReliability: Codable, Sendable {
    let region: String
    let totalConnections: Int
    let tunnelDrops: Int
    let normalDisconnects: Int
    let averageLatency: Double
    let dropRate: Double
    let stabilityScore: Int
    let lastUsed: Date
}

// MARK: - Latency Spike

struct LatencySpike: Codable, Sendable {
    let timestamp: Date
    let region: String
    let baselineLatency: Double
    let spikeLatency: Double
    let magnitude: Double
}

// MARK: - Region Consistency

enum RegionConsistency: String, Codable, Sendable {
    case stable = "Stable"
    case moderate = "Moderate"
    case inconsistent = "Inconsistent"
}
