//
//  NetworkStatus.swift
//  NetoSensei
//
//  Network status model for real-time monitoring
//

import Foundation
import Network

enum NetworkHealth {
    case excellent  // Green
    case fair       // Yellow
    case poor       // Red
    case unknown    // Gray

    var color: String {
        switch self {
        case .excellent: return "green"
        case .fair: return "yellow"
        case .poor: return "red"
        case .unknown: return "gray"
        }
    }
}

struct WiFiInfo {
    var ssid: String?
    var bssid: String?

    // Radio layer metrics (VERY IMPORTANT for diagnostics)
    // Note: iOS does not expose real WiFi radio metrics via public APIs.
    // These values are estimated based on connection quality tests.
    var rssi: Int?  // dBm - Signal strength (estimated on iOS)
    var noise: Int?  // dBm - Noise floor (estimated on iOS)
    var linkSpeed: Int?  // Mbps - TX rate (estimated on iOS)
    var channel: Int?  // Channel number (estimated on iOS)
    var channelWidth: Int?  // MHz - 20, 40, 80, 160 (estimated on iOS)
    var band: String?  // "2.4 GHz", "5 GHz", "6 GHz" (estimated on iOS)
    var phyMode: String?  // "802.11ac", "802.11ax", etc. (estimated on iOS)
    var mcsIndex: Int?  // Modulation and Coding Scheme (estimated on iOS)
    var nss: Int?  // Number of Spatial Streams (estimated on iOS)

    var isConnected: Bool

    // NEHotspotNetwork signal strength (0.0 to 1.0) — one of the few real RF metrics Apple exposes
    var signalStrength: Double?

    /// Signal quality derived from NEHotspotNetwork.signalStrength
    enum SignalQuality: String, Codable {
        case excellent  // > 0.75
        case good       // 0.5 - 0.75
        case fair       // 0.25 - 0.5
        case poor       // < 0.25
        case unknown

        init(from strength: Double?) {
            guard let strength = strength else { self = .unknown; return }
            switch strength {
            case 0.75...: self = .excellent
            case 0.5..<0.75: self = .good
            case 0.25..<0.5: self = .fair
            default: self = .poor
            }
        }
    }

    /// Computed signal quality from NEHotspotNetwork signal strength
    var signalQualityLevel: SignalQuality {
        SignalQuality(from: signalStrength)
    }

    /// Indicates that WiFi radio metrics are estimates (iOS limitation)
    /// Apple does not expose real RSSI, channel, or link speed via public APIs
    var metricsAreEstimated: Bool {
        return true  // Always true on iOS
    }

    /// Disclaimer text explaining the estimation
    var metricsDisclaimer: String {
        "WiFi metrics are estimated based on connection quality. iOS does not provide direct access to radio layer data."
    }

    // Computed SNR (Signal-to-Noise Ratio)
    var snr: Int? {
        guard let rssi = rssi, let noise = noise else { return nil }
        return rssi - noise  // > 30 dB = Excellent, 20-30 = OK, < 20 = Poor
    }

    var health: NetworkHealth {
        // FIXED: iOS has NO public API for RSSI or link speed
        // We cannot measure WiFi signal strength on iOS.
        // Return .unknown since we have no real data to base health on.
        // The router latency test in RouterInfo is the actual indicator of local network health.
        return .unknown
    }

    var signalQuality: String {
        // FIXED: iOS has NO public API for RSSI or link speed
        // We cannot measure WiFi signal strength.
        return "Not available on iOS"
    }

    var airtimeQuality: String {
        // FIXED: iOS has NO public API for TX rate
        // We cannot measure airtime quality.
        return "Not available on iOS"
    }
}

struct RouterInfo {
    var gatewayIP: String?
    var isReachable: Bool
    var latency: Double?  // ms
    var packetLoss: Double?  // percentage
    var jitter: Double?  // ms
    var adminURL: String?  // http(s)://gateway if port 80/443 responds

    /// Latency that is safe to display: real measurement only, no sentinels.
    var displayableLatency: Double? {
        LatencyValidation.normalize(latency)
    }

    /// True iff we have a real (non-sentinel) latency measurement to the gateway.
    /// A successful measurement IS proof of reachability — even when isReachable
    /// is stale or the gatewayIP was cleared by a timeout fallback.
    var hasMeasuredLatency: Bool {
        displayableLatency != nil
    }

