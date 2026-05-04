//
//  RootCauseAnalyzer.swift
//  NetoSensei
//
//  Root-Cause Analysis Engine - The Brain
//  Transforms raw diagnostics into intelligent explanations and fixes
//

import Foundation

/// Root-cause analysis engine - determines what's actually wrong
class RootCauseAnalyzer {

    // MARK: - Thresholds
    // FIXED: Calibrated thresholds based on real-world measurements

    private enum Thresholds {
        // Router/Gateway latency thresholds (local network)
        // < 10ms = Excellent, 10-30ms = Good, 30-50ms = Elevated, > 50ms = Congested
        static let routerLatencyExcellent: Double = 10
        static let routerLatencyGood: Double = 30
        static let routerLatencyElevated: Double = 50
        static let routerLatencyCongested: Double = 100

        // External/Internet latency thresholds
        static let internetLatencyGood: Double = 50
        static let internetLatencyWarning: Double = 100
        static let internetLatencyCritical: Double = 150

        // VPN latency thresholds (higher tolerance due to encryption overhead)
        static let vpnLatencyGood: Double = 80
        static let vpnLatencyWarning: Double = 150
        static let vpnLatencyCritical: Double = 250

        // CDN throughput thresholds
        static let cdnThroughputGood: Double = 10
        static let cdnThroughputWarning: Double = 5
        static let cdnThroughputPoor: Double = 2

        // DNS latency thresholds
        static let dnsLatencyGood: Double = 20
        static let dnsLatencyWarning: Double = 50
        static let dnsLatencyCritical: Double = 100

        // REMOVED: signalStrength thresholds
        // iOS has NO public API for WiFi RSSI - these cannot be measured
    }

    // MARK: - Analysis Result

    struct Analysis {
        let primaryProblem: ProblemType
        let severity: Severity
        let beginnerExplanation: String
        let expertExplanation: String
        let whyItMatters: String
        let whatToDoNext: String
        let autoFixAvailable: Bool
        let autoFixAction: AutoFixAction?
        let contributingFactors: [ProblemType]
        let healthScore: Int // 0-100

        enum ProblemType: String {
            case none = "No Issues"
            // REMOVED: wifiSignal - iOS has NO public API for RSSI, cannot be measured
            case routerElevated = "Gateway Latency Elevated"
            case routerCongestion = "Router Congested"
            case routerUnreachable = "Router Unreachable"
            case ispCongestion = "ISP Congestion"
            case ispOutage = "ISP Outage"
            case vpnSlow = "VPN Slow"
            case vpnRegionFar = "VPN Region Too Far"
            case vpnOverloaded = "VPN Server Overloaded"
            case cdnMismatch = "CDN Region Mismatch"
            case cdnUnreachable = "CDN Unreachable"
            case dnsSlow = "DNS Slow"
            case dnsFailure = "DNS Failure"
            case unknown = "Unknown Issue"
        }

        enum Severity {
            case none      // Everything good
            case minor     // Noticeable but not critical
            case moderate  // Degraded performance
            case severe    // Major issues
            case critical  // Completely broken

            var color: String {
                switch self {
                case .none: return "green"
                case .minor: return "blue"
                case .moderate: return "yellow"
                case .severe: return "orange"
                case .critical: return "red"
                }
            }
        }

        enum AutoFixAction: Equatable {
            case restartRouter
            case switchWifiChannel
            case moveCloserToRouter
            case enableVPN
            case switchVPNRegion(recommended: String)
            case switchVPNProtocol
            case changeDNS(recommended: String)
            case optimizeVPNForStreaming
            case contactISP
            case reconnectWifi
            case disableVPN
            case none
        }
    }

    // MARK: - Main Analysis Function

