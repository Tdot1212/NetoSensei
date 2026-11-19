//
//  SecurityIntelligence.swift
//  NetoSensei
//
//  Security Intelligence Module - 100% Real Detections Only
//  NO fake scans, NO OS scanning, ONLY network symptom analysis
//

import Foundation
import SwiftUI

// MARK: - Security Intelligence Report

struct SecurityIntelligenceReport: Codable, Sendable {
    let timestamp: Date
    let overallScore: SecurityScore
    let threats: [SecurityThreat]
    let warnings: [SecurityWarning]
    let recommendations: [SecurityRecommendation]

    // DNS Security
    let dnsSecurityStatus: DNSSecurityStatus

    // Privacy Status
    let privacyStatus: PrivacyStatus

    // Gateway Security
    let gatewaySecurityStatus: GatewaySecurityStatus?

    // IP Reputation
    let ipReputationStatus: IPReputationStatus?

    // TLS Integrity
    let tlsIntegrityStatus: TLSIntegrityStatus?

    // Network Behavior
    let networkBehaviorStatus: NetworkBehaviorStatus?

    // Privacy Leakage
    let privacyLeakageStatus: PrivacyLeakageStatus?

    // Router Configuration
    let routerConfigStatus: RouterConfigStatus?

    // WiFi Security
    let wifiSecurityStatus: WiFiSecurityStatus?

    // ISP Throttling
    let ispThrottlingStatus: ISPThrottlingStatus?

    // WiFi Saturation
    let wifiSaturationStatus: WiFiSaturationStatus?

    // NAT Behavior
    let natBehaviorStatus: NATBehaviorStatus?

    // WiFi Roaming
    let wifiRoamingStatus: WiFiRoamingStatus?

    // Latency Stability
    let latencyStabilityStatus: LatencyStabilityStatus?

    var hasThreats: Bool {
        !threats.isEmpty
    }

    var hasCriticalThreats: Bool {
        threats.contains(where: { $0.severity == .critical })
    }

    var userFriendlySummary: String {
        switch overallScore {
        case .secure:
            return "🟢 Network security checks passed"
        case .caution:
            return "🟡 Some findings need attention"
        case .risky:
            return "🔴 Multiple security findings detected"
        case .compromised:
            return "⚠️ Significant security issues found"
        }
    }
}

// MARK: - Security Score

enum SecurityScore: String, Codable, Sendable {
    case secure = "Secure"
    case caution = "Caution"
    case risky = "Risky"
    case compromised = "Compromised"

    var color: Color {
        switch self {
        case .secure: return .green
        case .caution: return .yellow
        case .risky: return .orange
        case .compromised: return .red
        }
    }

    var emoji: String {
        switch self {
        case .secure: return "🟢"
        case .caution: return "🟡"
        case .risky: return "🔴"
        case .compromised: return "⚠️"
        }
    }
}

// MARK: - Security Threat

struct SecurityThreat: Identifiable, Codable, Sendable {
    let id: UUID
    let type: ThreatType
    let severity: ThreatSeverity
    let title: String
    let description: String
    let technicalDetails: String
    let detectedAt: Date
    let actionable: [String]  // What user can do

    init(
        type: ThreatType,
        severity: ThreatSeverity,
        title: String,
        description: String,
        technicalDetails: String,
        actionable: [String]
    ) {
        self.id = UUID()
        self.type = type
        self.severity = severity
        self.title = title
        self.description = description
        self.technicalDetails = technicalDetails
        self.detectedAt = Date()
        self.actionable = actionable
    }
}

enum ThreatType: String, Codable, Sendable {
    case dnsHijacking = "DNS Hijacking"
    case dnsManipulation = "DNS Manipulation"
    case dnsLeak = "DNS Leak"
    case unencryptedDNS = "Unencrypted DNS"
    case vpnLeak = "VPN Leak"
    case suspiciousDNSServer = "Suspicious DNS Server"
    case foreignDNSServer = "Foreign DNS Server"
    case ispDNSHijack = "ISP DNS Hijacking"
    case publicWiFiRisk = "Public WiFi Risk"
    case routerCompromise = "Router Compromise"

