//
//  VPNPrivacyScore.swift
//  NetoSensei
//
//  VPN Privacy Score - Comprehensive privacy assessment for VPN connections
//  Combines DNS leak detection, IP type analysis, and detectability assessment
//

import Foundation

// MARK: - VPN Privacy Score

struct VPNPrivacyScore: Identifiable {
    let id = UUID()
    let timestamp: Date
    let overallScore: Int  // 0-100
    let rating: PrivacyRating
    let checks: [PrivacyCheck]
    let recommendations: [String]
    let detailsSummary: String

    enum PrivacyRating: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case critical = "Critical"

        var description: String {
            switch self {
            case .excellent: return "Your VPN provides strong privacy protection"
            case .good: return "Your VPN provides good privacy with minor concerns"
            case .fair: return "Some privacy leaks or detectability issues"
            case .poor: return "Significant privacy concerns detected"
            case .critical: return "Major privacy issues - immediate action recommended"
            }
        }

        var icon: String {
            switch self {
            case .excellent: return "shield.checkmark.fill"
            case .good: return "shield.fill"
            case .fair: return "shield.slash"
            case .poor: return "exclamationmark.shield"
            case .critical: return "xmark.shield.fill"
            }
        }

        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "blue"
            case .fair: return "yellow"
            case .poor: return "orange"
            case .critical: return "red"
            }
        }
    }
}

// MARK: - Privacy Check

struct PrivacyCheck: Identifiable {
    let id = UUID()
    let name: String
    let category: CheckCategory
    let status: CheckStatus
    let details: String
    let impact: String  // How this affects privacy
    let points: Int     // Points contributed (positive) or deducted (negative)

    enum CheckCategory: String {
        case dnsLeak = "DNS Leak"
        case ipType = "IP Type"
        case detectability = "VPN Detectability"
        case encryption = "Encryption"
        case ipv6 = "IPv6 Handling"
        case webrtc = "WebRTC"
        case latency = "Latency/Performance"
    }

    enum CheckStatus: String {
        case pass = "Pass"
        case warning = "Warning"
        case fail = "Fail"
        case notApplicable = "N/A"

        var icon: String {
            switch self {
            case .pass: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .fail: return "xmark.circle.fill"
            case .notApplicable: return "minus.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .pass: return "green"
            case .warning: return "yellow"
            case .fail: return "red"
            case .notApplicable: return "gray"
            }
        }
    }
}

// MARK: - VPN Privacy Analyzer

struct VPNPrivacyAnalyzer {

    /// Analyze VPN privacy based on available data
    static func analyze(
        vpnStatus: VPNInfo,
        geoIP: GeoIPInfo?,
        networkStatus: NetworkStatus,
        dnsTestResult: DNSInfo?
    ) -> VPNPrivacyScore {
        var checks: [PrivacyCheck] = []
        var totalPoints = 100  // Start with perfect score, deduct for issues

        // 1. DNS Leak Check
        let dnsCheck = checkDNSLeak(
            vpnStatus: vpnStatus,
            dnsInfo: dnsTestResult,
            geoIP: geoIP
        )
        checks.append(dnsCheck)
        totalPoints += dnsCheck.points

        // 2. IP Type Check (Datacenter vs Residential)
        let ipTypeCheck = checkIPType(geoIP: geoIP)
        checks.append(ipTypeCheck)
        totalPoints += ipTypeCheck.points

        // 3. VPN Detectability Check
        let detectabilityCheck = checkDetectability(geoIP: geoIP, vpnStatus: vpnStatus)
        checks.append(detectabilityCheck)
        totalPoints += detectabilityCheck.points

        // 4. IPv6 Leak Check
        let ipv6Check = checkIPv6Leak(networkStatus: networkStatus, vpnStatus: vpnStatus)
        checks.append(ipv6Check)
        totalPoints += ipv6Check.points

        // 5. Latency Impact Check
        let latencyCheck = checkLatencyImpact(networkStatus: networkStatus)
        checks.append(latencyCheck)
        totalPoints += latencyCheck.points

        // 6. Known VPN Provider Check
        let providerCheck = checkKnownProvider(geoIP: geoIP)
        checks.append(providerCheck)
        totalPoints += providerCheck.points

        // Clamp score to 0-100
        let finalScore = max(0, min(100, totalPoints))

        // Determine rating
        let rating: VPNPrivacyScore.PrivacyRating
        if finalScore >= 90 { rating = .excellent }
        else if finalScore >= 75 { rating = .good }
        else if finalScore >= 55 { rating = .fair }
        else if finalScore >= 35 { rating = .poor }
        else { rating = .critical }

        // Generate recommendations
        let recommendations = generateRecommendations(checks: checks, score: finalScore)

        // Generate summary
        let passCount = checks.filter { $0.status == .pass }.count
        let warnCount = checks.filter { $0.status == .warning }.count
        let failCount = checks.filter { $0.status == .fail }.count
        let summary = "\(passCount) passed, \(warnCount) warnings, \(failCount) issues"

        return VPNPrivacyScore(
            timestamp: Date(),
            overallScore: finalScore,
            rating: rating,
            checks: checks,
            recommendations: recommendations,
            detailsSummary: summary
        )
    }