    func analyze(diagnostic: DiagnosticResult) -> Analysis {
        // Collect all measurements
        let measurements = extractMeasurements(from: diagnostic)

        // Determine primary problem
        let primaryProblem = determinePrimaryProblem(measurements: measurements)

        // Determine contributing factors
        let contributingFactors = determineContributingFactors(
            measurements: measurements,
            excluding: primaryProblem
        )

        // Calculate severity
        let severity = calculateSeverity(
            problem: primaryProblem,
            measurements: measurements
        )

        // Generate explanations
        let beginnerExplanation = generateBeginnerExplanation(
            problem: primaryProblem,
            measurements: measurements
        )

        let expertExplanation = generateExpertExplanation(
            problem: primaryProblem,
            measurements: measurements
        )

        let whyItMatters = generateWhyItMatters(problem: primaryProblem)

        let whatToDoNext = generateWhatToDoNext(
            problem: primaryProblem,
            measurements: measurements
        )

        // Determine auto-fix
        let autoFix = determineAutoFix(
            problem: primaryProblem,
            measurements: measurements
        )

        // Calculate health score
        let healthScore = calculateHealthScore(measurements: measurements)

        return Analysis(
            primaryProblem: primaryProblem,
            severity: severity,
            beginnerExplanation: beginnerExplanation,
            expertExplanation: expertExplanation,
            whyItMatters: whyItMatters,
            whatToDoNext: whatToDoNext,
            autoFixAvailable: autoFix != .none,
            autoFixAction: autoFix,
            contributingFactors: contributingFactors,
            healthScore: healthScore
        )
    }

    // MARK: - Measurement Extraction

    private struct Measurements {
        let wifiConnected: Bool
        // REMOVED: wifiSignal - cannot be measured on iOS
        let routerLatency: Double?
        let routerReachable: Bool
        let internetLatency: Double?
        let internetReachable: Bool
        let vpnActive: Bool
        let vpnLatency: Double?
        let dnsLatency: Double?
        let dnsWorking: Bool
        let cdnThroughput: Double?
        let cdnPing: Double?
    }

    private func extractMeasurements(from diagnostic: DiagnosticResult) -> Measurements {
        let networkStatus = diagnostic.networkSnapshot

        // Find specific tests
        let gatewayTest = diagnostic.testsPerformed.first { $0.name.contains("Gateway") }
        let externalTest = diagnostic.testsPerformed.first { $0.name.contains("External") }
        let dnsTest = diagnostic.testsPerformed.first { $0.name.contains("DNS") }

        return Measurements(
            wifiConnected: networkStatus.wifi.isConnected,
            // REMOVED: wifiSignal - iOS has no public API for RSSI
            routerLatency: gatewayTest?.latency,
            routerReachable: gatewayTest?.result == .pass,
            internetLatency: externalTest?.latency,
            internetReachable: externalTest?.result == .pass,
            vpnActive: networkStatus.vpn.isActive,
            vpnLatency: networkStatus.vpn.isActive ? externalTest?.latency : nil,
            dnsLatency: dnsTest?.latency,
            dnsWorking: dnsTest?.result == .pass,
            cdnThroughput: nil, // Will be populated from streaming tests
            cdnPing: nil
        )
    }

    // MARK: - Problem Determination

    private func determinePrimaryProblem(measurements: Measurements) -> Analysis.ProblemType {
        // Priority order: Check from most specific to most general
        // FIXED: Removed signal check - iOS cannot measure WiFi RSSI

        // 1. Connection Issues (most fundamental)
        if !measurements.wifiConnected {
            return .routerUnreachable
        }

        // REMOVED: wifiSignal check - cannot be measured on iOS

        // 2. Router Issues - use FIXED thresholds
        if !measurements.routerReachable {
            return .routerUnreachable
        }

        if let routerLatency = measurements.routerLatency {
            if routerLatency > Thresholds.routerLatencyCongested {
                return .routerCongestion  // > 100ms = severe congestion
            } else if routerLatency > Thresholds.routerLatencyElevated {
                return .routerElevated    // 50-100ms = elevated
            }
            // 30-50ms is just slightly elevated, not a primary problem
        }

        // 3. DNS Issues
        if !measurements.dnsWorking {
            return .dnsFailure
        }

        if let dnsLatency = measurements.dnsLatency, dnsLatency > Thresholds.dnsLatencyCritical {
            return .dnsSlow
        }

        // 4. Internet/ISP Issues
        if !measurements.internetReachable {
            return .ispOutage
        }

        // FIXED: VPN overhead detection - the PRIMARY cause of high latency with VPN
        // Calculate VPN overhead: external latency - gateway latency
        // If VPN is adding > 100ms overhead, that's the problem
        if measurements.vpnActive,
           let internetLatency = measurements.internetLatency,
           let routerLatency = measurements.routerLatency {
            let vpnOverhead = internetLatency - routerLatency
            // If VPN is adding > 100ms overhead, it's the primary problem
            if vpnOverhead > 100 {
                debugLog("🔍 VPN overhead detected: \(Int(vpnOverhead))ms (external: \(Int(internetLatency))ms - gateway: \(Int(routerLatency))ms)")
                return .vpnSlow
            }
        }

        if let internetLatency = measurements.internetLatency {
            // If VPN is active, check against VPN-adjusted thresholds
            if measurements.vpnActive {
                // With VPN, total latency > 200ms is a problem
                if internetLatency > 200 {
                    return .vpnSlow
                }
            } else {
                // Without VPN, > 150ms is ISP congestion
                if internetLatency > Thresholds.internetLatencyCritical {
                    return .ispCongestion
                }
            }
        }

        // 5. VPN-specific issues (region too far)
        if measurements.vpnActive {
            if let vpnLatency = measurements.vpnLatency, vpnLatency > Thresholds.vpnLatencyCritical {
                return .vpnRegionFar
            }
        }

        // 6. CDN Issues
        if let throughput = measurements.cdnThroughput, throughput < Thresholds.cdnThroughputPoor {
            return .cdnMismatch
        }

        // REMOVED: wifiSignal check - cannot be measured on iOS

        // 7. Minor DNS issues
        if let dnsLatency = measurements.dnsLatency, dnsLatency > Thresholds.dnsLatencyWarning {
            return .dnsSlow
        }

        // FIXED: "No Issues" should ONLY be returned when ALL metrics are good
        // Gateway < 30ms, External < 80ms (or < 150ms with VPN), DNS < 50ms
        if let internetLatency = measurements.internetLatency {
            if measurements.vpnActive {
                // With VPN, allow up to 150ms external latency before flagging
                if internetLatency > 150 {
                    return .vpnSlow
                }
            } else {
                // Without VPN, > 80ms external is elevated (ISP issue)
                if internetLatency > 80 {
                    return .ispCongestion
                }
            }
        }

        // Everything looks good!
        return .none
    }