    var health: NetworkHealth {
        // FIXED: Router health based on packet loss + latency, not just latency alone
        // Single unreachable ping != router failure
        guard let latency = latency else { return .unknown }

        let loss = packetLoss ?? 0.0

        // Router is ONLY poor if:
        // 1. High latency (>50ms) OR
        // 2. Moderate latency (>20ms) AND packet loss exists (>0%)
        // 3. High packet loss (>5%)
        if loss > 5.0 { return .poor }
        if latency > 50 { return .poor }
        if latency > 20 && loss > 0 { return .fair }  // Degraded but not poor

        // Excellent: low latency, no loss
        if latency < 10 && loss == 0 { return .excellent }

        // Fair: acceptable latency, minimal loss
        return .fair
    }
}

struct InternetInfo {
    var isReachable: Bool
    var externalPingSuccess: Bool
    var latencyToExternal: Double?  // ms to 1.1.1.1 or 8.8.8.8
    var httpTestSuccess: Bool
    var cdnReachable: Bool

    /// Latency that is safe to display (no sentinels).
    var displayableLatency: Double? {
        LatencyValidation.normalize(latencyToExternal)
    }

    var health: NetworkHealth {
        if !isReachable || !externalPingSuccess { return .poor }
        if httpTestSuccess && cdnReachable { return .excellent }
        if httpTestSuccess { return .fair }
        return .poor
    }
}

struct DNSInfo {
    var resolverIP: String?
    var latency: Double?  // ms
    var lookupSuccess: Bool
    var recommendedDNS: String?

    var health: NetworkHealth {
        if !lookupSuccess { return .poor }
        guard let latency = latency else { return .unknown }
        if latency < 30 { return .excellent }
        if latency < 100 { return .fair }
        return .poor
    }

    /// Latency that is safe to display to the user.
    /// Returns nil when the value is missing OR is a known sentinel
    /// (999, 9999, negative, infinity) emitted by failed/timed-out probes.
    var displayableLatency: Double? {
        guard lookupSuccess, let l = latency else { return nil }
        return LatencyValidation.normalize(l)
    }
}

/// Helpers to keep timeout/failure sentinels (999, 9999, -1, .infinity)
/// from leaking into UI text or recommendation logic.
enum LatencyValidation {
    /// Returns the latency if it's a real measurement; nil if it's a sentinel.
    static func normalize(_ latency: Double?) -> Double? {
        guard let l = latency else { return nil }
        if l.isNaN || l.isInfinite { return nil }
        if l < 0 { return nil }
        // 999 / 9999 are "test failed/timed out" sentinels used throughout the
        // engines (see DNSBenchmark, GatewaySecurityScanner, etc.). They are not
        // real measurements and must never be shown to the user.
        if l >= 999 { return nil }
        return l
    }

    static func isSentinel(_ latency: Double?) -> Bool {
        guard let l = latency else { return false }
        return normalize(l) == nil
    }
}

struct VPNInfo {
    var isActive: Bool
    var tunnelType: String?  // IKEv2, WireGuard, IPSec, OpenVPN, L2TP, Shadowsocks, etc.
    var vpnProtocol: String?  // Detected protocol from interface analysis
    var serverLocation: String?
    var serverIP: String?
    var tunnelReachable: Bool
    var tunnelLatency: Double?  // ms
    var packetLoss: Double?
    var throughputImpact: Double?  // percentage reduction
    var ipv6Supported: Bool
    var dnsLeakDetected: Bool

    // Enhanced detection fields
    var detectionConfidence: Double  // 0.0 to 1.0
    var detectionMethods: [String]  // Which methods detected VPN
    var ipType: String?  // "Datacenter" or "Residential"
    var ispName: String?  // ISP/hosting provider name
    var displayLabel: String?  // e.g. "WireGuard VPN - Datacenter IP (Zenlayer)"

    // Authoritative vs inference
    var isAuthoritative: Bool  // true = NEVPNManager confirmed, false = ISP/inference
    var inferenceReasons: [String]  // Human-readable reasons (e.g. "IP belongs to datacenter: Zenlayer")

    // VPN State Machine (6 states)
    var vpnState: VPNState