    // MARK: - Individual Checks

    private static func checkDNSLeak(vpnStatus: VPNInfo, dnsInfo: DNSInfo?, geoIP: GeoIPInfo?) -> PrivacyCheck {
        // Check if DNS is leaking outside VPN tunnel
        let hasLeak = vpnStatus.dnsLeakDetected

        if hasLeak {
            return PrivacyCheck(
                name: "DNS Leak Protection",
                category: .dnsLeak,
                status: .fail,
                details: "DNS queries are leaking outside VPN tunnel",
                impact: "Your ISP can see which websites you visit",
                points: -25
            )
        }

        // If we can check DNS resolver, verify it's not ISP
        if let resolverIP = dnsInfo?.resolverIP {
            // Known public DNS servers
            let publicDNS = ["1.1.1.1", "8.8.8.8", "9.9.9.9", "208.67.222.222"]
            if publicDNS.contains(resolverIP) {
                return PrivacyCheck(
                    name: "DNS Leak Protection",
                    category: .dnsLeak,
                    status: .pass,
                    details: "Using secure public DNS (\(resolverIP))",
                    impact: "DNS queries are protected",
                    points: 0
                )
            }
        }

        return PrivacyCheck(
            name: "DNS Leak Protection",
            category: .dnsLeak,
            status: .pass,
            details: "No DNS leaks detected",
            impact: "DNS queries are protected by VPN",
            points: 0
        )
    }

    private static func checkIPType(geoIP: GeoIPInfo?) -> PrivacyCheck {
        guard let geo = geoIP else {
            return PrivacyCheck(
                name: "IP Type Analysis",
                category: .ipType,
                status: .notApplicable,
                details: "Unable to determine IP type",
                impact: "Unknown",
                points: 0
            )
        }

        // Check ASN for datacenter indicators
        let asnLower = (geo.asn ?? "").lowercased()
        let orgLower = (geo.org ?? "").lowercased()

        let datacenterKeywords = [
            "amazon", "aws", "google", "microsoft", "azure", "digitalocean",
            "linode", "vultr", "ovh", "hetzner", "alibaba", "tencent",
            "datacenter", "hosting", "cloud", "server"
        ]

        let isDatacenter = datacenterKeywords.contains { keyword in
            asnLower.contains(keyword) || orgLower.contains(keyword)
        }

        if isDatacenter {
            return PrivacyCheck(
                name: "IP Type Analysis",
                category: .ipType,
                status: .warning,
                details: "Datacenter IP detected",
                impact: "60%+ of services can detect you're using a VPN/proxy",
                points: -15
            )
        }

        return PrivacyCheck(
            name: "IP Type Analysis",
            category: .ipType,
            status: .pass,
            details: "Residential or ISP IP",
            impact: "Lower chance of VPN detection by services",
            points: 0
        )
    }

    private static func checkDetectability(geoIP: GeoIPInfo?, vpnStatus: VPNInfo) -> PrivacyCheck {
        // Combined detectability assessment
        var detectabilityScore = 0
        var issues: [String] = []

        // Check for common VPN exit node patterns
        if let geo = geoIP {
            // Mismatch between timezone and IP location can indicate VPN
            // (We can't easily check timezone on iOS, so skip this)

            // Check for hosting provider ASN
            let orgLower = (geo.org ?? "").lowercased()
            if orgLower.contains("vpn") || orgLower.contains("proxy") {
                detectabilityScore += 30
                issues.append("ASN indicates VPN provider")
            }
        }

        // High latency to CDN can indicate VPN routing
        // This is checked separately in latency check

        if detectabilityScore >= 30 {
            return PrivacyCheck(
                name: "VPN Detectability",
                category: .detectability,
                status: .warning,
                details: issues.joined(separator: "; "),
                impact: "Some services may block or restrict access",
                points: -10
            )
        }

        return PrivacyCheck(
            name: "VPN Detectability",
            category: .detectability,
            status: .pass,
            details: "VPN connection is not easily detectable",
            impact: "Most services will not detect VPN usage",
            points: 0
        )
    }

