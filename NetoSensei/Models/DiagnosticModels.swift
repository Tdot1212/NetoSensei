//
//  DiagnosticModels.swift
//  NetoSensei
//
//  Data models for Advanced Diagnostics Engine
//

import Foundation

// MARK: - Error Handling

enum DiagnosticError: Error, Sendable {
    case timeout
    case noResponse
    case unreachable
    case invalidData
    case permissionDenied
    case unknown(String)
}

// MARK: - 1.1 DNS Hijack Result

enum DNSRegion: String, Sendable, Codable {
    case chinaNative = "China Native"
    case overseas = "Overseas"
}

struct DNSHijackResult: Sendable, Codable {
    let domain: String
    let expectedIPs: [String]
    let resolvedIPs: [String]
    let hijacked: Bool
    let confidence: Double
    let region: DNSRegion
    var note: String?  // ADDED: VPN-aware note for context

    var userFriendlyDescription: String {
        // FIXED: Show VPN-aware note when applicable
        if let note = note, !note.isEmpty {
            return "ℹ️ \(domain): \(note)"
        }

        if hijacked {
            if region == .chinaNative {
                return "⚠️ China-native domain \(domain) shows issues"
            } else {
                return "ℹ️ Overseas domain \(domain) intercepted (normal for region)"
            }
        } else {
            return "✓ \(domain) resolves correctly"
        }
    }
}

// MARK: - 1.3 VPN Leak Result

struct VPNLeakResult: Sendable, Codable {
    let realIP: String?
    let vpnIP: String
    let leaked: Bool
    let leakType: VPNLeakType
    let timestamp: Date

    var userFriendlyDescription: String {
        // Add iOS visibility disclaimer
        if vpnIP == "N/A - No VPN Active" {
            return "ℹ️ No VPN detected by iOS. Note: VPN may be active at system or router level; iOS visibility is limited."
        } else if leaked {
            return "⚠️ VPN LEAK: Your real IP (\(realIP ?? "unknown")) is exposed!"
        } else {
            return "✓ No VPN leak detected. Your IP is protected. (Note: iOS-level detection only)"
        }
    }
}

enum VPNLeakType: String, Sendable, Codable {
    case ipLeak = "IP Leak"
    case dnsLeak = "DNS Leak"
    case webRTCLeak = "WebRTC Leak"
    case noLeak = "No Leak"
}

// MARK: - 1.4 Routing Hop

struct RoutingHop: Sendable, Codable, Identifiable {
    let id: UUID
    let hop: Int
    let ip: String
    let hostname: String?
    let latency: Int?  // ms
    let isTimeout: Bool

    var displayLatency: String {
        if isTimeout {
            return "* * *"
        } else if let latency = latency {
            return "\(latency)ms"
        } else {
            return "---"
        }
    }

    var userFriendlyDescription: String {
        let hostDisplay = hostname ?? ip
        return "Hop \(hop): \(hostDisplay) - \(displayLatency)"
    }

    init(hop: Int, ip: String, hostname: String? = nil, latency: Int? = nil, isTimeout: Bool = false) {
        self.id = UUID()
        self.hop = hop
        self.ip = ip
        self.hostname = hostname
        self.latency = latency
        self.isTimeout = isTimeout
    }
}

// MARK: - Routing Interpretation

struct RoutingInterpretation: Sendable, Codable {
    let hops: [RoutingHop]
    let diagnosis: String
    let problemType: RoutingProblemType
    let userFriendlyExplanation: String
    let recommendations: [String]
}

enum RoutingProblemType: String, Sendable, Codable {
    case routerCongestion = "Router Congestion"
    case ispCongestion = "ISP Congestion"
    case greatFirewall = "Great Firewall Blocking"
    case vpnExit = "VPN Exit Node Slow"
    case cdnFar = "CDN Too Far"
    case normal = "Normal Routing"
}

// MARK: - Performance Metrics

struct PerformanceMetrics: Sendable, Codable {
    let packetLoss: Double  // %
    let jitter: Int  // ms
    let throughput: Double  // Mbps
    let timestamp: Date

    var qualityRating: String {
        if packetLoss < 1 && jitter < 20 && throughput > 25 {
            return "Excellent"
        } else if packetLoss < 3 && jitter < 50 && throughput > 10 {
            return "Good"
        } else if packetLoss < 5 && jitter < 100 {
            return "Fair"
        } else {
            return "Poor"
        }
    }

    var userFriendlyDescription: String {
        let speedText: String
        if throughput < 0 {
            speedText = "Test blocked/interrupted"
        } else if throughput < 0.1 {
            speedText = "Connection severely throttled (< 0.1 Mbps)"
        } else {
            speedText = String(format: "%.1f Mbps", throughput)
        }
        return "Quality: \(qualityRating) - Loss: \(String(format: "%.1f", packetLoss))%, Jitter: \(jitter)ms, Speed: \(speedText)"
    }
}

// MARK: - Advanced Diagnostic Summary

struct AdvancedDiagnosticSummary: Sendable, Codable {
    let timestamp: Date
    let arpResult: ARPResult?  // Kept for backward compatibility, always nil
    let dnsHijackResults: [DNSHijackResult]
    let vpnLeakResult: VPNLeakResult?
    let routingInterpretation: RoutingInterpretation?
    let performanceMetrics: PerformanceMetrics?
    let vpnRegionScores: [VPNRegionScore]  // Kept for backward compatibility, always empty
    let wifiChannels: [WifiChannelInfo]  // Kept for backward compatibility, always empty
    let lanDevices: [LANDevice]  // Kept for backward compatibility, always empty