    // Gateway Behavior Threats
    case gatewayIPChange = "Gateway IP Changed"
    case rogueGateway = "Rogue Gateway"
    case gatewayLatencySpike = "Gateway Latency Spike"
    case unstableGateway = "Unstable Gateway"
    case fakeHotspot = "Fake Hotspot"

    // IP Reputation Threats
    case maliciousIP = "Malicious IP Address"
    case spamlistedIP = "Spam-listed IP"
    case proxyIP = "Proxy/VPN IP"
    case geolocationMismatch = "Geolocation Mismatch"
    case ipRotation = "Unusual IP Rotation"
    case botnetIP = "Botnet IP Address"
    case onThreatList = "IP on Threat Database"

    // TLS/HTTPS Integrity Threats
    case tlsMITM = "TLS Interception Detected"
    case certificateMismatch = "Certificate Mismatch"
    case sslHandshakeFailure = "SSL Handshake Failure"
    case httpsInterception = "HTTPS Interception"

    // Network Behavior Threats
    case captivePortal = "Captive Portal Detected"
    case packetInjection = "Packet Injection"
    case forcedRedirect = "Forced Redirects"
    case hiddenProxy = "Hidden Proxy Server"
    case connectionReset = "Unexpected Connection Resets"
    case trafficShaping = "Traffic Throttling"

    // Privacy Leakage Threats
    case ipExposure = "IP Address Exposed"
    case webRTCLeak = "WebRTC Leak"
    case locationMismatch = "Location Mismatch"
    case cgnatDetected = "CGNAT Network Detected"
    case ipv6Leak = "IPv6 Leak"

    // Router Configuration Threats
    case slowRouter = "Slow Router Response"
    case ttlAnomaly = "TTL Anomaly"
    case outdatedFirmware = "Outdated Router Firmware"
    case mtuMismatch = "MTU Mismatch"
    case noIPv6Support = "No IPv6 Support"

    // WiFi Security Threats
    case openNetwork = "Open WiFi Network"
    case weakEncryption = "Weak Encryption"
    case maliciousSSID = "Suspicious SSID Pattern"
    case noInternet = "No Internet Access"
    case routingChange = "Sudden Routing Change"

    // ISP Throttling Threats
    case internationalThrottling = "International Traffic Throttled"
    case streamingThrottling = "Streaming Throttled"
    case vpnThrottling = "VPN Throttled"
    case highJitter = "High Network Jitter"

    // WiFi Saturation Threats
    case routerOverload = "Router Overload"
    case highLANJitter = "High LAN Jitter"
    case frequentLatencySpikes = "Frequent Latency Spikes"

    // NAT Behavior Threats
    case symmetricNAT = "Symmetric NAT"
    case multipleNATLayers = "Multiple NAT Layers"

    // WiFi Roaming Threats
    case unstableRoaming = "Unstable WiFi Roaming"
    case meshNetworkIssues = "Mesh Network Issues"

    // Latency Stability Threats
    case poorLatencyStability = "Poor Latency Stability"
    case highPacketLoss = "High Packet Loss"
    case peakHourInstability = "Peak Hour Instability"

    // Rogue Hotspot Threats
    case rogueHotspot = "Rogue Hotspot"
    case suspiciousPublicIP = "Suspicious Public IP"
    case gatewayDNSMismatch = "Gateway/DNS Mismatch"
}

enum ThreatSeverity: String, Codable, Sendable {
    case info = "Info"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"

    var color: Color {
        switch self {
        case .info: return .blue
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }

    var emoji: String {
        switch self {
        case .info: return "ℹ️"
        case .low: return "✅"
        case .medium: return "🟡"
        case .high: return "🟠"
        case .critical: return "🔴"
        }
    }
}

// MARK: - Security Warning

struct SecurityWarning: Identifiable, Codable, Sendable {
    let id: UUID
    let title: String
    let message: String
    let priority: WarningPriority