    private static func checkIPv6Leak(networkStatus: NetworkStatus, vpnStatus: VPNInfo) -> PrivacyCheck {
        // Check if IPv6 is enabled but not tunneled through VPN
        let hasIPv6 = networkStatus.isIPv6Enabled
        let vpnSupportsIPv6 = vpnStatus.ipv6Supported

        if hasIPv6 && !vpnSupportsIPv6 {
            return PrivacyCheck(
                name: "IPv6 Handling",
                category: .ipv6,
                status: .warning,
                details: "IPv6 enabled but not tunneled through VPN",
                impact: "IPv6 traffic may bypass VPN tunnel",
                points: -10
            )
        }

        if !hasIPv6 {
            return PrivacyCheck(
                name: "IPv6 Handling",
                category: .ipv6,
                status: .pass,
                details: "IPv6 disabled (no leak possible)",
                impact: "No IPv6 leak risk",
                points: 0
            )
        }

        return PrivacyCheck(
            name: "IPv6 Handling",
            category: .ipv6,
            status: .pass,
            details: "IPv6 properly tunneled through VPN",
            impact: "Full IPv6 protection",
            points: 5  // Bonus for proper IPv6 handling
        )
    }

    private static func checkLatencyImpact(networkStatus: NetworkStatus) -> PrivacyCheck {
        guard let externalLatency = networkStatus.internet.latencyToExternal else {
            return PrivacyCheck(
                name: "Latency Impact",
                category: .latency,
                status: .notApplicable,
                details: "Unable to measure latency",
                impact: "Unknown",
                points: 0
            )
        }

        if externalLatency > 300 {
            return PrivacyCheck(
                name: "Latency Impact",
                category: .latency,
                status: .warning,
                details: "High latency (\(Int(externalLatency))ms)",
                impact: "Streaming services may flag unusual routing",
                points: -5
            )
        }

        if externalLatency > 150 {
            return PrivacyCheck(
                name: "Latency Impact",
                category: .latency,
                status: .warning,
                details: "Elevated latency (\(Int(externalLatency))ms)",
                impact: "Some services may detect VPN routing",
                points: -3
            )
        }

        return PrivacyCheck(
            name: "Latency Impact",
            category: .latency,
            status: .pass,
            details: "Good latency (\(Int(externalLatency))ms)",
            impact: "Latency unlikely to trigger VPN detection",
            points: 0
        )
    }

    private static func checkKnownProvider(geoIP: GeoIPInfo?) -> PrivacyCheck {
        guard let geo = geoIP else {
            return PrivacyCheck(
                name: "VPN Provider Visibility",
                category: .detectability,
                status: .notApplicable,
                details: "Unable to analyze",
                impact: "Unknown",
                points: 0
            )
        }

        // Known commercial VPN providers (their ASNs are often blocklisted)
        let knownVPNProviders = [
            "nordvpn", "expressvpn", "surfshark", "purevpn", "cyberghost",
            "private internet access", "pia", "mullvad", "protonvpn"
        ]

        let orgLower = (geo.org ?? "").lowercased()
        let asnLower = (geo.asn ?? "").lowercased()

        let isKnownVPN = knownVPNProviders.contains { provider in
            orgLower.contains(provider) || asnLower.contains(provider)
        }

        if isKnownVPN {
            return PrivacyCheck(
                name: "VPN Provider Visibility",
                category: .detectability,
                status: .warning,
                details: "Using known commercial VPN provider",
                impact: "IP ranges may be blocklisted by some services",
                points: -10
            )
        }

        return PrivacyCheck(
            name: "VPN Provider Visibility",
            category: .detectability,
            status: .pass,
            details: "Not using a well-known VPN provider IP",
            impact: "Lower chance of IP-based blocking",
            points: 5  // Bonus for obscurity
        )
    }

    // MARK: - Generate Recommendations

    private static func generateRecommendations(checks: [PrivacyCheck], score: Int) -> [String] {
        var recommendations: [String] = []

        // Add recommendations based on failed checks
        for check in checks where check.status == .fail || check.status == .warning {
            switch check.category {
            case .dnsLeak:
                recommendations.append("Enable DNS leak protection in your VPN settings, or manually configure DNS to a secure provider (1.1.1.1 or 8.8.8.8).")

            case .ipType:
                recommendations.append("For streaming services, consider switching to a residential proxy or a VPN server with residential IPs.")

            case .detectability:
                recommendations.append("Try using obfuscated protocols (Shadowsocks, V2Ray, Trojan) to reduce detectability.")

            case .ipv6:
                recommendations.append("Disable IPv6 in your network settings, or use a VPN that properly tunnels IPv6 traffic.")

            case .latency:
                recommendations.append("High latency suggests distant server. Switch to a closer VPN server for better performance and lower detectability.")

            default:
                break
            }
        }

        // General recommendations based on score
        if score >= 90 {
            recommendations.append("Your VPN privacy is excellent. No immediate action needed.")
        } else if score >= 75 {
            recommendations.append("Good privacy protection overall. Consider addressing the warnings above for optimal security.")
        } else if score < 55 {
            recommendations.append("Consider switching to a more privacy-focused VPN provider or adjusting your configuration.")
        }

        return recommendations
    }
}
