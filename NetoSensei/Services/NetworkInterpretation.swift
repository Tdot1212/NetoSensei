//
//  NetworkInterpretation.swift
//  NetoSensei
//
//  Single source of truth for ALL network status messages.
//  Every screen reads from this. No screen writes its own interpretation.
//  FIXES: "Router Unreachable" vs "359ms green checkmark" contradiction
//  FIXES: "WiFi disconnected" when WiFi is connected
//

import Foundation
import SwiftUI

// MARK: - Interpretation Result

struct NetworkInterpretation {
    let overallStatus: InterpretedStatus
    let healthScore: Int
    let rootCause: RootCause
    let summaryItems: [SummaryItem]
    let testResults: [TestResult]
    let recommendations: [InterpretedRecommendation]

    // Individual component statuses
    let wifi: ComponentStatus
    let router: ComponentStatus
    let internet: ComponentStatus
    let vpn: ComponentStatus
    let dns: ComponentStatus
    let isp: ComponentStatus

    // Counts for UI display
    var passedCount: Int { testResults.filter { $0.passed }.count }
    var warningCount: Int { testResults.filter { !$0.passed && $0.statusColor == .orange }.count }
    var failedCount: Int { testResults.filter { !$0.passed && $0.statusColor == .red }.count }
    var issueCount: Int { warningCount + failedCount }
}

enum InterpretedStatus: String {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case critical = "Critical"

    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .green
        case .fair: return .orange
        case .poor: return .red
        case .critical: return .red
        }
    }

    var emoji: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🟢"
        case .fair: return "🟡"
        case .poor: return "🔴"
        case .critical: return "🔴"
        }
    }

    /// Convert to NetworkHealth for compatibility
    var asNetworkHealth: NetworkHealth {
        switch self {
        case .excellent, .good: return .excellent
        case .fair: return .fair
        case .poor, .critical: return .poor
        }
    }
}

struct ComponentStatus {
    let name: String
    let status: StatusLevel
    let value: String       // e.g. "234ms", "Active", "Connected"
    let detail: String      // Short explanation
    let color: Color

    enum StatusLevel: String {
        case good = "Good"
        case warning = "Warning"
        case bad = "Bad"
        case inactive = "Inactive"
        case hidden = "Hidden"  // For when VPN masks a test
    }

    /// Whether this component has an issue
    var hasIssue: Bool {
        status == .warning || status == .bad
    }
}

struct RootCause {
    let title: String          // e.g. "VPN Adds Latency"
    let description: String    // e.g. "Your VPN routes traffic through the US..."
    let severity: InterpretedStatus
    let icon: String           // SF Symbol name
}

struct SummaryItem: Identifiable, Hashable {
    let id = UUID()
    let emoji: String
    let title: String
    let explanation: String
    let priority: Int  // 1 = highest

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SummaryItem, rhs: SummaryItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct TestResult: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let passed: Bool
    let statusColor: Color
    let icon: String
    let detail: String
}

struct InterpretedRecommendation: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let priority: Int
    let actionable: Bool  // true = user can do something about it
}

// MARK: - The Interpretation Engine

@MainActor
class NetworkInterpreter: ObservableObject {
    static let shared = NetworkInterpreter()

    @Published var current: NetworkInterpretation?

    /// Timestamp of last interpretation
    @Published var lastInterpretedAt: Date?

    private init() {}