    init(isActive: Bool = false, tunnelType: String? = nil, vpnProtocol: String? = nil,
         serverLocation: String? = nil, serverIP: String? = nil,
         tunnelReachable: Bool = false, tunnelLatency: Double? = nil,
         packetLoss: Double? = nil, throughputImpact: Double? = nil,
         ipv6Supported: Bool = false, dnsLeakDetected: Bool = false,
         detectionConfidence: Double = 0.0, detectionMethods: [String] = [],
         ipType: String? = nil, ispName: String? = nil, displayLabel: String? = nil,
         isAuthoritative: Bool = false, inferenceReasons: [String] = [],
         vpnState: VPNState = .unknown) {
        self.isActive = isActive
        self.tunnelType = tunnelType
        self.vpnProtocol = vpnProtocol
        self.serverLocation = serverLocation
        self.serverIP = serverIP
        self.tunnelReachable = tunnelReachable
        self.tunnelLatency = tunnelLatency
        self.packetLoss = packetLoss
        self.throughputImpact = throughputImpact
        self.ipv6Supported = ipv6Supported
        self.dnsLeakDetected = dnsLeakDetected
        self.detectionConfidence = detectionConfidence
        self.detectionMethods = detectionMethods
        self.ipType = ipType
        self.ispName = ispName
        self.displayLabel = displayLabel
        self.isAuthoritative = isAuthoritative
        self.inferenceReasons = inferenceReasons
        self.vpnState = vpnState
    }

    var health: NetworkHealth {
        if !isActive { return .unknown }
        if !tunnelReachable { return .poor }
        if let latency = tunnelLatency {
            if latency < 50 && (packetLoss ?? 0) < 1 { return .excellent }
            if latency < 100 && (packetLoss ?? 0) < 5 { return .fair }
            return .poor
        }
        return .fair
    }
}

struct NetworkStatus {
    var timestamp: Date

    // Core components
    var wifi: WiFiInfo
    var router: RouterInfo
    var internet: InternetInfo
    var dns: DNSInfo
    var vpn: VPNInfo

    // Network details
    var publicIP: String?
    var localIP: String?
    var ipv6Address: String?
    var isCGNAT: Bool
    var isProxyDetected: Bool

    // Device network mode
    var isIPv4Enabled: Bool
    var isIPv6Enabled: Bool
    var connectionType: NWInterface.InterfaceType?
    var isHotspot: Bool  // True if connected to mobile hotspot/tethering

    // Network congestion indicators
    var estimatedDeviceCount: Int?
    var bandwidthUtilization: Double?  // percentage

    // Performance metrics (from streaming/throughput tests)
    var streamingThroughput: Double?  // Mbps - actual streaming throughput
    var performanceThroughput: Double?  // Mbps - general performance test throughput

