//
//  WiFiRoamingScanner.swift
//  NetoSensei
//
//  WiFi Roaming Instability Detection - 100% Real Detection
//  Detects: Mesh network node switching, unstable roaming, connection drops
//

import Foundation

actor WiFiRoamingScanner {
    static let shared = WiFiRoamingScanner()

    private init() {}

    private let gatewayHistoryKey = "gateway_roaming_history"
    private let roamingEventsKey = "roaming_events_count"

    // MARK: - WiFi Roaming Scan

    func performWiFiRoamingScan() async -> WiFiRoamingStatus {
        // 1. Detect sudden gateway changes
        let (currentGateway, previousGateway, gatewayChanged) = await detectGatewayChange()

        // 2. Track roaming frequency
        let roamingFrequency = trackRoamingFrequency(gatewayChanged: gatewayChanged)

        // 3. Detect unstable roaming pattern
        let unstableRoaming = detectUnstableRoaming(frequency: roamingFrequency)

        // 4. Measure connection quality after roaming
        let connectionQuality = await measureConnectionQualityAfterRoaming(
            gatewayChanged: gatewayChanged
        )

        // 5. Estimate if using mesh network
        let meshNetworkDetected = estimateMeshNetwork(
            roamingFrequency: roamingFrequency,
            gatewayChanges: gatewayChanged
        )

        // 6. Calculate roaming score
        let roamingScore = calculateRoamingScore(
            unstableRoaming: unstableRoaming,
            roamingFrequency: roamingFrequency,
            connectionQuality: connectionQuality
        )

        return WiFiRoamingStatus(
            currentGateway: currentGateway,
            previousGateway: previousGateway,
            gatewayChanged: gatewayChanged,
            roamingFrequency: roamingFrequency,
            unstableRoaming: unstableRoaming,
            meshNetworkDetected: meshNetworkDetected,
            connectionQualityAfterRoaming: connectionQuality,
            roamingScore: roamingScore
        )
    }

    // MARK: - Detect Gateway Change

    private func detectGatewayChange() async -> (current: String, previous: String?, changed: Bool) {
        let gatewayStatus = await GatewaySecurityScanner.shared.performGatewayScan()

        let currentGateway = gatewayStatus.currentGatewayIP
        let previousGateway = gatewayStatus.previousGatewayIP

        let changed = gatewayStatus.gatewayIPChanged

        return (currentGateway, previousGateway, changed)
    }

    // MARK: - Track Roaming Frequency

    private func trackRoamingFrequency(gatewayChanged: Bool) -> Int {
        var roamingEvents = UserDefaults.standard.integer(forKey: roamingEventsKey)

        if gatewayChanged {
            roamingEvents += 1
            UserDefaults.standard.set(roamingEvents, forKey: roamingEventsKey)

            // Also save to history with timestamp
            var history = getGatewayHistory()
            history.append(RoamingEvent(timestamp: Date()))

            // Keep only last 50 events
            if history.count > 50 {
                history = Array(history.suffix(50))
            }

            saveGatewayHistory(history)
        }

        return roamingEvents
    }

    private func getGatewayHistory() -> [RoamingEvent] {
        guard let data = UserDefaults.standard.data(forKey: gatewayHistoryKey),
              let history = try? JSONDecoder().decode([RoamingEvent].self, from: data) else {
            return []
        }
        return history
    }

    private func saveGatewayHistory(_ history: [RoamingEvent]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: gatewayHistoryKey)
        }
    }

    // MARK: - Detect Unstable Roaming

    private func detectUnstableRoaming(frequency: Int) -> Bool {
        // Check recent roaming events
        let history = getGatewayHistory()

        // If roamed more than 5 times in last hour, unstable
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let recentRoaming = history.filter { $0.timestamp > oneHourAgo }

        return recentRoaming.count > 5
    }

    // MARK: - Measure Connection Quality After Roaming

    private func measureConnectionQualityAfterRoaming(gatewayChanged: Bool) async -> RoamingQuality {
        guard gatewayChanged else { return .stable }

        // Measure latency and stability after roaming
        let gatewayStatus = await GatewaySecurityScanner.shared.performGatewayScan()

        let latency = gatewayStatus.gatewayLatency
        let stable = gatewayStatus.gatewayStable

        if !stable || latency > 100 {
            return .poor
        } else if latency > 50 {
            return .fair
        } else {
            return .good
        }
    }

    // MARK: - Estimate Mesh Network

    private func estimateMeshNetwork(roamingFrequency: Int, gatewayChanges: Bool) -> Bool {
        // If gateway changes frequently and roaming count is high, likely mesh/multiple APs
        let history = getGatewayHistory()

        // Mesh networks typically cause 3+ roaming events per day
        let oneDayAgo = Date().addingTimeInterval(-86400)
        let dailyRoaming = history.filter { $0.timestamp > oneDayAgo }

        return dailyRoaming.count >= 3
    }

    // MARK: - Calculate Roaming Score

    private func calculateRoamingScore(
        unstableRoaming: Bool,
        roamingFrequency: Int,
        connectionQuality: RoamingQuality
    ) -> Int {
        var score = 100

        if unstableRoaming {
            score -= 50  // Major issue
        }

        // Frequent roaming isn't bad if connection quality is good
        if roamingFrequency > 10 {
            switch connectionQuality {
            case .poor:
                score -= 40
            case .fair:
                score -= 20
            case .good, .stable:
                score -= 5  // Mesh network working well
            }
        }

        switch connectionQuality {
        case .poor:
            score -= 30
        case .fair:
            score -= 15
        case .good:
            break
        case .stable:
            break
        }

        return max(0, min(100, score))
    }

    // MARK: - Reset Roaming Stats

    func resetRoamingStats() {
        UserDefaults.standard.set(0, forKey: roamingEventsKey)
        UserDefaults.standard.removeObject(forKey: gatewayHistoryKey)
    }
}

