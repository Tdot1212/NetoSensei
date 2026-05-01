//
//  StreamingDiagnosticResult.swift
//  NetoSensei
//
//  Streaming-specific diagnostic results
//

import Foundation

enum StreamingPlatform: String, CaseIterable {
    case netflix = "Netflix"
    case youtube = "YouTube"
    case tiktok = "TikTok"
    case twitch = "Twitch"
    case disneyPlus = "Disney+"
    case amazonPrime = "Amazon Prime"
    case appleTV = "Apple TV+"
    case hulu = "Hulu"
}

struct CDNTestResult {
    var platform: StreamingPlatform
    var endpoint: String
    var isReachable: Bool
    var latency: Double?  // ms
    var throughput: Double?  // Mbps
    var regionDetected: String?
    var routingOptimal: Bool
    var estimatedQuality: VideoQuality

    enum VideoQuality {
        case sd      // < 3 Mbps
        case hd      // 3-8 Mbps
        case fullHD  // 8-25 Mbps
        case uhd4K   // > 25 Mbps

        var description: String {
            switch self {
            case .sd: return "SD (480p)"
            case .hd: return "HD (720p)"
            case .fullHD: return "Full HD (1080p)"
            case .uhd4K: return "4K UHD"
            }
        }
    }
}

struct StreamingDiagnosticResult {
    var timestamp: Date
    var platform: StreamingPlatform

    // CDN Testing
    var cdnPing: Double  // ms
    var cdnThroughput: Double  // Mbps
    var cdnReachable: Bool
    var cdnRegion: String?
    var cdnRoutingIssue: Bool

    // Network Factors
    var wifiStrength: Int  // RSSI in dBm
    var routerLatency: Double?
    var jitter: Double?
    var packetLoss: Double?

    // VPN Impact Analysis
    var vpnActive: Bool
    var vpnImpact: Double?  // Percentage reduction in speed
    var throughputWithVPN: Double?
    var throughputWithoutVPN: Double?
    var vpnServerLocation: String?

    // ISP Congestion
    var ispCongestion: Bool
    var timeOfDay: Date
    var historicalCongestionPattern: String?

    // DNS Performance
    var dnsLatency: Double
    var dnsProvider: String?

    // IPv6 Fallback
    var ipv6Available: Bool
    var ipv6Faster: Bool

    // Estimated Device Count
    var estimatedDeviceCount: Int?

    // Root Cause Analysis
    var primaryBottleneck: BottleneckType
    var secondaryFactors: [BottleneckType]

    enum BottleneckType: String {
        case vpn = "VPN Server"
        // FIXED: Changed from "Wi-Fi Signal" since iOS cannot measure RSSI
        case wifi = "Local Network"  // Kept for backwards compatibility, displays as "Local Network"
        case router = "Router Congestion"
        case isp = "ISP Congestion"
        case cdn = "CDN Routing"
        case dns = "DNS Resolution"
        case device = "Device Limitation"
        case none = "No Issues Detected"
    }

    /// FIX (Speed Issue 4): The user-visible label for the primary bottleneck.
    /// When VPN is active and the bottleneck is `.vpn`, prefer "VPN Server
    /// Distance" over the generic "VPN Server" — the user is seeing the cost
    /// of routing through a distant exit, not a problem with the VPN itself.
    var primaryBottleneckDisplay: String {
        if vpnActive && primaryBottleneck == .vpn && cdnPing > 150 {
            return "VPN Server Distance"
        }
        return primaryBottleneck.rawValue
    }

    // Recommendations
    var recommendation: String
    var actionableSteps: [String]

    // One-Tap Fix
    var fixAction: FixAction?

    enum FixAction {
        case switchVPNServer(region: String)
        case disconnectVPN
        case moveCloserToRouter
        case switchDNS
        case switchToCellular
        case restartRouter
        case changeVPNRegion(recommended: String)
        case waitForOffPeakHours(hours: String)
    }

    // Video Quality Estimation
    var estimatedVideoQuality: CDNTestResult.VideoQuality {
        if cdnThroughput < 0 { return .sd }  // Test blocked/failed
        if cdnThroughput >= 25 { return .uhd4K }
        if cdnThroughput >= 8 { return .fullHD }
        if cdnThroughput >= 3 { return .hd }
        return .sd
    }

    var hasIssues: Bool {
        primaryBottleneck != .none || isLikelyGeoBlocked
    }

    // ISSUE 9 FIX: Detect geo-restriction when CDN unreachable + VPN active
    var isLikelyGeoBlocked: Bool {
        !cdnReachable && vpnActive
    }

    // Human-readable summary
    var summary: String {
        generateSummary()
    }

    private func generateSummary() -> String {
        // ISSUE 9 FIX: Check for geo-restriction before reporting connectivity failure
        if isLikelyGeoBlocked {
            return "\(platform.rawValue): Blocked (VPN IP detected by streaming service). Try switching VPN server region."
        }

        guard hasIssues else {
            return "Your \(platform.rawValue) streaming should work perfectly. Estimated quality: \(estimatedVideoQuality.description)."
        }

        var summary = ""

        switch primaryBottleneck {
        case .vpn:
            if let impact = vpnImpact {
                summary = "Your VPN is reducing streaming speed by \(Int(impact))%. "
                if let withVPN = throughputWithVPN, let withoutVPN = throughputWithoutVPN {
                    summary += "(\(String(format: "%.1f", withVPN)) Mbps → \(String(format: "%.1f", withoutVPN)) Mbps). "
                }
            } else {
                summary = "Your VPN is causing streaming issues. "
            }

        case .wifi:
            // FIXED: Don't mention WiFi signal - iOS cannot measure RSSI
            summary = "Local network issues detected affecting streaming. "

        case .router:
            summary = "Your router appears congested (inferred from throughput collapse). "
            if let devices = estimatedDeviceCount {
                summary += "Estimated ~\(devices) devices (based on network behavior, not directly counted). "
            } else {
                summary += "Device count cannot be directly measured on iOS. "
            }

        case .isp:
            summary = "Your ISP is experiencing congestion. "
            if let pattern = historicalCongestionPattern {
                summary += pattern + " "
            }

        case .cdn:
            summary = "\(platform.rawValue) is routing you to a distant server. "
            if let region = cdnRegion {
                summary += "Connected to: \(region). "
            }
            if cdnPing > 0 {
                summary += "Latency: \(Int(cdnPing))ms. "
            }

        case .dns:
            summary = "DNS resolution is slow (\(Int(dnsLatency))ms). "

        case .device:
            summary = "Your device may have limitations affecting streaming. "

        case .none:
            summary = "No issues detected. "
        }

        return summary
    }
}