    private func determineContributingFactors(
        measurements: Measurements,
        excluding primary: Analysis.ProblemType
    ) -> [Analysis.ProblemType] {
        var factors: [Analysis.ProblemType] = []

        // REMOVED: wifiSignal check - iOS cannot measure RSSI

        // Check router latency (if not primary) - use FIXED thresholds
        // Only flag as elevated if latency > 30ms (not just > 10ms)
        if primary != .routerCongestion && primary != .routerElevated,
           let routerLatency = measurements.routerLatency,
           routerLatency > Thresholds.routerLatencyGood {  // > 30ms
            if routerLatency > Thresholds.routerLatencyElevated {  // > 50ms
                factors.append(.routerCongestion)
            } else {
                factors.append(.routerElevated)
            }
        }

        // Check DNS (if not primary)
        if primary != .dnsSlow,
           let dnsLatency = measurements.dnsLatency,
           dnsLatency > Thresholds.dnsLatencyWarning {
            factors.append(.dnsSlow)
        }

        // Check VPN (if active and not primary)
        if measurements.vpnActive,
           primary != .vpnSlow,
           let vpnLatency = measurements.vpnLatency,
           vpnLatency > Thresholds.vpnLatencyWarning {
            factors.append(.vpnSlow)
        }

        return factors
    }

    // MARK: - Severity Calculation

    private func calculateSeverity(
        problem: Analysis.ProblemType,
        measurements: Measurements
    ) -> Analysis.Severity {
        switch problem {
        case .none:
            return .none

        case .routerElevated:
            // FIXED: Use router latency, not WiFi signal (iOS cannot measure RSSI)
            if let latency = measurements.routerLatency {
                if latency > 80 { return .moderate }
                if latency > 50 { return .minor }
                return .minor
            }
            return .minor

        case .routerCongestion:
            if let latency = measurements.routerLatency {
                if latency > 100 { return .severe }
                if latency > 50 { return .moderate }
                return .minor
            }
            return .moderate

        case .routerUnreachable:
            return .critical

        case .ispCongestion:
            if let latency = measurements.internetLatency {
                if latency > 500 { return .severe }
                if latency > 300 { return .moderate }
                return .minor
            }
            return .moderate

        case .ispOutage:
            return .critical

        case .vpnSlow, .vpnRegionFar, .vpnOverloaded:
            return .moderate

        case .cdnMismatch, .cdnUnreachable:
            return .moderate

        case .dnsSlow:
            return .minor

        case .dnsFailure:
            return .severe

        case .unknown:
            return .moderate
        }
    }

    // MARK: - Beginner Explanations