    init(title: String, message: String, priority: WarningPriority) {
        self.id = UUID()
        self.title = title
        self.message = message
        self.priority = priority
    }
}

enum WarningPriority: String, Codable, Sendable {
    case info = "Info"
    case warning = "Warning"
    case urgent = "Urgent"
}

// MARK: - Security Recommendation

struct SecurityRecommendation: Identifiable, Codable, Sendable {
    let id: UUID
    let title: String
    let description: String
    let actions: [String]
    let priority: RecommendationPriority
    let estimatedImpact: String

    init(
        title: String,
        description: String,
        actions: [String],
        priority: RecommendationPriority,
        estimatedImpact: String
    ) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.actions = actions
        self.priority = priority
        self.estimatedImpact = estimatedImpact
    }
}

// MARK: - DNS Security Status

struct DNSSecurityStatus: Codable, Sendable {
    let isEncrypted: Bool
    let encryptionType: DNSEncryptionType?
    let currentDNSServer: String
    let expectedDNSServer: String?  // Based on ISP
    let dnsServerLocation: String?
    let dnsServerCountry: String?
    let isISPDNS: Bool
    let isForeignDNS: Bool
    let dnsMismatchDetected: Bool
    let dnsHijackDetected: Bool
    let dnsRewritingDetected: Bool
    let securityScore: Int  // 0-100

    var statusText: String {
        if dnsHijackDetected {
            return "🔴 DNS routing altered"
        } else if dnsRewritingDetected {
            return "🟠 DNS responses modified"
        } else if isForeignDNS {
            return "🟡 Foreign DNS Server"
        } else if !isEncrypted {
            return "🟡 DNS Not Encrypted"
        } else {
            return "🟢 DNS Secure"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if dnsHijackDetected {
            recs.append("⚠️ DNS responses differ from expected — enable VPN for secure DNS")
            recs.append("Restart your router")
            recs.append("Contact your ISP")
        } else if !isEncrypted {
            recs.append("Enable encrypted DNS (1.1.1.1 or 8.8.8.8)")
            recs.append("Use DNS-over-HTTPS in iOS Settings")
        } else if isForeignDNS {
            recs.append("Your DNS server is overseas - may be slow")
            recs.append("Consider switching to local DNS")
        }

        return recs
    }
}

enum DNSEncryptionType: String, Codable, Sendable {
    case none = "None"
    case doh = "DNS-over-HTTPS"
    case dot = "DNS-over-TLS"
    case unknown = "Unknown"
}

// MARK: - Privacy Status

struct PrivacyStatus: Codable, Sendable {
    let vpnActive: Bool
    let vpnLeakDetected: Bool
    let dnsLeakDetected: Bool
    let publicIPLocation: String?
    let publicIPCountry: String?
    let isProxy: Bool
    let isTor: Bool
    let privacyScore: Int  // 0-100

    var statusText: String {
        if vpnActive && vpnLeakDetected {
            return "🔴 VPN LEAK DETECTED"
        } else if vpnActive && dnsLeakDetected {
            return "🟠 DNS LEAK DETECTED"
        } else if vpnActive {
            return "🟢 VPN Active & Secure"
        } else {
            return "🟡 No VPN Protection"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if vpnLeakDetected {
            recs.append("⚠️ Your VPN is leaking your real IP")
            recs.append("Switch to a different VPN server")
            recs.append("Enable kill switch in VPN settings")
        } else if dnsLeakDetected {
            recs.append("⚠️ Your DNS queries are bypassing VPN")
            recs.append("Configure VPN to use VPN DNS servers")
            recs.append("Enable DNS leak protection")
        } else if !vpnActive {
            recs.append("Consider using a VPN on public WiFi")
            recs.append("Enable encrypted DNS (1.1.1.1)")
        }

        return recs
    }
}

// MARK: - Gateway Security Status

struct GatewaySecurityStatus: Codable, Sendable {
    let currentGatewayIP: String
    let previousGatewayIP: String?
    let gatewayIPChanged: Bool
    let gatewayLatency: Double  // ms
    let gatewayLatencyNormal: Bool
    let gatewayStable: Bool
    let isPrivateNetwork: Bool
    let isSuspiciousNetwork: Bool
    let handshakeSuccessRate: Double  // 0-100%
    let securityScore: Int  // 0-100