    // NEW: Intelligent diagnosis
    let networkDiagnosis: NetworkDiagnosisResult?

    var overallThreatLevel: ThreatLevel {
        var threatScore = 0

        // FIXED: Use region-aware DNS logic (must match summaryText logic)
        // Only count DNS issues that are actual threats, not normal ISP behavior
        switch dnsBehaviorType {
        case .dnsConfigurationIssue:
            threatScore += 25  // User-caused, not critical
        case .abnormalDNSBehavior:
            threatScore += 50  // Actual threat - rare, abnormal
        case .normalChinaISP, .allNormal:
            // Don't add threat score - these are expected behaviors
            break
        }

        // VPN leak is always a real security threat
        if vpnLeakResult?.leaked == true { threatScore += 50 }

        // Return appropriate threat level
        if threatScore == 0 { return .secure }
        else if threatScore >= 75 { return .critical }
        else if threatScore >= 50 { return .high }
        else if threatScore >= 25 { return .medium }
        else { return .low }
    }

    // MARK: - Region-Aware DNS Interpretation
    enum DNSBehaviorType {
        case normalChinaISP
        case dnsConfigurationIssue
        case abnormalDNSBehavior
        case allNormal
    }

    var dnsBehaviorType: DNSBehaviorType {
        let chinaNativeResults = dnsHijackResults.filter { $0.region == .chinaNative }
        let overseasResults = dnsHijackResults.filter { $0.region == .overseas }

        let chinaNativeHijacked = chinaNativeResults.contains { $0.hijacked }
        let overseasHijacked = overseasResults.contains { $0.hijacked }

        // 1️⃣ Normal China ISP Behavior (MOST COMMON)
        // China domains OK, overseas domains intercepted
        if !chinaNativeHijacked && overseasHijacked {
            return .normalChinaISP
        }

        // 2️⃣ DNS Configuration Issue (USER-CAUSED)
        // Both domestic and overseas domains have issues
        if chinaNativeHijacked && overseasHijacked {
            return .dnsConfigurationIssue
        }

        // 3️⃣ Abnormal DNS Behavior (RARE)
        // Only China-native domains are hijacked (unusual!)
        if chinaNativeHijacked && !overseasHijacked {
            return .abnormalDNSBehavior
        }

        // All normal
        return .allNormal
    }

    var dnsBehaviorDescription: String {
        switch dnsBehaviorType {
        case .normalChinaISP:
            return "ISP DNS Interception (Regional Behavior)\n\nYour DNS behaves normally for mainland China. Overseas domains may be redirected by the ISP, which can affect Google, YouTube, and streaming services.\n\n🇨🇳 China-native: OK\n🌍 Overseas: Intercepted (expected)"

        case .dnsConfigurationIssue:
            return "DNS Configuration Issue Detected\n\nBoth domestic and overseas domains show resolution issues. This may be caused by custom DNS settings, proxies, or router configuration.\n\n⚠️ China-native: Issues\n⚠️ Overseas: Issues"

        case .abnormalDNSBehavior:
            return "Abnormal DNS Manipulation Detected\n\nChina-native domains are being redirected, which is unusual behavior. This could indicate router misconfiguration or network tampering.\n\n⚠️ China-native: Redirected (abnormal)\n✓ Overseas: Normal"

        case .allNormal:
            return "DNS Resolution Normal\n\nAll tested domains resolve correctly without interception.\n\n✓ China-native: OK\n✓ Overseas: OK"
        }
    }

    var summaryText: String {
        // Prioritize intelligent diagnosis if available
        if let diagnosis = networkDiagnosis {
            return diagnosis.userFriendlySummary
        }

        // Fallback to region-aware DNS interpretation
        var issues: [String] = []

        // Use region-aware DNS logic instead of generic "hijacking detected"
        switch dnsBehaviorType {
        case .normalChinaISP:
            // Don't report as "issue" - it's expected behavior
            break
        case .dnsConfigurationIssue:
            issues.append("DNS configuration issue")
        case .abnormalDNSBehavior:
            issues.append("Abnormal DNS behavior")
        case .allNormal:
            break
        }

        if vpnLeakResult?.leaked == true {
            issues.append("VPN leak detected")
        }

        if issues.isEmpty {
            return "✓ No security threats detected"
        } else {
            return "⚠️ \(issues.joined(separator: ", "))"
        }
    }
}

// Legacy structs kept for Codable backward compatibility
struct ARPResult: Sendable, Codable {
    let gatewayIP: String
    let gatewayMAC: String
    let observedMAC: String
    let isSpoofed: Bool
    let confidence: Double
    let timestamp: Date
}

struct VPNRegionScore: Sendable, Codable, Identifiable {
    let id: UUID
    let region: String
    let serverIP: String
    let latency: Int
    let jitter: Int
    let packetLoss: Double
    let rating: String
    let timestamp: Date
}

struct WifiChannelInfo: Sendable, Codable, Identifiable {
    let id: UUID
    let channel: Int
    let frequency: Int
    let networkCount: Int
    let recommended: Bool
}

struct LANDevice: Sendable, Codable, Identifiable {
    let id: UUID
    let ip: String
    let mac: String
    let hostname: String?
    let vendor: String?
    let firstSeen: Date
    let lastSeen: Date
    let isSuspicious: Bool
}

// ThreatLevel is defined in SecurityScanResult.swift