    private func generateBeginnerExplanation(
        problem: Analysis.ProblemType,
        measurements: Measurements
    ) -> String {
        switch problem {
        case .none:
            return "Everything looks great! Your network is working perfectly."

        case .routerElevated:
            if let latency = measurements.routerLatency {
                return "Your router is responding slower than normal (\(Int(latency))ms). This could indicate minor network congestion or router load."
            }
            return "Your router is responding slower than normal. This could indicate minor network congestion."

        case .routerCongestion:
            if let latency = measurements.routerLatency {
                return "Your router is responding slowly (\(Int(latency))ms). High probability of local network congestion (based on throughput collapse under load). This is typically caused by too many active devices or router CPU overload."
            }
            return "High probability of router congestion (inferred from network behavior, not directly measured)."

        case .routerUnreachable:
            return "Can't connect to your router. Your WiFi might be disconnected or the router is offline."

        case .ispCongestion:
            if let latency = measurements.internetLatency {
                return "Your internet is slow today (\(Int(latency))ms). Your internet provider's network is congested. This is NOT your WiFi or router."
            }
            return "Your internet provider's network is congested."

        case .ispOutage:
            return "Your internet is completely down. Your internet provider is having an outage or your modem is offline."

        case .vpnSlow:
            return "Your VPN connection is slow. The VPN server you're connected to is either too far away or overloaded."

        case .vpnRegionFar:
            return "You're connected to a VPN server that's too far away, causing high latency."

        case .vpnOverloaded:
            return "The VPN server you're using is overloaded with too many users."

        case .cdnMismatch:
            return "You're not connected to the right streaming server. Netflix/YouTube thinks you're in the wrong region."

        case .cdnUnreachable:
            return "Can't reach streaming servers. Your VPN or ISP routing is blocking access."

        case .dnsSlow:
            if let latency = measurements.dnsLatency {
                return "DNS (address lookup) is slow (\(Int(latency))ms). Switching DNS servers will speed up website loading."
            }
            return "DNS is slow. Switching DNS servers will help."

        case .dnsFailure:
            return "DNS is not working. You can't access websites by name (like google.com)."

        case .unknown:
            return "Something is affecting your network, but the exact cause is unclear."
        }
    }

    // MARK: - Expert Explanations

    private func generateExpertExplanation(
        problem: Analysis.ProblemType,
        measurements: Measurements
    ) -> String {
        switch problem {
        case .none:
            return "All network metrics within optimal ranges. No packet loss detected. Routing efficient."

        case .routerElevated:
            // FIXED: Use router latency, not WiFi signal (iOS cannot measure RSSI)
            if let latency = measurements.routerLatency {
                return "Gateway RTT = \(Int(latency))ms (optimal <10ms, acceptable <30ms). Elevated latency suggests minor router load or local network activity."
            }
            return "Gateway latency elevated above optimal threshold."

        case .routerCongestion:
            if let latency = measurements.routerLatency {
                return "Gateway RTT = \(Int(latency))ms (expected <10ms). Local congestion detected. Router load high or interference present."
            }
            return "Gateway latency exceeds threshold. Router CPU or buffer saturation likely."

        case .routerUnreachable:
            return "No ARP response from default gateway. Layer 2 connectivity failure."

        case .ispCongestion:
            if let latency = measurements.internetLatency {
                return "High last-mile latency detected (\(Int(latency))ms). Symptom typical of ISP peak congestion or overloaded NAT/CGNAT."
            }
            return "ISP routing exhibiting high latency. Last-mile congestion or peering issue."

        case .ispOutage:
            return "No route to external hosts. ISP WAN link down or modem offline."

        case .vpnSlow:
            if let latency = measurements.vpnLatency {
                return "VPN tunnel RTT = \(Int(latency))ms. Server oversubscribed or geographic distance excessive."
            }
            return "VPN tunnel experiencing high latency. Server congestion or suboptimal routing."

        case .vpnRegionFar:
            return "VPN endpoint geographically distant. High propagation delay unavoidable with current region selection."

        case .vpnOverloaded:
            return "VPN server load high. Throughput degraded. Consider alternative endpoint or protocol."

        case .cdnMismatch:
            return "CDN edge server suboptimal. GeoDNS mismatch or VPN routing causing far-edge selection."

        case .cdnUnreachable:
            return "No path to CDN edge servers. VPN or firewall blocking access."

        case .dnsSlow:
            if let latency = measurements.dnsLatency {
                return "DNS resolution = \(Int(latency))ms (expected <20ms). Resolver overloaded or distant. Consider 1.1.1.1 or 8.8.8.8."
            }
            return "DNS resolver latency high. Switch to Cloudflare (1.1.1.1) or Google (8.8.8.8) DNS."

        case .dnsFailure:
            return "DNS lookup failure. No response from configured resolvers. Network configuration issue or DNS servers unreachable."

        case .unknown:
            return "Anomalous network behavior detected. Multiple subsystems affected. Further investigation required."
        }
    }