    var statusText: String {
        if gatewayIPChanged {
            return "🔴 Gateway IP Changed"
        } else if isSuspiciousNetwork {
            return "🔴 Suspicious Network"
        } else if !gatewayLatencyNormal {
            return "🟠 Gateway Latency Spike"
        } else if !gatewayStable {
            return "🟡 Unstable Gateway"
        } else {
            return "🟢 Gateway Secure"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if gatewayIPChanged {
            recs.append("⚠️ Gateway IP changed unexpectedly")
            recs.append("This may indicate a network change or reconfiguration")
            recs.append("If on an untrusted network, consider switching to cellular")
            recs.append("Use a VPN for additional protection")
        } else if isSuspiciousNetwork {
            recs.append("⚠️ This network has unusual characteristics")
            recs.append("May be a shared or misconfigured hotspot")
            recs.append("Avoid entering sensitive information without VPN")
            recs.append("Switch to a trusted network if possible")
        } else if !gatewayLatencyNormal {
            recs.append("Gateway latency is unusually high")
            recs.append("May indicate network congestion or misconfiguration")
            recs.append("Reboot router if you own it")
            recs.append("Otherwise, switch networks")
        } else if !gatewayStable {
            recs.append("Gateway is unstable")
            recs.append("May indicate router compromise")
            recs.append("Check router admin panel")
            recs.append("Update router firmware")
        }

        return recs
    }
}

// MARK: - IP Reputation Status

struct IPReputationStatus: Codable, Sendable {
    let publicIP: String
    let isBlacklisted: Bool
    let isSpam: Bool
    let isProxy: Bool
    let isTor: Bool
    let isHosting: Bool
    let isBotnet: Bool
    let isOnThreatList: Bool
    let threatLists: [String]
    let expectedCountry: String?
    let actualCountry: String?
    let geolocationMismatch: Bool
    let reputationScore: Int  // 0-100 (100 = clean)
    let threatDatabase: String?  // Which database flagged it

    var statusText: String {
        if isBotnet {
            return "🔴 BOTNET IP DETECTED"
        } else if isBlacklisted {
            return "🔴 IP BLACKLISTED"
        } else if isOnThreatList {
            return "🔴 IP on Threat Databases"
        } else if geolocationMismatch {
            return "🟠 Geolocation Mismatch"
        } else if isSpam {
            return "🟡 Spam-listed IP"
        } else if isProxy && !isTor {
            return "🟡 Proxy IP Detected"
        } else if isTor {
            return "🟡 Tor Exit Node"
        } else {
            return "🟢 IP Reputation Clean"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if isBotnet {
            recs.append("⚠️ Your IP appears on botnet activity lists")
            recs.append("This may indicate your router needs attention")
            recs.append("Reset router to factory defaults")
            recs.append("Update router firmware")
            recs.append("Scan connected devices for unwanted software")
            recs.append("Change all router passwords")
            recs.append("Contact your ISP for assistance")
        } else if isOnThreatList {
            recs.append("⚠️ Your IP appears on security databases:")
            recs.append(contentsOf: threatLists.map { "  • \($0)" })
            recs.append("Router may need a firmware update or reset")
            recs.append("Scan devices for unwanted software")
            recs.append("Reset router to factory defaults if issue persists")
            recs.append("Contact ISP if problem persists")
        } else if isBlacklisted {
            recs.append("⚠️ Your IP is on security watch lists")
            recs.append("Router may need attention — try a reset")
            recs.append("Reset your modem/router")
            recs.append("Contact ISP if problem persists")
        } else if geolocationMismatch {
            recs.append("⚠️ IP location doesn't match your actual location")
            recs.append("May indicate ISP rerouting or VPN leak")
            recs.append("Verify VPN is working correctly")
            recs.append("Contact ISP if no VPN is active")
        } else if isSpam {
            recs.append("Your IP appears on spam lists")
            recs.append("Router may be infected")
            recs.append("Scan all devices for malware")
            recs.append("Reset router to factory defaults")
        } else if isProxy || isTor {
            recs.append("IP detected as proxy/anonymizer")
            recs.append("Expected if using VPN/Tor")
            recs.append("Unexpected? Check for router compromise")
        }

        return recs
    }
}

// MARK: - TLS Integrity Status

struct TLSIntegrityStatus: Codable, Sendable {
    let testEndpointCount: Int
    let successfulHandshakes: Int
    let failedHandshakes: Int
    let certificateMismatches: Int
    let handshakeLatencyAverage: Double  // ms
    let handshakeLatencyNormal: Bool
    let integrityScore: Int  // 0-100

