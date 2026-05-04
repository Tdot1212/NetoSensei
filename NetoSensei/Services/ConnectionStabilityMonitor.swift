//
//  ConnectionStabilityMonitor.swift
//  NetoSensei
//
//  Connection Stability Monitor - Tracks network events over time
//  Provides stability metrics and event history for user insights
//

import Foundation
import Combine

// MARK: - Stability Event Types

enum StabilityEventType: String, Codable {
    case connected = "Connected"
    case disconnected = "Disconnected"
    case latencySpike = "Latency Spike"
    case packetLoss = "Packet Loss"
    case interfaceChanged = "Interface Changed"
    case vpnConnected = "VPN Connected"
    case vpnDisconnected = "VPN Disconnected"
    case qualityDegraded = "Quality Degraded"
    case qualityImproved = "Quality Improved"
}

struct StabilityEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let type: StabilityEventType
    let details: String
    let latency: Double?
    let connectionType: String?

    init(type: StabilityEventType, details: String, latency: Double? = nil, connectionType: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.details = details
        self.latency = latency
        self.connectionType = connectionType
    }
}

// MARK: - Connection Stability Metrics

struct ConnectionStabilityMetrics {
    let uptimePercentage: Double         // % of time connected in tracking period
    let averageLatency: Double?          // Average latency when connected
    let disconnectCount: Int             // Number of disconnects
    let latencySpikeCount: Int           // Number of latency spikes (>200ms)
    let lastDisconnect: Date?            // When was last disconnect
    let stableSince: Date?               // When did current stable period start
    let connectionQuality: ConnectionQualityLevel

    enum ConnectionQualityLevel: String {
        case excellent = "Excellent"  // >99% uptime, <50ms avg latency, 0 spikes
        case good = "Good"            // >95% uptime, <100ms avg latency, <3 spikes
        case fair = "Fair"            // >90% uptime, <200ms avg latency
        case poor = "Poor"            // <90% uptime or >200ms avg latency

        var description: String {
            switch self {
            case .excellent: return "Rock solid connection"
            case .good: return "Stable with minor variations"
            case .fair: return "Some instability detected"
            case .poor: return "Frequent issues detected"
            }
        }
    }
}

// MARK: - Connection Stability Monitor

@MainActor
class ConnectionStabilityMonitor: ObservableObject {
    static let shared = ConnectionStabilityMonitor()

    // MARK: - Published Properties

    @Published var events: [StabilityEvent] = []
    @Published var isMonitoring = false
    @Published var currentMetrics: ConnectionStabilityMetrics?

    // MARK: - Configuration

    // FIXED: Reduced from 500 to 100 events to prevent UserDefaults crash
    // 500 events could exceed UserDefaults ~1MB limit when encoded
    private let maxEvents = 100               // Keep last 100 events (was 500)
    private let trackingWindowHours = 24      // Calculate metrics over 24 hours
    private let latencySpikeThreshold = 200.0 // >200ms = spike
    private let metricsUpdateInterval = 60.0  // Update metrics every 60s

    // MARK: - State Tracking

    private var lastKnownStatus: NetworkStatus?
    private var lastConnectedTime: Date?
    private var totalConnectedTime: TimeInterval = 0
    private var trackingStartTime: Date?

    // FIXED: Startup delay and debouncing to prevent event spam
    private var appStartTime: Date = Date()
    private var lastEventTime: Date?
    private let startupDelay: TimeInterval = 5.0      // Don't fire events for first 5 seconds
    private let minEventInterval: TimeInterval = 5.0  // Debounce: max 1 event per 5 seconds

    // MARK: - Services

    private var cancellables = Set<AnyCancellable>()
    private let networkMonitor: NetworkMonitorService
    private var metricsTimer: Timer?

    // MARK: - Persistence

    private let userDefaults = UserDefaults.standard
    private let eventsKey = "stabilityEvents"

    // MARK: - Initialization

    private init() {
        self.networkMonitor = NetworkMonitorService.shared
        loadEvents()
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        trackingStartTime = Date()
        appStartTime = Date()  // FIXED: Reset startup time when monitoring starts

        // Subscribe to network status changes
        networkMonitor.$currentStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                self?.processStatusChange(newStatus)
            }
            .store(in: &cancellables)

