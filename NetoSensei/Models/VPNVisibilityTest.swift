//
//  VPNVisibilityTest.swift
//  NetoSensei
//
//  VPN Detection Risk, Security Leaks, and IP Reputation Analysis
//  Educational tool - shows WHY sites block VPNs, not how to evade
//

import Foundation

// MARK: - IP Classification

enum IPType: String, Codable {
    case residential = "Residential ISP"
    case datacenter = "Data Center"
    case mobile = "Mobile Carrier"
    case vpn = "Known VPN Provider"
    case proxy = "Proxy Service"
    case hosting = "Hosting Company"
    case unknown = "Unknown"

    var detectionRisk: DetectionRisk {
        switch self {
        case .residential, .mobile:
            return .low
        case .hosting:
            return .medium
        case .datacenter, .vpn, .proxy:
            return .high
        case .unknown:
            return .medium
        }
    }
}

enum DetectionRisk: String, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var explanation: String {
        switch self {
        case .low:
            return "Appears as regular consumer connection"
        case .medium:
            return "Some detection indicators present"
        case .high:
            return "Multiple VPN/proxy indicators detected"
        }
    }
}

// MARK: - VPN Detection Signals

struct VPNDetectionSignals: Codable, Equatable {
    // A. IP Intelligence
    let asnType: String  // "Residential", "Data Center", "Mobile"
    let asnOrganization: String
    let ipType: IPType
    let isKnownVPNProvider: Bool
    let isHostingCompany: Bool

    // B. Geographic Mismatch
    let ipCountry: String
    let ipCity: String?
    let mismatchProbability: Double  // 0.0-1.0

    // C. IP Sharing & Age
    let sharedIPLikelihood: String  // "Low (<10 users)", "High (1000+ users)"
    let ipAgeDays: Int?  // Newer IPs are more suspicious

    var overallDetectionRisk: DetectionRisk {
        var riskScore = 0

        // Datacenter/VPN ASN = high risk
        if ipType == .datacenter || ipType == .vpn || ipType == .proxy {
            riskScore += 3
        }

        // Known VPN provider = high risk
        if isKnownVPNProvider {
            riskScore += 2
        }

        // High IP sharing = medium risk
        if sharedIPLikelihood.contains("High") || sharedIPLikelihood.contains("1000+") {
            riskScore += 1
        }

        // Recent IP = medium risk
        if let age = ipAgeDays, age < 30 {
            riskScore += 1
        }

        if riskScore >= 4 { return .high }
        if riskScore >= 2 { return .medium }
        return .low
    }

    var userFriendlySummary: String {
        """
        Detection Risk: \(overallDetectionRisk.rawValue)
        \(overallDetectionRisk.explanation)

        IP Type: \(ipType.rawValue)
        ASN: \(asnOrganization)
        Sharing: \(sharedIPLikelihood)

        Why sites might detect this:
        \(detectionReasons.joined(separator: "\n"))
        """
    }

    var detectionReasons: [String] {
        var reasons: [String] = []

        if ipType == .datacenter || ipType == .hosting {
            reasons.append("• IP belongs to data center, not residential ISP")
        }

        if isKnownVPNProvider {
            reasons.append("• ASN is a known VPN provider")
        }

        if sharedIPLikelihood.contains("High") {
            reasons.append("• IP shared by many users (suspicious)")
        }

        if let age = ipAgeDays, age < 30 {
            reasons.append("• Recently allocated IP (suspicious)")
        }

        if reasons.isEmpty {
            reasons.append("✓ No obvious detection indicators")
        }

        return reasons
    }
}

// MARK: - VPN Security Leaks

struct VPNSecurityLeaks: Codable, Equatable {
    // DNS Leak Detection
    let dnsServerIP: String
    let dnsServerCountry: String?
    let dnsLeakDetected: Bool  // DNS outside VPN tunnel

    // WebRTC Leak Detection
    // NOTE: WebRTC is a BROWSER technology. Native iOS apps don't have WebRTC
    // unless you specifically import a WebRTC framework (like for video calls).
    // These fields are always false for native apps since there's no WebRTC to leak.
    // We keep these fields for API compatibility but they're effectively N/A.
    let webRTCLocalIPExposed: Bool  // N/A for native iOS apps
    let webRTCRealIPExposed: Bool   // N/A for native iOS apps
    let exposedIPs: [String]        // N/A for native iOS apps