    var tlsInterceptionDetected: Bool {
        certificateMismatches > 0 || (failedHandshakes > testEndpointCount / 2)
    }

    var statusText: String {
        if certificateMismatches > 0 {
            return "🔴 Certificate mismatch detected"
        } else if tlsInterceptionDetected {
            return "🟠 TLS interception detected (check VPN/proxy settings)"
        } else if !handshakeLatencyNormal {
            return "🟡 Unusual TLS Latency"
        } else {
            return "🟢 TLS Integrity OK"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if certificateMismatches > 0 {
            recs.append("⚠️ Certificate mismatch detected for some sites")
            recs.append("If using a VPN/proxy, this may be from local TLS inspection")
            recs.append("Without VPN: avoid sensitive transactions on this network")
            recs.append("Consider switching to cellular for banking")
        } else if tlsInterceptionDetected {
            recs.append("ℹ️ TLS interception detected — likely from VPN/proxy app")
            recs.append("If you use Surge, Shadowrocket, or similar: this is expected")
            recs.append("If not: avoid sensitive transactions on this network")
            recs.append("Use cellular data for banking as a precaution")
        } else if !handshakeLatencyNormal {
            recs.append("TLS handshake latency is high")
            recs.append("May indicate network congestion or proxy overhead")
            recs.append("Use caution on this network")
        }

        return recs
    }
}

// MARK: - Network Behavior Status

struct NetworkBehaviorStatus: Codable, Sendable {
    let captivePortalDetected: Bool
    let packetInjectionLikely: Bool
    let forcedRedirectsDetected: Bool
    let hiddenProxyDetected: Bool
    let connectionResetsCount: Int
    let trafficShapingDetected: Bool
    let behaviorScore: Int  // 0-100