    // Overall health - WEIGHTED ALGORITHM WITH CONSISTENCY CHECK
    // FIXED: Prevents "Excellent" when components show issues
    // Based on actual user experience impact, not equal weight
    var overallHealth: NetworkHealth {
        // FIXED: Check for critical issues first - prevents "Excellent" + "Issue" contradiction
        // If any fundamental component is poor, overall cannot be excellent
        if router.health == .poor || wifi.health == .poor {
            // Local network has critical issues
            return .poor
        }

        if internet.health == .poor {
            // Internet connection is broken
            return .poor
        }

        // FIXED: If any component is fair, overall cannot be excellent
        let hasAnyIssue = router.health == .fair || wifi.health == .fair ||
                          internet.health == .fair || dns.health == .fair

        // Weights based on real user impact:
        // Streaming throughput: 35% - what user actually experiences
        // Packet loss: 25% - causes freezing/buffering
        // Jitter: 15% - causes quality drops
        // Latency: 10% - affects responsiveness
        // DNS: 5% - rarely the bottleneck
        // Router reachability: 10% - fundamental connectivity

        var totalScore: Double = 0
        var totalWeight: Double = 0

        // 1. Streaming Throughput (35% weight) - HIGHEST PRIORITY
        if let throughput = streamingThroughput ?? performanceThroughput, throughput >= 0 {
            let throughputScore: Double
            if throughput >= 25 { throughputScore = 100 }  // Excellent
            else if throughput >= 10 { throughputScore = 75 }  // Fair
            else if throughput >= 5 { throughputScore = 50 }  // Poor
            else if throughput >= 1 { throughputScore = 25 }  // Very poor
            else { throughputScore = 0 }  // Broken

            totalScore += throughputScore * 0.35
            totalWeight += 0.35
        }

        // 2. Packet Loss (25% weight) - from router or internet
        if let loss = router.packetLoss {
            let lossScore: Double
            if loss < 1 { lossScore = 100 }
            else if loss < 3 { lossScore = 75 }
            else if loss < 5 { lossScore = 50 }
            else { lossScore = 0 }

            totalScore += lossScore * 0.25
            totalWeight += 0.25
        }

        // 3. Jitter (15% weight) - from router
        if let jitter = router.jitter {
            let jitterScore: Double
            if jitter < 10 { jitterScore = 100 }
            else if jitter < 30 { jitterScore = 75 }
            else if jitter < 50 { jitterScore = 50 }
            else { jitterScore = 0 }

            totalScore += jitterScore * 0.15
            totalWeight += 0.15
        }

        // 4. Latency (10% weight) - combined router + internet
        if let routerLatency = router.latency {
            let latencyScore: Double
            if routerLatency < 10 { latencyScore = 100 }
            else if routerLatency < 30 { latencyScore = 75 }
            else if routerLatency < 50 { latencyScore = 50 }
            else { latencyScore = 0 }

            totalScore += latencyScore * 0.10
            totalWeight += 0.10
        }

        // 5. DNS (5% weight) - rarely the bottleneck
        if let dnsLatency = dns.latency {
            let dnsScore: Double
            if dnsLatency < 30 { dnsScore = 100 }
            else if dnsLatency < 100 { dnsScore = 75 }
            else if dnsLatency < 200 { dnsScore = 50 }
            else { dnsScore = 0 }

            totalScore += dnsScore * 0.05
            totalWeight += 0.05
        }

        // 6. Router Reachability (10% weight) - fundamental connectivity
        let reachabilityScore: Double = router.isReachable ? 100 : 0
        totalScore += reachabilityScore * 0.10
        totalWeight += 0.10

        // Calculate final weighted score
        guard totalWeight > 0 else { return .unknown }
        let finalScore = totalScore / totalWeight

        // Convert score to health
        // FIXED: Cap at .fair if any component has issues
        if finalScore >= 85 {
            return hasAnyIssue ? .fair : .excellent
        }
        if finalScore >= 60 { return .fair }
        if finalScore >= 30 { return .poor }
        return .poor
    }

    // Unified network state: separates local vs external issues
    var networkState: (local: NetworkHealth, external: NetworkHealth, summary: String) {
        // Local = WiFi + Router
        let localComponents = [wifi.health, router.health]
        let localState: NetworkHealth
        if localComponents.contains(.poor) { localState = .poor }
        else if localComponents.contains(.fair) { localState = .fair }
        else if localComponents.allSatisfy({ $0 == .excellent }) { localState = .excellent }
        else { localState = .unknown }

        // External = Internet + DNS + throughput
        var externalComponents = [internet.health, dns.health]
        let externalState: NetworkHealth

        // Check streaming/performance throughput
        if let throughput = streamingThroughput ?? performanceThroughput {
            if throughput >= 0 && throughput < 1.0 {
                externalComponents.append(.poor)
            } else if throughput >= 1.0 && throughput < 5.0 {
                externalComponents.append(.fair)
            } else if throughput >= 5.0 {
                externalComponents.append(.excellent)
            }
            // throughput < 0 means test blocked - ignore
        }

        if externalComponents.contains(.poor) { externalState = .poor }
        else if externalComponents.contains(.fair) { externalState = .fair }
        else if externalComponents.allSatisfy({ $0 == .excellent }) { externalState = .excellent }
        else { externalState = .unknown }

        // Generate summary
        let summary: String
        switch (localState, externalState) {
        case (.excellent, .excellent):
            summary = "All systems operational"
        case (.excellent, .fair), (.fair, .fair):
            summary = "Local network OK, external path degraded"
        case (.excellent, .poor):
            summary = "Local network OK, external path severely degraded"
        case (.fair, .excellent), (.poor, .excellent):
            summary = "Local network degraded, external path OK"
        case (.fair, .poor), (.poor, .fair), (.poor, .poor):
            summary = "Both local and external network degraded"
        default:
            summary = "Insufficient data to diagnose"
        }

        return (localState, externalState, summary)
    }