    // IPv6 Leak Detection
    let ipv6Tunneled: Bool
    let ipv6LeakDetected: Bool

    // MTU Issues
    let mtuFragmentationDetected: Bool
    let optimalMTU: Int?

    var hasLeaks: Bool {
        dnsLeakDetected || webRTCRealIPExposed || ipv6LeakDetected
    }

    var securityRating: String {
        if !hasLeaks && ipv6Tunneled && !mtuFragmentationDetected {
            return "Excellent"
        }
        if !hasLeaks && !mtuFragmentationDetected {
            return "Good"
        }
        if hasLeaks {
            return "Poor - Leaks Detected"
        }
        return "Fair"
    }

    var userFriendlySummary: String {
        var status: [String] = []

        // DNS
        if dnsLeakDetected {
            status.append("❌ DNS leak: Queries go outside VPN tunnel")
        } else if dnsServerIP.isEmpty || dnsServerIP == "Unknown" {
            status.append("⚠️ DNS: Could not determine DNS server")
        } else {
            status.append("✅ No DNS leak")
        }

        // WebRTC - Always N/A for native iOS apps
        status.append("➖ WebRTC: N/A (native app — no WebRTC)")

        // IPv6
        if ipv6LeakDetected {
            status.append("⚠️ IPv6 leak detected")
        } else if ipv6Tunneled {
            status.append("✅ IPv6 properly tunneled")
        } else {
            status.append("➖ IPv6: Not active (no leak possible)")
        }

        // MTU
        if mtuFragmentationDetected {
            status.append("⚠️ MTU mismatch (video instability possible)")
        } else {
            status.append("✅ No MTU issues")
        }

        return """
        VPN Security: \(securityRating)

        \(status.joined(separator: "\n"))
        """
    }
}

// MARK: - IP Reputation

struct IPReputation: Codable, Equatable {
    // Abuse & Blacklist Status
    let abuseRiskScore: Double  // 0.0-1.0 (0 = clean, 1 = high abuse)
    let botActivityProbability: Double  // 0.0-1.0
    let knownAbuseFlags: [String]  // "Spam", "Scraping", "Botnet", etc.

    // Trust Indicators
    let ipTrustScore: Double  // 0.0-1.0 (0 = untrusted, 1 = trusted)
    let reverseHostname: String?
    let isResidentialIP: Bool

    var trustRating: String {
        if ipTrustScore >= 0.7 { return "High" }
        if ipTrustScore >= 0.4 { return "Medium" }
        return "Low"
    }

    var userFriendlySummary: String {
        var status: [String] = []

        // Trust score
        status.append("Trust Score: \(trustRating)")

        // Abuse risk
        if abuseRiskScore > 0.5 {
            status.append("⚠️ High abuse risk score")
        } else if abuseRiskScore > 0.2 {
            status.append("⚠️ Moderate abuse risk")
        } else {
            status.append("✅ No known abuse flags")
        }

        // Bot probability
        if botActivityProbability > 0.5 {
            status.append("⚠️ High bot activity probability")
        }

        // Abuse flags
        if !knownAbuseFlags.isEmpty {
            status.append("⚠️ Flagged for: \(knownAbuseFlags.joined(separator: ", "))")
        }

        // IP type
        if isResidentialIP {
            status.append("✅ Residential IP (trusted)")
        } else {
            status.append("⚠️ Non-residential IP (lower trust)")
        }

        return status.joined(separator: "\n")
    }
}

// MARK: - Streaming & Service Friendliness

struct ServiceFriendliness: Codable, Equatable {
    // AI Service Detection Risk (Claude, ChatGPT, etc.)
    let aiServiceDetectionRisk: DetectionRisk
    let aiServiceRiskReasons: [String]

    // Streaming Service Compatibility
    let streamingCDNLatency: Double?  // ms to major CDNs
    let packetStability: String  // "Stable", "Unstable"
    let mtuHealth: String  // "Optimal", "Fragmentation Detected"