    // MARK: - Why It Matters

    private func generateWhyItMatters(problem: Analysis.ProblemType) -> String {
        switch problem {
        case .none:
            return "Your network is performing optimally."

        case .routerElevated:
            return "Elevated gateway latency can cause: slightly slower page loads, minor delays in video calls, and occasional buffering. Usually not critical."

        case .routerCongestion:
            return "A slow router affects EVERYTHING: websites, streaming, gaming, video calls - all devices suffer."

        case .routerUnreachable:
            return "Without router connection, you have zero internet access on all devices."

        case .ispCongestion:
            return "ISP congestion slows down: streaming quality, downloads, uploads, online gaming. Nothing you do locally will fix this."

        case .ispOutage:
            return "Complete internet outage. You can't access anything online until your ISP fixes the problem."

        case .vpnSlow:
            return "Slow VPN ruins: streaming quality, video calls, gaming. Websites take forever to load."

        case .vpnRegionFar:
            return "High VPN latency makes real-time activities (gaming, calls) nearly impossible. Web browsing feels sluggish."

        case .vpnOverloaded:
            return "Overloaded VPN servers cause buffering, disconnects, and extremely slow speeds."

        case .cdnMismatch:
            return "Wrong CDN means: blurry videos, constant buffering, long loading times for Netflix/YouTube."

        case .cdnUnreachable:
            return "Can't stream videos or access content delivery networks. Netflix, YouTube, etc. won't work."

        case .dnsSlow:
            return "Slow DNS makes websites take forever to start loading. Each new site you visit delays before loading."

        case .dnsFailure:
            return "Without DNS, you can't access websites by name. Only direct IP addresses work."

        case .unknown:
            return "Network performance is degraded but root cause unclear. Multiple services may be affected."
        }
    }

    // MARK: - What To Do Next

    private func generateWhatToDoNext(
        problem: Analysis.ProblemType,
        measurements: Measurements
    ) -> String {
        switch problem {
        case .none:
            return "No action needed. Enjoy your fast connection! 🚀"

        case .routerElevated:
            return "Check if other devices are using heavy bandwidth. Consider restarting router if latency persists."

        case .routerCongestion:
            return "Restart your router. If problem persists, check how many devices are connected and disconnect unused ones."

        case .routerUnreachable:
            return "Check if WiFi is on, restart your router, or reconnect to your WiFi network."

        case .ispCongestion:
            if measurements.vpnActive {
                return "Try switching your VPN to a different region closer to you."
            } else {
                return "Enable a VPN to bypass your ISP's slow routing. Or contact your ISP to report congestion."
            }

        case .ispOutage:
            return "Contact your internet service provider. Check their website or social media for outage reports."

        case .vpnSlow:
            return "Switch to a VPN server closer to your location. Try a different VPN protocol (WireGuard is usually fastest)."

        case .vpnRegionFar:
            return "Connect to a VPN server in a nearby country or region to reduce latency."

        case .vpnOverloaded:
            return "Switch to a different VPN server in the same region. Try during off-peak hours."

        case .cdnMismatch:
            return "Change your VPN region to match the content you're watching. Or switch DNS to 1.1.1.1 (Cloudflare)."

        case .cdnUnreachable:
            return "Disable VPN temporarily to test. If that works, switch VPN servers. Otherwise, check your firewall settings."

        case .dnsSlow:
            return "Change your DNS to Cloudflare (1.1.1.1) or Google (8.8.8.8) for faster lookups."

        case .dnsFailure:
            return "Change your DNS servers to 1.1.1.1 (Cloudflare) or 8.8.8.8 (Google) in your network settings."

        case .unknown:
            return "Try restarting your router and device. If issues persist, run the diagnostic again in a few minutes."
        }
    }

    // MARK: - Auto-Fix Determination