    var statusText: String {
        if captivePortalDetected {
            return "🟡 Captive Portal Detected"
        } else if packetInjectionLikely {
            return "🔴 Unexpected content injection detected"
        } else if forcedRedirectsDetected {
            return "🟠 Forced redirects detected"
        } else if hiddenProxyDetected {
            return "🟠 Transparent proxy detected"
        } else if trafficShapingDetected {
            return "🟡 Traffic Throttling Detected"
        } else if connectionResetsCount > 3 {
            return "🟠 Frequent Connection Resets"
        } else {
            return "🟢 Network Behavior Normal"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if captivePortalDetected {
            recs.append("Captive portal requires authentication")
            recs.append("Verify this is a legitimate WiFi network")
            recs.append("Avoid sensitive activity until authenticated")
        } else if packetInjectionLikely || forcedRedirectsDetected {
            recs.append("⚠️ Network modifying or redirecting traffic")
            recs.append("Use VPN for protection")
            recs.append("Avoid sensitive transactions without VPN")
            recs.append("Consider switching to cellular data")
        } else if hiddenProxyDetected {
            recs.append("ℹ️ Transparent proxy detected on this network")
            recs.append("Traffic may be routed through a network proxy")
            recs.append("Enable VPN for end-to-end encryption")
            recs.append("Contact network administrator if unexpected")
        } else if trafficShapingDetected {
            recs.append("ISP or network is throttling traffic")
            recs.append("Enable VPN to bypass throttling")
            recs.append("Contact ISP if persistent")
        } else if connectionResetsCount > 3 {
            recs.append("Frequent connection resets detected")
            recs.append("May indicate network instability or filtering")
            recs.append("Restart router or switch networks")
        }

        return recs
    }
}

// MARK: - Privacy Leakage Status

struct PrivacyLeakageStatus: Codable, Sendable {
    let ipExposed: Bool
    let dnsLeaking: Bool
    let webRTCLeaking: Bool
    let locationMismatch: Bool
    let cgnatDetected: Bool
    let ipv6Leaking: Bool
    let actualCity: String?
    let expectedCity: String?
    let internalIPExposed: Bool
    let privacyScore: Int  // 0-100

    var statusText: String {
        if webRTCLeaking {
            return "🔴 WebRTC Leak Detected"
        } else if dnsLeaking {
            return "🔴 DNS Leak Detected"
        } else if ipv6Leaking {
            return "🟠 IPv6 Leak Detected"
        } else if locationMismatch {
            return "🟡 Location Mismatch"
        } else if ipExposed {
            return "🟡 IP Exposed"
        } else {
            return "🟢 Privacy Protected"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if webRTCLeaking {
            recs.append("⚠️ WebRTC is leaking your real IP")
            recs.append("Your VPN is leaking DNS—switch to a different region")
            recs.append("Disable WebRTC in browser settings")
            recs.append("Use VPN with WebRTC leak protection")
        } else if dnsLeaking {
            recs.append("⚠️ DNS queries bypassing VPN")
            recs.append("Enable DNS leak protection in VPN")
            recs.append("Switch VPN server")
            recs.append("Test at dnsleaktest.com")
        } else if ipv6Leaking {
            recs.append("IPv6 traffic bypassing VPN")
            recs.append("Disable IPv6 or use VPN with IPv6 support")
            recs.append("Your real location may be exposed")
        } else if locationMismatch {
            recs.append("Your IP reveals your exact city—use privacy mode")
            recs.append("Expected: \(expectedCity ?? "Unknown")")
            recs.append("Actual: \(actualCity ?? "Unknown")")
        } else if ipExposed && cgnatDetected {
            recs.append("Your ISP showing your internal IP (CGNAT)")
            recs.append("Common in China and mobile networks")
            recs.append("Use VPN for privacy")
        }

        return recs
    }
}

// MARK: - Router Configuration Status

struct RouterConfigStatus: Codable, Sendable {
    let routerResponseTime: Double  // ms
    let ttlValue: Int?
    let ttlAnomalyDetected: Bool
    let firmwareOutdated: Bool
    let mtuValue: Int?
    let mtuMismatch: Bool
    let ipv6Supported: Bool
    let configScore: Int  // 0-100