        // Update metrics periodically
        metricsTimer = Timer.scheduledTimer(withTimeInterval: metricsUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMetrics()
            }
        }

        // Initial metrics calculation
        updateMetrics()

        debugLog("📊 Connection Stability Monitor started")
    }

    func stopMonitoring() {
        isMonitoring = false
        cancellables.removeAll()
        metricsTimer?.invalidate()
        metricsTimer = nil

        // Save final state
        saveEvents()

        debugLog("📊 Connection Stability Monitor stopped")
    }

    // MARK: - Status Processing

    private func processStatusChange(_ newStatus: NetworkStatus) {
        defer {
            lastKnownStatus = newStatus
        }

        guard let oldStatus = lastKnownStatus else {
            // First status - record initial state
            if newStatus.internet.isReachable {
                lastConnectedTime = Date()
                recordEvent(.connected, details: "Monitoring started")
            }
            return
        }

        // Check for connection state changes
        let wasConnected = oldStatus.internet.isReachable
        let isConnected = newStatus.internet.isReachable

        if wasConnected && !isConnected {
            // Disconnected
            if let connectedSince = lastConnectedTime {
                totalConnectedTime += Date().timeIntervalSince(connectedSince)
            }
            lastConnectedTime = nil
            recordEvent(.disconnected, details: "Internet connection lost")

        } else if !wasConnected && isConnected {
            // Reconnected
            lastConnectedTime = Date()
            recordEvent(.connected, details: "Internet connection restored")
        }

        // Check for latency spikes (only when connected)
        if isConnected {
            if let newLatency = newStatus.internet.latencyToExternal,
               let oldLatency = oldStatus.internet.latencyToExternal {
                // Spike: latency increased by >100ms or exceeded threshold
                if newLatency > latencySpikeThreshold && oldLatency < latencySpikeThreshold {
                    recordEvent(.latencySpike, details: "Latency increased to \(Int(newLatency))ms", latency: newLatency)
                }
            }
        }

        // Check for interface changes
        if oldStatus.connectionType != newStatus.connectionType {
            let oldType = oldStatus.connectionType?.displayName ?? "Unknown"
            let newType = newStatus.connectionType?.displayName ?? "Unknown"
            recordEvent(.interfaceChanged, details: "\(oldType) → \(newType)", connectionType: newType)
        }

        // Check for VPN state changes
        let wasVPN = oldStatus.vpn.isActive
        let isVPN = newStatus.vpn.isActive

        if !wasVPN && isVPN {
            recordEvent(.vpnConnected, details: "VPN tunnel established")
        } else if wasVPN && !isVPN {
            recordEvent(.vpnDisconnected, details: "VPN tunnel closed")
        }

        // Check for quality changes
        let oldHealth = oldStatus.overallHealth
        let newHealth = newStatus.overallHealth

        // Compare health using helper function
        if healthDegraded(from: oldHealth, to: newHealth) {
            recordEvent(.qualityDegraded, details: "\(oldHealth.color) → \(newHealth.color)")
        } else if healthImproved(from: oldHealth, to: newHealth) {
            recordEvent(.qualityImproved, details: "\(oldHealth.color) → \(newHealth.color)")
        }
    }

    /// Helper: Check if health degraded significantly
    private func healthDegraded(from old: NetworkHealth, to new: NetworkHealth) -> Bool {
        let order: [NetworkHealth] = [.excellent, .fair, .poor, .unknown]
        guard let oldIndex = order.firstIndex(of: old),
              let newIndex = order.firstIndex(of: new) else { return false }
        return newIndex > oldIndex + 1  // Degraded by more than 1 step
    }

    /// Helper: Check if health improved significantly
    private func healthImproved(from old: NetworkHealth, to new: NetworkHealth) -> Bool {
        let order: [NetworkHealth] = [.excellent, .fair, .poor, .unknown]
        guard let oldIndex = order.firstIndex(of: old),
              let newIndex = order.firstIndex(of: new) else { return false }
        return newIndex < oldIndex - 1  // Improved by more than 1 step
    }

    // MARK: - Event Recording

    private func recordEvent(_ type: StabilityEventType, details: String, latency: Double? = nil, connectionType: String? = nil) {
        let now = Date()

        // FIXED: Skip events during startup (first 5 seconds)
        guard now.timeIntervalSince(appStartTime) > startupDelay else {
            debugLog("📊 Stability event skipped (startup): \(type.rawValue)")
            return
        }

        // FIXED: Debounce - don't fire more than 1 event per 5 seconds
        if let lastTime = lastEventTime, now.timeIntervalSince(lastTime) < minEventInterval {
            debugLog("📊 Stability event debounced: \(type.rawValue)")
            return
        }
        lastEventTime = now

        let event = StabilityEvent(type: type, details: details, latency: latency, connectionType: connectionType)
        events.insert(event, at: 0)

        // Trim to max size
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }

        // Save to persistence
        saveEvents()

        // Update metrics after significant events
        if type == .disconnected || type == .connected || type == .latencySpike {
            updateMetrics()
        }

        debugLog("📊 Stability event: \(type.rawValue) - \(details)")
    }

    // MARK: - Metrics Calculation

    private func updateMetrics() {
        let windowStart = Date().addingTimeInterval(-Double(trackingWindowHours) * 3600)
        let recentEvents = events.filter { $0.timestamp >= windowStart }

        // Calculate uptime percentage
        var connectedTime: TimeInterval = 0
        var lastConnect: Date?
        var lastDisconnect: Date?

        // Process events in chronological order
        for event in recentEvents.reversed() {
            switch event.type {
            case .connected:
                lastConnect = event.timestamp
            case .disconnected:
                if let connect = lastConnect {
                    connectedTime += event.timestamp.timeIntervalSince(connect)
                    lastConnect = nil
                }
                lastDisconnect = event.timestamp
            default:
                break
            }
        }

        // Add time for current connection if still connected
        if let connect = lastConnect, lastKnownStatus?.internet.isReachable == true {
            connectedTime += Date().timeIntervalSince(connect)
        }

        let windowDuration = Date().timeIntervalSince(windowStart)
        let uptimePercentage = windowDuration > 0 ? (connectedTime / windowDuration) * 100 : 100

        // Calculate average latency
        let latencyEvents = recentEvents.compactMap { $0.latency }
        let avgLatency: Double? = latencyEvents.isEmpty ? lastKnownStatus?.internet.latencyToExternal : latencyEvents.reduce(0, +) / Double(latencyEvents.count)

        // Count events
        let disconnectCount = recentEvents.filter { $0.type == .disconnected }.count
        let spikeCount = recentEvents.filter { $0.type == .latencySpike }.count

        // Determine stable since (last disconnect or start of tracking)
        let stableSince: Date? = lastDisconnect.map { Date() > $0 ? $0 : nil } ?? trackingStartTime

        // Determine quality
        let quality: ConnectionStabilityMetrics.ConnectionQualityLevel
        if uptimePercentage >= 99 && (avgLatency ?? 0) < 50 && spikeCount == 0 {
            quality = .excellent
        } else if uptimePercentage >= 95 && (avgLatency ?? 0) < 100 && spikeCount < 3 {
            quality = .good
        } else if uptimePercentage >= 90 && (avgLatency ?? 0) < 200 {
            quality = .fair
        } else {
            quality = .poor
        }

        currentMetrics = ConnectionStabilityMetrics(
            uptimePercentage: uptimePercentage,
            averageLatency: avgLatency,
            disconnectCount: disconnectCount,
            latencySpikeCount: spikeCount,
            lastDisconnect: lastDisconnect,
            stableSince: stableSince,
            connectionQuality: quality
        )
    }

    // MARK: - Public API

    /// Get events within a time window
    func getEvents(since: Date) -> [StabilityEvent] {
        events.filter { $0.timestamp >= since }
    }

    /// Get events of specific type
    func getEvents(ofType type: StabilityEventType) -> [StabilityEvent] {
        events.filter { $0.type == type }
    }

    /// Get summary text for dashboard
    var stabilitySummary: String {
        guard let metrics = currentMetrics else {
            return "Monitoring..."
        }

        if metrics.disconnectCount == 0 && metrics.latencySpikeCount == 0 {
            return "\(metrics.connectionQuality.rawValue) - No issues in last \(trackingWindowHours)h"
        }

        var issues: [String] = []
        if metrics.disconnectCount > 0 {
            issues.append("\(metrics.disconnectCount) disconnect\(metrics.disconnectCount > 1 ? "s" : "")")
        }
        if metrics.latencySpikeCount > 0 {
            issues.append("\(metrics.latencySpikeCount) latency spike\(metrics.latencySpikeCount > 1 ? "s" : "")")
        }

        return "\(metrics.connectionQuality.rawValue) - \(issues.joined(separator: ", "))"
    }

    /// Clear all events
    func clearHistory() {
        events = []
        totalConnectedTime = 0
        trackingStartTime = Date()
        saveEvents()
        updateMetrics()
    }

    // MARK: - Dashboard Convenience Properties

    /// Disconnects in last 24 hours
    var dropsLast24h: Int {
        currentMetrics?.disconnectCount ?? 0
    }

    /// Average latency from metrics
    var averageLatency: Double? {
        currentMetrics?.averageLatency
    }

    /// Formatted uptime streak string
    var uptimeStreakFormatted: String {
        guard let stableSince = currentMetrics?.stableSince else {
            return "N/A"
        }

        let streak = Date().timeIntervalSince(stableSince)
        let hours = Int(streak) / 3600
        let minutes = (Int(streak) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Get recent events for timeline visualization
    func recentTimeline(hours: Int = 24) -> [StabilityEvent] {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        return events
            .filter { $0.timestamp > cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Create timeline buckets for visualization (true = connected, false = had issues)
    func timelineBuckets(hours: Int = 24) -> [Bool] {
        var buckets = Array(repeating: true, count: hours)
        let now = Date()
        let disconnects = events.filter { $0.type == .disconnected }

        for event in disconnects {
            let hoursAgo = now.timeIntervalSince(event.timestamp) / 3600
            let bucketIndex = hours - 1 - Int(hoursAgo)
            if bucketIndex >= 0 && bucketIndex < hours {
                buckets[bucketIndex] = false
            }
        }

        return buckets
    }

    // MARK: - Persistence

    private func loadEvents() {
        if let data = userDefaults.data(forKey: eventsKey),
           let decoded = try? JSONDecoder().decode([StabilityEvent].self, from: data) {
            events = decoded
        }
    }

    private func saveEvents() {
        // FIXED: Use safe save with size limit to prevent UserDefaults crash
        // Save in background to avoid blocking UI
        let eventsToSave = events
        Task.detached {
            // Use safe save with automatic trimming if data exceeds limits
            UserDefaults.standard.setSafe(eventsToSave, forKey: "stabilityEvents", maxItems: 100)
        }
    }
}
