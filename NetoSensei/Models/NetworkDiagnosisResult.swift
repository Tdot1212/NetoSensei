//
//  NetworkDiagnosisResult.swift
//  NetoSensei
//
//  Intelligent Network Diagnosis - Symptom-based problem detection
//

import Foundation

// MARK: - Diagnosis Result

struct NetworkDiagnosisResult: Sendable, Codable {
    let timestamp: Date
    let primaryProblem: NetworkProblemType
    let secondaryProblems: [NetworkProblemType]
    let confidence: DiagnosisConfidence
    let explanation: String
    let recommendations: [ActionableRecommendation]
    let technicalDetails: TechnicalDetails

    // NEW: Network Safety Assessment
    let safetyScore: NetworkSafetyScore
    let safetyReasons: [String]

    var userFriendlySummary: String {
        switch primaryProblem {
        case .wifiRouterIssue:
            return "🔴 Your WiFi or router is the bottleneck"
        case .vpnServerSlow:
            return "🔴 Your VPN server is overloaded or far away"
        case .vpnInstability:
            return "⚠️ Your VPN connection is unstable"
        case .ispThrottling:
            return "⚠️ Your ISP may be throttling international traffic"
        case .ispLocalCongestion:
            return "🔴 Your ISP has local congestion"
        case .normalPerformance:
            return "✅ Everything looks good"
        case .insufficientData:
            return "⚠️ Not enough data to diagnose"
        }
    }

    var safetySummary: String {
        switch safetyScore {
        case .safe:
            return "🟢 Your network is SAFE"
        case .caution:
            return "🟡 Your network needs attention"
        case .risky:
            return "🔴 Your network looks RISKY"
        case .suspicious:
            return "⚠️ Your network looks SUSPICIOUS"
        }
    }
}

// MARK: - Problem Types

enum NetworkProblemType: String, Sendable, Codable {
    case wifiRouterIssue = "WiFi/Router Problem"
    case vpnServerSlow = "VPN Server Slow"
    case vpnInstability = "VPN Tunnel Unstable"
    case ispThrottling = "ISP International Throttling"
    case ispLocalCongestion = "ISP Local Congestion"
    case normalPerformance = "Normal Performance"
    case insufficientData = "Insufficient Data"
}

// MARK: - Network Safety Score

enum NetworkSafetyScore: String, Sendable, Codable {
    case safe = "Safe"
    case caution = "Caution"
    case risky = "Risky"
    case suspicious = "Suspicious"

    var color: String {
        switch self {
        case .safe: return "green"
        case .caution: return "yellow"
        case .risky: return "orange"
        case .suspicious: return "red"
        }
    }
}

// MARK: - Confidence Level

enum DiagnosisConfidence: String, Sendable, Codable {
    case high = "High"       // 80%+
    case medium = "Medium"   // 50-80%
    case low = "Low"         // <50%

    var percentage: Int {
        switch self {
        case .high: return 85
        case .medium: return 65
        case .low: return 35
        }
    }
}

// MARK: - Actionable Recommendation

struct ActionableRecommendation: Sendable, Codable, Identifiable {
    let id: UUID
    let priority: RecommendationPriority
    let action: String
    let reasoning: String
    let expectedImprovement: String

    init(priority: RecommendationPriority, action: String, reasoning: String, expectedImprovement: String) {
        self.id = UUID()
        self.priority = priority
        self.action = action
        self.reasoning = reasoning
        self.expectedImprovement = expectedImprovement
    }
}

enum RecommendationPriority: String, Sendable, Codable {
    case critical = "Do This Now"
    case high = "Recommended"
    case medium = "Consider"
    case low = "Optional"
}

// MARK: - Technical Details

struct TechnicalDetails: Sendable, Codable {
    let vpnActive: Bool
    let publicIP: String
    let localLatency: Double
    let foreignLatency: Double?
    let packetLoss: Double
    let jitter: Int
    let downloadSpeed: Double
    let uploadSpeed: Double?

    // Symptom indicators
    let hasHighLocalLatency: Bool
    let hasHighPacketLoss: Bool
    let hasHighJitter: Bool
    let hasSlowSpeed: Bool
    let hasLatencyJump: Bool

    var symptomsDescription: String {
        var symptoms: [String] = []

        if hasHighLocalLatency {
            symptoms.append("High local latency (\(Int(localLatency))ms)")
        }
        if hasHighPacketLoss {
            symptoms.append("High packet loss (\(String(format: "%.1f", packetLoss))%)")
        }
        if hasHighJitter {
            symptoms.append("High jitter (\(jitter)ms)")
        }
        if hasSlowSpeed {
            symptoms.append("Slow download speed (\(String(format: "%.1f", downloadSpeed)) Mbps)")
        }
        if hasLatencyJump {
            if let foreign = foreignLatency {
                symptoms.append("Large latency jump (\(Int(localLatency))ms → \(Int(foreign))ms)")
            }
        }

        return symptoms.isEmpty ? "No significant symptoms detected" : symptoms.joined(separator: "\n")
    }
}