    static var empty: NetworkStatus {
        NetworkStatus(
            timestamp: Date(),
            wifi: WiFiInfo(isConnected: false),
            router: RouterInfo(isReachable: false),
            internet: InternetInfo(isReachable: false, externalPingSuccess: false, httpTestSuccess: false, cdnReachable: false),
            dns: DNSInfo(lookupSuccess: false),
            vpn: VPNInfo(),
            isCGNAT: false,
            isProxyDetected: false,
            isIPv4Enabled: true,
            isIPv6Enabled: false,
            isHotspot: false
        )
    }
}

// MARK: - VPN State Machine (6 states)

enum VPNState: String {
    case off           // NEVPNManager confirmed no VPN + residential ISP
    case probablyOff   // NEVPNManager unavailable + residential ISP + no geo mismatch
    case connecting    // NEVPNManager transitional state
    case on            // NEVPNManager confirmed VPN connected
    case probablyOn    // NEVPNManager unavailable + datacenter ISP OR geo mismatch
    case unknown       // Initial state or insufficient data

    var isDefinitelyOn: Bool { self == .on }
    var isLikelyOn: Bool { self == .on || self == .probablyOn }
    var isDefinitelyOff: Bool { self == .off }
    var isLikelyOff: Bool { self == .off || self == .probablyOff }

    var displayText: String {
        switch self {
        case .off: return "No VPN"
        case .probablyOff: return "No VPN"
        case .connecting: return "VPN Connecting..."
        case .on: return "VPN Active"
        case .probablyOn: return "VPN/Proxy Detected (inferred)"
        case .unknown: return "VPN Status Unknown"
        }
    }

    var isAuthoritative: Bool {
        self == .on || self == .off || self == .connecting
    }
}

// MARK: - Probe System

enum ProbeStatus: String {
    case success
    case timeout
    case blocked
    case failed
    case unavailable
    case skipped
}

struct ProbeResult: Identifiable {
    let id = UUID()
    let name: String         // e.g. "LOCAL_NETWORK", "DOMESTIC_INTERNET"
    let target: String       // e.g. "192.168.1.1", "baidu.com"
    let status: ProbeStatus
    let latencyMs: Double?
    let detail: String       // human-readable detail
    let confidence: Double   // 0.0 - 1.0
    let timestamp: Date

    var passed: Bool { status == .success }
}

// MARK: - Explanation Cards (MEASURED/RESULT/CONFIDENCE/NEXT_STEPS)

enum CardCategory: String {
    case wifi = "WiFi"
    case router = "Router"
    case internet = "Internet"
    case vpn = "VPN"
    case dns = "DNS"
    case speed = "Speed"
    case tls = "Security"
    case privacy = "Privacy"   // FIX (Sec Issue 3): privacy-score evidence
}

enum CardResult: String {
    case good = "Good"
    case warning = "Warning"
    case problem = "Problem"
    case hidden = "Hidden"     // e.g. gateway hidden by VPN
    case unknown = "Unknown"
}

enum CardConfidence {
    case high(String)    // e.g. "NEVPNManager confirmed"
    case medium(String)  // e.g. "Inferred from ISP classification"
    case low(String)     // e.g. "Insufficient data"

    var label: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var detail: String {
        switch self {
        case .high(let s), .medium(let s), .low(let s): return s
        }
    }
}

struct ExplanationCard: Identifiable {
    let id = UUID()
    let category: CardCategory
    let measured: String         // "Gateway latency: 3ms (5 pings, median)"
    let result: CardResult
    let confidence: CardConfidence
    let nextSteps: String        // "No action needed" or "Move closer to router"
    let iOSLimitation: String?   // "iOS cannot measure WiFi signal strength"
    /// FIX (Sec Issue 6): Optional override for the row title in Evidence list.
    /// Two `category: .internet` cards (Domestic + Overseas) used to render
    /// as two stacked "Internet" rows with opposite verdicts. When set, the
    /// view renders this in place of `category.rawValue`.
    var displayLabel: String? = nil
}

// MARK: - 5-Score System