    /// Interpret network data - call this ONCE after each diagnostic or refresh.
    /// All screens read from `current` - never compute their own text.
    func interpret(
        gatewayLatency: Double?,
        gatewayReachable: Bool,
        externalLatency: Double?,
        externalReachable: Bool,
        dnsLatency: Double?,
        dnsReachable: Bool,
        httpSuccess: Bool,
        vpnActive: Bool,
        vpnServerLocation: String?,
        vpnIP: String?,
        ispLatency: Double?,
        ispReachable: Bool,
        wifiConnected: Bool,
        ssid: String?,
        publicIP: String?,
        isp: String?
    ) -> NetworkInterpretation {

        // ========================================
        // RULE 1: Determine VPN overhead FIRST
        // This affects how we interpret ALL other latency values
        // ========================================

        var vpnOverhead: Double = 0
        if vpnActive, let ext = externalLatency, let gw = gatewayLatency {
            vpnOverhead = max(0, ext - gw)
        } else if vpnActive, let ext = externalLatency {
            // If we can't measure gateway, estimate VPN overhead from external latency
            // Assume 30ms baseline without VPN
            vpnOverhead = max(0, ext - 30)
        }

        // ========================================
        // RULE 2: Adjust thresholds when VPN is active
        // VPN adds 100-300ms latency - that's EXPECTED, not a problem
        // ========================================

        let gatewayThresholdGood: Double = vpnActive ? 100 : 20
        let gatewayThresholdFair: Double = vpnActive ? 300 : 50
        let externalThresholdGood: Double = vpnActive ? 400 : 100
        let externalThresholdFair: Double = vpnActive ? 800 : 300
        let dnsThresholdGood: Double = 50
        let dnsThresholdFair: Double = 150
        let ispThresholdGood: Double = vpnActive ? 400 : 100
        let ispThresholdFair: Double = vpnActive ? 800 : 300

        // ========================================
        // RULE 3: Interpret each component
        // ========================================

        // --- WiFi ---
        let wifi: ComponentStatus
        if wifiConnected {
            wifi = ComponentStatus(
                name: "WiFi",
                status: .good,
                value: ssid != nil ? "Connected (\(ssid!))" : "Connected",
                detail: ssid == nil ? "SSID requires Location permission" : "WiFi connected",
                color: .green
            )
        } else {
            wifi = ComponentStatus(
                name: "WiFi", status: .bad,
                value: "Disconnected",
                detail: "Not connected to WiFi",
                color: .red
            )
        }

        // --- Router/Gateway ---
        // FIX (Issue 2): treat a real (non-sentinel) gateway latency measurement as
        // proof of reachability. The plumbing sometimes leaves `gatewayReachable`
        // false (timeout fallback path) even though the live latency was measured.
        let router: ComponentStatus
        let routerHasMeasuredLatency = LatencyValidation.normalize(gatewayLatency) != nil
        let routerReachableEffective = gatewayReachable || routerHasMeasuredLatency
        if let gw = LatencyValidation.normalize(gatewayLatency), routerReachableEffective {
            if gw < gatewayThresholdGood {
                router = ComponentStatus(
                    name: "Router", status: .good,
                    value: "\(Int(gw))ms",
                    detail: vpnActive ? "Good (measured through VPN)" : "Fast connection to router",
                    color: .green
                )
            } else if gw < gatewayThresholdFair {
                router = ComponentStatus(
                    name: "Router", status: .warning,
                    value: "\(Int(gw))ms",
                    detail: vpnActive ? "Elevated - VPN adds overhead" : "Slightly slow - move closer to router",
                    color: .orange
                )
            } else {
                router = ComponentStatus(
                    name: "Router", status: .bad,
                    value: "\(Int(gw))ms",
                    detail: vpnActive ? "Slow - mostly VPN overhead, not WiFi" : "Slow - WiFi signal may be weak",
                    color: .red
                )
            }
        } else if vpnActive {
            // CRITICAL FIX: VPN blocks local network -> router test fails
            // This is EXPECTED and NOT a WiFi problem
            router = ComponentStatus(
                name: "Router", status: .hidden,
                value: "Hidden by VPN",
                detail: "VPN blocks router access - this is normal",
                color: .gray
            )
        } else {
            router = ComponentStatus(
                name: "Router", status: .bad,
                value: "Unreachable",
                detail: "Cannot reach router - check WiFi connection",
                color: .red
            )
        }

        // --- Internet ---
        let internet: ComponentStatus
        if let ext = externalLatency, externalReachable {
            if ext < externalThresholdGood {
                internet = ComponentStatus(
                    name: "Internet", status: .good,
                    value: "\(Int(ext))ms",
                    detail: vpnActive ? "Good (includes \(Int(vpnOverhead))ms VPN overhead)" : "Fast internet connection",
                    color: .green
                )
            } else if ext < externalThresholdFair {
                internet = ComponentStatus(
                    name: "Internet", status: .warning,
                    value: "\(Int(ext))ms",
                    detail: vpnActive ? "VPN adds ~\(Int(vpnOverhead))ms - try a closer server" : "Moderate latency",
                    color: .orange
                )
            } else {
                internet = ComponentStatus(
                    name: "Internet", status: .bad,
                    value: "\(Int(ext))ms",
                    detail: vpnActive ? "Slow - VPN adds ~\(Int(vpnOverhead))ms overhead" : "High latency - possible ISP issue",
                    color: .red
                )
            }
        } else {
            internet = ComponentStatus(
                name: "Internet", status: .bad,
                value: "No connection",
                detail: "Cannot reach external servers",
                color: .red
            )
        }

        // --- VPN ---
        let vpn: ComponentStatus
        if vpnActive {
            if vpnOverhead < 100 {
                vpn = ComponentStatus(
                    name: "VPN", status: .good,
                    value: "Active",
                    detail: "Low overhead (\(Int(vpnOverhead))ms) - great setup",
                    color: .green
                )
            } else if vpnOverhead < 250 {
                vpn = ComponentStatus(
                    name: "VPN", status: .warning,
                    value: "Active",
                    detail: "Moderate overhead (\(Int(vpnOverhead))ms)",
                    color: .orange
                )
            } else {
                vpn = ComponentStatus(
                    name: "VPN", status: .bad,
                    value: "Active (slow)",
                    detail: "High overhead (\(Int(vpnOverhead))ms) - try a closer server",
                    color: .red
                )
            }
        } else {
            vpn = ComponentStatus(
                name: "VPN", status: .inactive,
                value: "Inactive",
                detail: "No VPN detected",
                color: .gray
            )
        }

        // --- DNS ---
        // FIX (Issue 3): only display real DNS latency. A 999 sentinel must
        // be reported as "data unavailable", not as a 999ms result.
        let dns: ComponentStatus
        if let dnsLat = LatencyValidation.normalize(dnsLatency), dnsReachable {
            if dnsLat < dnsThresholdGood {
                dns = ComponentStatus(
                    name: "DNS", status: .good,
                    value: "\(Int(dnsLat))ms",
                    detail: "Fast DNS resolution",
                    color: .green
                )
            } else if dnsLat < dnsThresholdFair {
                dns = ComponentStatus(
                    name: "DNS", status: .warning,
                    value: "\(Int(dnsLat))ms",
                    detail: "Slow - consider switching to 1.1.1.1 or 8.8.8.8",
                    color: .orange
                )
            } else {
                dns = ComponentStatus(
                    name: "DNS", status: .bad,
                    value: "\(Int(dnsLat))ms",
                    detail: "Very slow - switch DNS to 1.1.1.1 for faster browsing",
                    color: .red
                )
            }
        } else if dnsReachable {
            // We have a reachable DNS but no real latency — mark as unavailable,
            // not a hard failure. (Browsing clearly works, otherwise the page that
            // loaded the dashboard wouldn't have loaded.)
            dns = ComponentStatus(
                name: "DNS", status: .good,
                value: "OK",
                detail: "DNS resolves; latency unavailable",
                color: .green
            )
        } else {
            dns = ComponentStatus(
                name: "DNS", status: .bad,
                value: "Check failed",
                detail: "DNS check failed — measurement unavailable",
                color: .red
            )
        }

        // --- ISP ---
        let ispStatus: ComponentStatus
        if let ispLat = ispLatency, ispReachable {
            if ispLat < ispThresholdGood {
                ispStatus = ComponentStatus(
                    name: "ISP", status: .good,
                    value: "\(Int(ispLat))ms",
                    detail: "ISP performing well",
                    color: .green
                )
            } else if ispLat < ispThresholdFair {
                ispStatus = ComponentStatus(
                    name: "ISP", status: .warning,
                    value: "\(Int(ispLat))ms",
                    detail: vpnActive ? "Includes VPN overhead" : "ISP somewhat slow",
                    color: .orange
                )
            } else {
                ispStatus = ComponentStatus(
                    name: "ISP", status: .bad,
                    value: "\(Int(ispLat))ms",
                    detail: vpnActive ? "Mostly VPN overhead, not ISP" : "ISP congestion detected",
                    color: .red
                )
            }
        } else {
            ispStatus = ComponentStatus(
                name: "ISP", status: .bad,
                value: "Unreachable",
                detail: "Could not reach ISP test servers",
                color: .red
            )
        }

        // ========================================
        // RULE 4: Calculate health score
        // ========================================

        var score = 100

        // WiFi (max -20)
        if !wifiConnected { score -= 20 }

        // Router (max -20, but reduce penalty when VPN masks it)
        if !gatewayReachable && !vpnActive { score -= 20 }
        else if !gatewayReachable && vpnActive { score -= 5 } // VPN expected to mask router
        else if let gw = gatewayLatency {
            if gw > gatewayThresholdFair { score -= 15 }
            else if gw > gatewayThresholdGood { score -= 5 }
        }

        // Internet (max -25)
        if !externalReachable { score -= 25 }
        else if let ext = externalLatency {
            if ext > externalThresholdFair { score -= 20 }
            else if ext > externalThresholdGood { score -= 10 }
        }

        // DNS (max -15)
        if !dnsReachable { score -= 15 }
        else if let d = dnsLatency {
            if d > dnsThresholdFair { score -= 10 }
            else if d > dnsThresholdGood { score -= 5 }
        }

        // ISP (max -15)
        if !ispReachable && !vpnActive { score -= 15 }
        else if !ispReachable && vpnActive { score -= 5 }
        else if let i = ispLatency {
            if i > ispThresholdFair { score -= 10 }
            else if i > ispThresholdGood { score -= 5 }
        }

        // VPN overhead penalty (max -10)
        if vpnActive && vpnOverhead > 250 { score -= 10 }
        else if vpnActive && vpnOverhead > 150 { score -= 5 }

        score = max(0, min(100, score))

        // ========================================
        // RULE 5: Determine overall status from score
        // ========================================

        let overallStatus: InterpretedStatus
        if score >= 80 { overallStatus = .excellent }
        else if score >= 60 { overallStatus = .good }
        else if score >= 40 { overallStatus = .fair }
        else if score >= 20 { overallStatus = .poor }
        else { overallStatus = .critical }

        // ========================================
        // RULE 6: Determine ROOT CAUSE
        // Priority order: no internet > no WiFi > VPN slow > gateway slow > DNS slow > ISP slow
        // ========================================

        let rootCause: RootCause

        if !externalReachable && !httpSuccess {
            rootCause = RootCause(
                title: "No Internet Connection",
                description: "Cannot reach any external servers. Check your WiFi and router.",
                severity: .critical,
                icon: "wifi.slash"
            )
        } else if !wifiConnected {
            rootCause = RootCause(
                title: "WiFi Disconnected",
                description: "You're not connected to a WiFi network.",
                severity: .critical,
                icon: "wifi.exclamationmark"
            )
        } else if vpnActive && vpnOverhead > 250 {
            rootCause = RootCause(
                title: "VPN Is Slow",
                description: "Your VPN adds \(Int(vpnOverhead))ms of delay. Try connecting to a server closer to your location in your VPN app.",
                severity: .poor,
                icon: "lock.trianglebadge.exclamationmark"
            )
        } else if vpnActive && vpnOverhead > 100 {
            rootCause = RootCause(
                title: "Moderate VPN Overhead",
                description: "Your VPN adds \(Int(vpnOverhead))ms. This is normal for international VPN connections. A closer server could help.",
                severity: .fair,
                icon: "lock.shield"
            )
        } else if let gw = LatencyValidation.normalize(gatewayLatency), gw > 100 && !vpnActive {
            rootCause = RootCause(
                title: "Weak WiFi Connection",
                description: "Your router responds slowly (\(Int(gw))ms). Move closer to your router or reduce connected devices.",
                severity: .poor,
                icon: "wifi.exclamationmark"
            )
        } else if let d = LatencyValidation.normalize(dnsLatency), d > 300 {
            // FIX (Issue 3): only diagnose "Slow DNS" from a real measurement.
            rootCause = RootCause(
                title: "Slow DNS",
                description: "Website lookups take \(Int(d))ms. Change your DNS server to 1.1.1.1 or 8.8.8.8 for faster browsing.",
                severity: .fair,
                icon: "server.rack"
            )
        } else if let i = LatencyValidation.normalize(ispLatency), i > 300 && !vpnActive {
            rootCause = RootCause(
                title: "ISP Congestion",
                description: "Your internet provider's network is slow (\(Int(i))ms). This is usually temporary.",
                severity: .fair,
                icon: "antenna.radiowaves.left.and.right"
            )
        } else if vpnActive {
            rootCause = RootCause(
                title: "VPN Connected",
                description: "Your network is working through VPN with \(Int(vpnOverhead))ms overhead. Everything looks normal.",
                severity: overallStatus,
                icon: "lock.shield.fill"
            )
        } else {
            rootCause = RootCause(
                title: "Network Healthy",
                description: "All systems working normally.",
                severity: .excellent,
                icon: "checkmark.shield.fill"
            )
        }

        // ========================================
        // RULE 7: Build test results (for diagnostic screen)
        // ========================================

        var testResults: [TestResult] = []

        testResults.append(TestResult(
            name: "Router/Gateway",
            value: router.value,
            passed: router.status == .good || router.status == .hidden,
            statusColor: router.color,
            icon: "wifi.router",
            detail: router.detail
        ))
        testResults.append(TestResult(
            name: "External Connectivity",
            value: internet.value,
            passed: internet.status == .good,
            statusColor: internet.color,
            icon: "globe",
            detail: internet.detail
        ))
        testResults.append(TestResult(
            name: "DNS Resolution",
            value: dns.value,
            passed: dns.status == .good,
            statusColor: dns.color,
            icon: "server.rack",
            detail: dns.detail
        ))
        testResults.append(TestResult(
            name: "HTTP Connectivity",
            value: httpSuccess ? "OK" : "Failed",
            passed: httpSuccess,
            statusColor: httpSuccess ? .green : .red,
            icon: "globe.americas",
            detail: httpSuccess ? "HTTP requests working" : "HTTP requests failed"
        ))
        testResults.append(TestResult(
            name: "VPN Tunnel",
            value: vpn.value,
            passed: !vpnActive || vpn.status == .good,
            statusColor: vpnActive ? vpn.color : .gray,
            icon: "lock.shield",
            detail: vpn.detail
        ))
        testResults.append(TestResult(
            name: "ISP Performance",
            value: ispStatus.value,
            passed: ispStatus.status == .good,
            statusColor: ispStatus.color,
            icon: "antenna.radiowaves.left.and.right",
            detail: ispStatus.detail
        ))

        // ========================================
        // RULE 8: Build recommendations
        // ========================================

        var recommendations: [InterpretedRecommendation] = []

        if vpnActive && vpnOverhead > 150 {
            recommendations.append(InterpretedRecommendation(
                icon: "lock.rotation",
                title: "Switch VPN Server",
                description: "Your VPN adds \(Int(vpnOverhead))ms. Try a server closer to \(vpnServerLocation ?? "your location").",
                priority: 1,
                actionable: true
            ))
        }

        // FIX (Issue 3/6): only generate from REAL measurements. Sentinel values
        // like 999 (timed out / failed) must never produce "Your DNS takes 999ms"
        // recommendations. Same for the gateway recommendation below.
        if let d = LatencyValidation.normalize(dnsLatency), dnsReachable, d > 300 {
            recommendations.append(InterpretedRecommendation(
                icon: "server.rack",
                title: "Switch to Faster DNS",
                description: "Your DNS takes \(Int(d))ms. Change to 1.1.1.1 or 8.8.8.8 in WiFi settings.",
                priority: 2,
                actionable: true
            ))
        }

        if let gw = LatencyValidation.normalize(gatewayLatency), gatewayReachable, gw > 50, !vpnActive {
            recommendations.append(InterpretedRecommendation(
                icon: "wifi",
                title: "Improve WiFi Signal",
                description: "Router latency is \(Int(gw))ms. Move closer to your router or reduce nearby interference.",
                priority: 3,
                actionable: true
            ))
        }

        if score >= 70 {
            recommendations.append(InterpretedRecommendation(
                icon: "checkmark.circle",
                title: "Looking Good",
                description: "Your network is performing well. No changes needed right now.",
                priority: 99,
                actionable: false
            ))
        }

        // ========================================
        // RULE 9: Build plain-English summary
        // ========================================

        var summaryItems: [SummaryItem] = []

        // Overall
        if score >= 70 {
            summaryItems.append(SummaryItem(
                emoji: "✅", title: "Your internet is working well",
                explanation: "Browsing, streaming, and video calls should all work fine.",
                priority: 1
            ))
        } else if score >= 40 {
            summaryItems.append(SummaryItem(
                emoji: "⚠️", title: "Your internet is okay but could be better",
                explanation: "Basic browsing works but videos might buffer and video calls could lag.",
                priority: 1
            ))
        } else {
            summaryItems.append(SummaryItem(
                emoji: "🔴", title: "Your internet has problems right now",
                explanation: "You'll notice slow loading, buffering, and possible disconnections.",
                priority: 1
            ))
        }

        // VPN explanation
        if vpnActive {
            if vpnOverhead > 200 {
                summaryItems.append(SummaryItem(
                    emoji: "🐢", title: "VPN is slowing things down",
                    explanation: "Your VPN adds \(Int(vpnOverhead))ms delay. Switch to a closer server in your VPN app for better speed.",
                    priority: 2
                ))
            } else {
                summaryItems.append(SummaryItem(
                    emoji: "🔒", title: "VPN is working",
                    explanation: "Connected through \(vpnServerLocation ?? "VPN") with \(Int(vpnOverhead))ms overhead. This is normal.",
                    priority: 3
                ))
            }
        }

        // Top actionable tip
        if let topRec = recommendations.filter({ $0.actionable }).sorted(by: { $0.priority < $1.priority }).first {
            summaryItems.append(SummaryItem(
                emoji: "💡", title: topRec.title,
                explanation: topRec.description,
                priority: 10
            ))
        }

        let interpretation = NetworkInterpretation(
            overallStatus: overallStatus,
            healthScore: score,
            rootCause: rootCause,
            summaryItems: summaryItems.sorted { $0.priority < $1.priority },
            testResults: testResults,
            recommendations: recommendations.sorted { $0.priority < $1.priority },
            wifi: wifi,
            router: router,
            internet: internet,
            vpn: vpn,
            dns: dns,
            isp: ispStatus
        )

        current = interpretation
        lastInterpretedAt = Date()

        print("🧠 NetworkInterpreter: Score=\(score), RootCause=\(rootCause.title), VPNActive=\(vpnActive), VPNOverhead=\(Int(vpnOverhead))ms")

        return interpretation
    }

    /// Quick interpretation from current NetworkStatus (for dashboard refresh)
    func interpretFromStatus(_ status: NetworkStatus) -> NetworkInterpretation {
        let vpnResult = SmartVPNDetector.shared.detectionResult
        let vpnActive = vpnResult?.isVPNActive ?? false

        return interpret(
            gatewayLatency: status.router.latency,
            gatewayReachable: status.router.isReachable,
            externalLatency: status.internet.latencyToExternal,
            externalReachable: status.internet.isReachable,
            dnsLatency: status.dns.latency,
            dnsReachable: status.dns.latency != nil,
            httpSuccess: status.internet.isReachable,
            vpnActive: vpnActive,
            vpnServerLocation: vpnResult?.publicCity ?? vpnResult?.publicCountry,
            vpnIP: vpnResult?.publicIP,
            ispLatency: status.internet.latencyToExternal,  // Use external as ISP proxy
            ispReachable: status.internet.isReachable,
            wifiConnected: status.wifi.isConnected,
            ssid: status.wifi.ssid,
            publicIP: status.publicIP,
            isp: vpnResult?.publicISP
        )
    }
}