    // China-Specific Routing (if applicable)
    let chinaRoutingQuality: String?  // "Good", "GFW interference detected"
    let overseasRTTInflation: Double?  // Multiplier vs expected

    var streamingRating: String {
        guard let latency = streamingCDNLatency else { return "Unknown" }

        if latency < 50 && packetStability == "Stable" && mtuHealth == "Optimal" {
            return "Excellent"
        }
        if latency < 100 && packetStability == "Stable" {
            return "Good"
        }
        if latency < 200 {
            return "Fair"
        }
        return "Poor"
    }

    var userFriendlySummary: String {
        var status: [String] = []

        // AI service risk
        status.append("AI Service Detection: \(aiServiceDetectionRisk.rawValue)")
        for reason in aiServiceRiskReasons {
            status.append("  \(reason)")
        }

        // Streaming
        if let cdn = streamingCDNLatency {
            status.append("\nStreaming: \(streamingRating)")
            status.append("  CDN latency: \(Int(cdn))ms")
            status.append("  Packet stability: \(packetStability)")
            status.append("  MTU health: \(mtuHealth)")
        }

        // China routing
        if let quality = chinaRoutingQuality {
            status.append("\nChina Routing: \(quality)")
        }

        return status.joined(separator: "\n")
    }
}

// MARK: - Complete VPN Visibility Test Result

struct VPNVisibilityTestResult: Codable, Equatable {
    let timestamp: Date

    // Core Analysis
    let detectionSignals: VPNDetectionSignals
    let securityLeaks: VPNSecurityLeaks
    let reputation: IPReputation
    let serviceFriendliness: ServiceFriendliness

    // Overall Assessment
    var overallAssessment: String {
        let detectionRisk = detectionSignals.overallDetectionRisk
        let hasLeaks = securityLeaks.hasLeaks
        let trustRating = reputation.trustRating

        if detectionRisk == .high || hasLeaks {
            return "⚠️ High Detection Risk + Security Issues"
        }

        if detectionRisk == .medium && trustRating == "Low" {
            return "⚠️ Moderate Detection Risk"
        }

        if detectionRisk == .low && !hasLeaks && trustRating == "High" {
            return "✅ Low Detection Risk - Clean IP"
        }

        return "ℹ️ Mixed Signals"
    }

    var comparisonSummary: String {
        """
        Overall: \(overallAssessment)

        Detection Risk: \(detectionSignals.overallDetectionRisk.rawValue)
        Security: \(securityLeaks.securityRating)
        Reputation: \(reputation.trustRating)
        AI Service Risk: \(serviceFriendliness.aiServiceDetectionRisk.rawValue)

        Key Issues:
        \(keyIssues.joined(separator: "\n"))
        """
    }

    var keyIssues: [String] {
        var issues: [String] = []

        // Detection
        if detectionSignals.ipType == .datacenter || detectionSignals.ipType == .vpn {
            issues.append("• IP type: \(detectionSignals.ipType.rawValue)")
        }

        // Security
        if securityLeaks.dnsLeakDetected {
            issues.append("• DNS leak detected")
        }
        if securityLeaks.webRTCRealIPExposed {
            issues.append("• WebRTC leak detected")
        }

        // Reputation
        if reputation.abuseRiskScore > 0.3 {
            issues.append("• Elevated abuse risk")
        }

        if issues.isEmpty {
            issues.append("✓ No major issues detected")
        }

        return issues
    }

    // Why Claude/ChatGPT might block this
    var likelyBlockReason: String? {
        if detectionSignals.ipType == .datacenter || detectionSignals.ipType == .vpn {
            return "Datacenter/VPN IP - AI services block these by default"
        }

        if detectionSignals.isKnownVPNProvider {
            return "Known VPN provider - appears in detection databases"
        }

        if detectionSignals.sharedIPLikelihood.contains("High") {
            return "High IP sharing (1000+ users) - abuse prevention systems flag this"
        }

        if reputation.abuseRiskScore > 0.5 {
            return "IP flagged for abuse/bot activity"
        }

        return nil
    }
}