    var statusText: String {
        if routerResponseTime > 200 {
            return "🟠 Slow Router Response"
        } else if ttlAnomalyDetected {
            return "🟡 TTL Anomaly Detected"
        } else if firmwareOutdated {
            return "🟡 Outdated Router Firmware"
        } else if mtuMismatch {
            return "🟡 MTU Mismatch"
        } else if !ipv6Supported {
            return "🟡 No IPv6 Support"
        } else {
            return "🟢 Router Config OK"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if routerResponseTime > 200 {
            recs.append("Your router firmware is outdated—consider upgrading hardware")
            recs.append("Router responding slowly (\(Int(routerResponseTime))ms)")
            recs.append("Update firmware or replace router")
        } else if ttlAnomalyDetected {
            recs.append("TTL anomaly detected—possible firmware issue")
            recs.append("May indicate router compromise")
            recs.append("Check router admin panel")
        } else if firmwareOutdated {
            recs.append("Router firmware appears outdated")
            recs.append("Update firmware for security patches")
            recs.append("Visit router manufacturer website")
        } else if mtuMismatch {
            recs.append("Your router MTU is causing performance issues—restart router or change ISP")
            recs.append("May cause packet fragmentation")
            recs.append("Contact ISP for optimal MTU settings")
        } else if !ipv6Supported {
            recs.append("Router doesn't support IPv6")
            recs.append("Often indicates outdated hardware")
            recs.append("Consider router upgrade")
        }

        return recs
    }
}

// MARK: - WiFi Security Status

struct WiFiSecurityStatus: Codable, Sendable {
    let ssid: String?
    let isOpen: Bool
    let encryptionType: String?
    let isWeakEncryption: Bool
    let maliciousSSIDPattern: Bool
    let hasInternet: Bool
    let routingChanged: Bool
    let previousRoute: String?
    let currentRoute: String?
    let rogueHotspotDetected: Bool
    let rogueHotspotIndicators: [String]
    let suspiciousPublicIP: Bool
    let gatewayDNSMismatch: Bool
    let securityScore: Int  // 0-100

    var statusText: String {
        if rogueHotspotDetected {
            return "🔴 Suspicious hotspot detected"
        } else if isOpen {
            return "🔴 Open WiFi Network"
        } else if isWeakEncryption {
            return "🟠 Weak Encryption"
        } else if maliciousSSIDPattern {
            return "🟠 Suspicious SSID pattern"
        } else if suspiciousPublicIP {
            return "🟠 Unusual Public IP"
        } else if gatewayDNSMismatch {
            return "🟡 Gateway/DNS Mismatch"
        } else if !hasInternet {
            return "🟠 No Internet Access"
        } else if routingChanged {
            return "🟡 Routing Changed"
        } else {
            return "🟢 WiFi Secure"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if rogueHotspotDetected {
            recs.append("⚠️ This hotspot has suspicious characteristics")
            recs.append(contentsOf: rogueHotspotIndicators)
            recs.append("Avoid entering passwords or sensitive information")
            recs.append("Consider switching to cellular data")
            recs.append("If you entered credentials, consider changing passwords")
        } else if suspiciousPublicIP {
            recs.append("⚠️ Public IP has unusual characteristics")
            recs.append("IP may be from a hosting provider or shared network")
            recs.append("Use VPN for additional protection")
        } else if gatewayDNSMismatch {
            recs.append("⚠️ Gateway and DNS server addresses don't match")
            recs.append("DNS may be configured separately from the gateway")
            recs.append("If unexpected, verify network settings")
        } else if isOpen {
            recs.append("⚠️ This WiFi network has no password — avoid sensitive activity")
            recs.append("No password protection detected")
            recs.append("Use VPN or switch to cellular for sensitive tasks")
        } else if isWeakEncryption {
            recs.append("Weak WPA1 encryption detected")
            recs.append("Consider asking admin to upgrade to WPA3")
            recs.append("Use VPN for protection")
        } else if maliciousSSIDPattern {
            recs.append("⚠️ Suspicious WiFi name detected")
            recs.append("May be a fake hotspot")
            recs.append("Verify network authenticity")
            recs.append("Avoid sensitive transactions")
        } else if !hasInternet {
            recs.append("Network has no internet access")
            recs.append("May be a phishing hotspot")
            recs.append("Disconnect and switch networks")
        } else if routingChanged {
            recs.append("Routing changed unexpectedly")
            recs.append("Previous: \(previousRoute ?? "Unknown")")
            recs.append("Current: \(currentRoute ?? "Unknown")")
            recs.append("Possible network reconfiguration")
        }

        return recs
    }
}