// MARK: - Roaming Event

struct RoamingEvent: Codable {
    let timestamp: Date
}

// MARK: - Roaming Quality

enum RoamingQuality: String, Codable, Sendable {
    case stable = "Stable"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
}

// MARK: - WiFi Roaming Status

struct WiFiRoamingStatus: Codable, Sendable {
    let currentGateway: String
    let previousGateway: String?
    let gatewayChanged: Bool
    let roamingFrequency: Int
    let unstableRoaming: Bool
    let meshNetworkDetected: Bool
    let connectionQualityAfterRoaming: RoamingQuality
    let roamingScore: Int

    var statusText: String {
        if unstableRoaming {
            return "🔴 Unstable WiFi Roaming"
        } else if meshNetworkDetected && connectionQualityAfterRoaming == .poor {
            return "🟠 Mesh Network Issues"
        } else if meshNetworkDetected {
            return "🟢 Mesh Network Active"
        } else if gatewayChanged {
            return "🟡 Gateway Changed"
        } else {
            return "🟢 Connection Stable"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if unstableRoaming {
            recs.append("⚠️ WiFi roaming is unstable")
            recs.append("Device jumping between nodes too frequently")
            recs.append("May cause Netflix blur / video lag")
            recs.append("Roaming events: \(roamingFrequency) times")
        }

        if meshNetworkDetected {
            if connectionQualityAfterRoaming == .poor {
                recs.append("Mesh network detected with poor handoff")
                recs.append("Check mesh node placement")
                recs.append("Update mesh firmware")
                recs.append("Reduce overlap between nodes")
            } else {
                recs.append("Mesh network detected and working well")
                recs.append("Seamless roaming between nodes")
            }
        }

        if gatewayChanged && !meshNetworkDetected {
            recs.append("Gateway changed unexpectedly")
            recs.append("From: \(previousGateway ?? "Unknown")")
            recs.append("To: \(currentGateway)")
            recs.append("May indicate network reconfiguration")
        }

        if connectionQualityAfterRoaming == .poor {
            recs.append("Poor connection quality after roaming")
            recs.append("Try staying closer to one access point")
            recs.append("Disable auto-join on weaker networks")
        }

        return recs
    }
}