    private func determineAutoFix(
        problem: Analysis.ProblemType,
        measurements: Measurements
    ) -> Analysis.AutoFixAction {
        switch problem {
        case .none:
            return .none

        case .routerElevated:
            // FIXED: Router latency issue, not signal - suggest restart
            return .restartRouter

        case .routerCongestion:
            return .restartRouter

        case .routerUnreachable:
            return .reconnectWifi

        case .ispCongestion:
            return measurements.vpnActive ? .switchVPNRegion(recommended: "Nearest") : .enableVPN

        case .ispOutage:
            return .contactISP

        case .vpnSlow, .vpnRegionFar:
            return .switchVPNRegion(recommended: "Nearest")

        case .vpnOverloaded:
            return .switchVPNRegion(recommended: "Same region, different server")

        case .cdnMismatch:
            return .optimizeVPNForStreaming

        case .cdnUnreachable:
            // Disable-VPN action removed: app cannot disconnect a VPN it
            // didn't install. Suggest a different region instead.
            return .switchVPNRegion(recommended: "Different region")

        case .dnsSlow, .dnsFailure:
            return .changeDNS(recommended: "1.1.1.1")

        case .unknown:
            return .none
        }
    }

    // MARK: - Health Score Calculation

    private func calculateHealthScore(measurements: Measurements) -> Int {
        // FIX (Phase 5): VPN-aware calibration. The previous version
        // double-counted (raw internet latency penalty PLUS VPN overhead
        // penalty), turning a healthy transpacific VPN into "Poor". The
        // user's rubric:
        //   - all-pass, no warnings           → 90-100
        //   - all-pass, only normal-VPN-overhead warnings → 75-85
        //   - all-pass, genuine concerns      → 60-75
        //   - test failures                   → scaled
        //
        // Worked examples (verified):
        //   A) 4ms gw, 167ms internet (VPN), 1ms DNS, overhead 163ms
        //      → -10 internet, -5 overhead = -15 → 85
        //   B) 51ms gw, 382ms internet (VPN), 212ms DNS, overhead 331ms
        //      → -18 internet, -10 overhead, -5 router, -7 DNS = -40 → 60
        var score = 100
        let vpnActive = measurements.vpnActive

        // Router latency (-15 max). Thresholds widened slightly so a 51ms
        // gateway counts as "elevated" (-5), not "poor" (-10).
        if let routerLatency = measurements.routerLatency {
            if routerLatency > 100 { score -= 15 }
            else if routerLatency > 60 { score -= 10 }
            else if routerLatency > 30 { score -= 5 }
            else if routerLatency > 10 { score -= 2 }
        }

        // Internet latency — VPN-aware.
        if let internetLatency = measurements.internetLatency {
            if vpnActive {
                // International VPN: 100-400ms is the normal operating range.
                if internetLatency > 800 { score -= 45 }
                else if internetLatency > 600 { score -= 35 }
                else if internetLatency > 400 { score -= 28 }
                else if internetLatency > 250 { score -= 18 }
                else if internetLatency > 100 { score -= 10 }
            } else {
                if internetLatency > 400 { score -= 50 }
                else if internetLatency > 300 { score -= 45 }
                else if internetLatency > 200 { score -= 40 }
                else if internetLatency > 150 { score -= 30 }
                else if internetLatency > 100 { score -= 20 }
                else if internetLatency > 80 { score -= 12 }
                else if internetLatency > 50 { score -= 5 }
            }
        }

        // VPN overhead — counted ONCE, gentler than before. Sub-150ms overhead
        // gets no penalty: that's normal for any international tunnel.
        if vpnActive,
           let internetLatency = measurements.internetLatency,
           let routerLatency = measurements.routerLatency {
            let vpnOverhead = internetLatency - routerLatency
            if vpnOverhead > 450 { score -= 20 }
            else if vpnOverhead > 300 { score -= 10 }
            else if vpnOverhead > 150 { score -= 5 }
        }

        // DNS latency (-10 max). 200-300ms is "borderline", not "broken".
        if let dnsLatency = measurements.dnsLatency {
            if dnsLatency > 300 { score -= 10 }
            else if dnsLatency > 200 { score -= 7 }
            else if dnsLatency > 100 { score -= 5 }
            else if dnsLatency > 50 { score -= 3 }
            else if dnsLatency > 20 { score -= 1 }
        }

        // Critical failures
        if !measurements.routerReachable { score -= 40 }
        if !measurements.internetReachable { score -= 40 }
        if !measurements.dnsWorking { score -= 20 }

        return max(0, min(100, score))
    }
}