struct NetworkScores {
    let localNetwork: Int           // 0-100: Gateway, WiFi, local connectivity
    let domesticInternet: Int       // 0-100: Domestic endpoints
    let internationalInternet: Int  // 0-100: Overseas endpoints
    let privacy: Int                // 0-100: VPN status, DNS privacy
    let stability: Int              // 0-100: Packet loss, jitter, uptime

    /// Human-readable summary highlighting each dimension
    var summary: String {
        var parts: [String] = []
        parts.append("\(label(localNetwork)) local network (\(localNetwork))")
        parts.append("\(label(domesticInternet)) domestic internet (\(domesticInternet))")
        parts.append("\(label(internationalInternet)) international routing (\(internationalInternet))")
        return parts.joined(separator: ", ")
    }

    private func label(_ score: Int) -> String {
        if score >= 80 { return "Strong" }
        if score >= 60 { return "Good" }
        if score >= 40 { return "Fair" }
        if score >= 20 { return "Weak" }
        return "Poor"
    }
}

// MARK: - Network Facts (Layer 1: Raw data, no interpretation)

struct NetworkFacts {
    let timestamp: Date

    // Connection
    let wifiConnected: Bool
    let ssid: String?
    let connectionType: String  // "WiFi", "Cellular", "Unknown"

    // Gateway
    let gatewayIP: String?
    let gatewayReachable: Bool
    let gatewayLatencyMs: Double?
    let gatewayPacketLoss: Double?
    let gatewayJitterMs: Double?

    // Internet
    let domesticReachable: Bool
    let domesticLatencyMs: Double?
    let domesticTarget: String       // e.g. "baidu.com" or "cloudflare-dns.com"
    let overseasReachable: Bool
    let overseasLatencyMs: Double?
    let overseasTarget: String       // e.g. "google.com"

    // DNS
    let dnsResolverIP: String?
    let dnsLookupSuccess: Bool
    let dnsLatencyMs: Double?

    // IP Identity
    let publicIP: String?
    let ipCountry: String?
    let ipISP: String?
    let ipVerified: Bool

    // Device locale (for China detection)
    let deviceLocale: String
    let isLikelyInChina: Bool

    /// Build from current NetworkStatus + VPN detection
    static func from(status: NetworkStatus, vpnResult: SmartVPNDetector.VPNDetectionResult?) -> NetworkFacts {
        NetworkFacts(
            timestamp: Date(),
            wifiConnected: status.wifi.isConnected,
            ssid: status.wifi.ssid,
            connectionType: status.connectionType?.displayName ?? "Unknown",
            gatewayIP: status.router.gatewayIP,
            gatewayReachable: status.router.isReachable,
            gatewayLatencyMs: status.router.latency,
            gatewayPacketLoss: status.router.packetLoss,
            gatewayJitterMs: status.router.jitter,
            domesticReachable: status.internet.isReachable,
            domesticLatencyMs: status.internet.latencyToExternal,
            domesticTarget: (vpnResult?.isLikelyInChina == true) ? "baidu.com" : "cloudflare-dns.com",
            overseasReachable: status.internet.httpTestSuccess,
            overseasLatencyMs: nil,  // Measured separately by probe
            overseasTarget: "google.com",
            dnsResolverIP: status.dns.resolverIP,
            dnsLookupSuccess: status.dns.lookupSuccess,
            dnsLatencyMs: status.dns.latency,
            publicIP: vpnResult?.publicIP ?? status.publicIP,
            ipCountry: vpnResult?.publicCountry,
            ipISP: vpnResult?.publicISP,
            ipVerified: vpnResult?.ipVerified ?? false,
            deviceLocale: Locale.current.identifier,
            isLikelyInChina: vpnResult?.isLikelyInChina ?? false
        )
    }
}

// MARK: - Network Diagnosis

struct NetworkDiagnosis {
    let timestamp: Date
    let vpnState: VPNState
    let vpnEvidence: [String]     // reasons for the VPN state
    let probeResults: [ProbeResult]
    let cards: [ExplanationCard]
    let scores: NetworkScores     // 5 independent scores
    let primaryIssue: String?     // root cause or nil if healthy
    let summary: String           // one-line plain English
    let facts: NetworkFacts?      // raw facts snapshot

    /// Legacy single health score (average of 5 scores)
    var healthScore: Int {
        (scores.localNetwork + scores.domesticInternet + scores.internationalInternet + scores.privacy + scores.stability) / 5
    }
}
