//
//  SmartRecommendationEngine.swift
//  NetoSensei
//
//  Generates specific, actionable recommendations based on measured diagnostic data
//

import Foundation

// MARK: - Recommendation Model

struct Recommendation: Identifiable {
    let id = UUID()
    let priority: Int           // 1 = highest
    let title: String           // "Switch VPN Server"
    let description: String     // "Your VPN server in Ashburn is adding 209ms..."
    let action: String?         // "Open VPN app and select Hong Kong server"
    let deepLink: String?       // "App-Prefs:WIFI" to open settings
    let category: Category

    enum Category: String, CaseIterable {
        case vpn = "VPN"
        case router = "Router/WiFi"
        case dns = "DNS"
        case isp = "ISP"
        case general = "General"

        var icon: String {
            switch self {
            case .vpn: return "lock.shield"
            case .router: return "wifi"
            case .dns: return "server.rack"
            case .isp: return "network"
            case .general: return "checkmark.circle"
            }
        }
    }
}

// MARK: - Smart Recommendation Engine

class SmartRecommendationEngine {
    static let shared = SmartRecommendationEngine()

    private init() {}

    func generateRecommendations(
        gatewayLatency: Double,      // ms
        externalLatency: Double,     // ms
        dnsLatency: Double,          // ms
        downloadSpeed: Double,       // Mbps
        uploadSpeed: Double,         // Mbps
        jitter: Double,              // ms
        packetLoss: Double,          // percentage
        vpnActive: Bool,
        vpnOverhead: Double?,        // ms
        vpnServerLocation: String?,  // "Ashburn, US"
        gatewayIP: String?,          // "192.168.150.1"
        gatewayValid: Bool = true,   // false ⇒ skip gateway-based recs (no real measurement)
        dnsValid: Bool = true,       // false ⇒ skip DNS-based recs (timeout/sentinel)
        externalValid: Bool = true   // false ⇒ skip ISP/external-based recs
    ) -> [Recommendation] {

        var recs: [Recommendation] = []

        // VPN recommendations
        if vpnActive, let overhead = vpnOverhead, overhead > 100 {
            let location = vpnServerLocation ?? "your current server"
            recs.append(Recommendation(
                priority: 1,
                title: "Switch VPN Server",
                description: "Your VPN server in \(location) is adding \(Int(overhead))ms latency. This is the #1 cause of your slow connection.",
                action: "Try a server closer to your physical location (Hong Kong, Singapore, or Japan would be faster from China).",
                deepLink: nil,
                category: .vpn
            ))

            if overhead > 200 {
                recs.append(Recommendation(
                    priority: 2,
                    title: "Try a Different VPN Protocol",
                    description: "With \(Int(overhead))ms overhead, your current VPN protocol may be inefficient. WireGuard is typically 30-50% faster than OpenVPN.",
                    action: "Check your VPN app settings for protocol options. WireGuard or IKEv2 are fastest.",
                    deepLink: nil,
                    category: .vpn
                ))
            }
        }

        // Gateway/Router recommendations
        // FIX (Issue 6): only act on REAL gateway measurements.
        if gatewayValid && gatewayLatency > 50 {
            let ip = gatewayIP ?? "your router"
            recs.append(Recommendation(
                priority: vpnActive ? 3 : 1,
                title: "Fix Your Router",
                description: "Your router (\(ip)) is responding slowly at \(Int(gatewayLatency))ms (should be under 10ms).",
                action: "1) Restart your router (unplug for 30 seconds)\n2) Check how many devices are connected\n3) Move closer to the router\n4) Check if someone is downloading large files",
                deepLink: nil,
                category: .router
            ))
        } else if gatewayValid && gatewayLatency > 15 {
            recs.append(Recommendation(
                priority: 5,
                title: "WiFi Could Be Better",
                description: "Gateway latency is \(Int(gatewayLatency))ms — acceptable but not ideal. Moving closer to your router or reducing connected devices could improve this.",
                action: nil,
                deepLink: nil,
                category: .router
            ))
        }

        // DNS recommendations
        // FIX (Issue 3 / 6): only recommend a DNS switch when we have a REAL
        // measurement above the threshold. 999/sentinel values must not generate
        // recommendations like "Your DNS takes 999ms to resolve."
        // Bumped threshold to 300ms per spec (was 50ms — too noisy).
        if dnsValid && dnsLatency > 300 {
            recs.append(Recommendation(
                priority: 2,
                title: "Switch to Faster DNS",
                description: "Your DNS takes \(Int(dnsLatency))ms to resolve. Switching DNS could improve page load times significantly.",
                action: "Go to Settings → Wi-Fi → tap (i) next to your network → Configure DNS → Manual → Add:\n• 1.1.1.1 (Cloudflare, typically 3-10ms)\n• 8.8.8.8 (Google)\n• 223.5.5.5 (Alibaba, good for China)",
                deepLink: "App-Prefs:WIFI",
                category: .dns
            ))
        }

        // Packet loss
        if packetLoss > 2 {
            recs.append(Recommendation(
                priority: 1,
                title: "Fix Packet Loss",
                description: "You're losing \(String(format: "%.1f", packetLoss))% of packets. This causes video stuttering, dropped calls, and slow page loads.",
                action: "Common causes:\n1) WiFi interference (microwaves, Bluetooth devices, neighboring networks)\n2) Too far from router\n3) Damaged ethernet cable (if wired)\n4) Router overloaded — restart it",
                deepLink: nil,
                category: .router
            ))
        }

        // ISP congestion (only if no VPN — with VPN, the overhead is from VPN not ISP)
        // FIX (Issue 6): require BOTH external and gateway to be real measurements.
        if externalValid && gatewayValid && !vpnActive && externalLatency > 100 && gatewayLatency < 30 {
            recs.append(Recommendation(
                priority: 1,
                title: "ISP Congestion Detected",
                description: "Your local network is fine (\(Int(gatewayLatency))ms to router) but internet latency is \(Int(externalLatency))ms. Your ISP is the bottleneck.",
                action: "Options:\n1) Enable a VPN to bypass ISP's slow routing\n2) Try again later (congestion often clears after peak hours)\n3) Contact your ISP to report slow speeds\n4) If persistent, consider switching ISP",
                deepLink: nil,
                category: .isp
            ))
        }

        // Jitter
        if jitter > 30 {
            recs.append(Recommendation(
                priority: 3,
                title: "Unstable Connection",
                description: "Your jitter is \(Int(jitter))ms (should be under 15ms). This causes inconsistent performance — sometimes fast, sometimes slow.",
                action: "This is often caused by WiFi congestion or an unstable VPN connection. Try connecting to the 5GHz WiFi band if available, or switch VPN servers.",
                deepLink: nil,
                category: .general
            ))
        }

        // Speed-specific advice
        if downloadSpeed < 5 && downloadSpeed > 0 {
            recs.append(Recommendation(
                priority: 1,
                title: "Very Slow Download Speed",
                description: "Your download speed (\(String(format: "%.1f", downloadSpeed)) Mbps) is too slow for HD streaming or video calls.",
                action: "Check: Is someone else using the network heavily? Is your VPN limiting bandwidth? Try a speed test without VPN to compare.",
                deepLink: nil,
                category: .general
            ))
        }

        // Upload speed (important for video calls)
        if uploadSpeed < 1 && uploadSpeed > 0 {
            recs.append(Recommendation(
                priority: 2,
                title: "Upload Speed Too Low",
                description: "Your upload speed (\(String(format: "%.1f", uploadSpeed)) Mbps) may cause issues with video calls and screen sharing.",
                action: "Upload speed affects sending video/audio. Try closing apps that upload in background (cloud sync, backups).",
                deepLink: nil,
                category: .general
            ))
        }

        // No issues
        if recs.isEmpty {
            recs.append(Recommendation(
                priority: 10,
                title: "All Good!",
                description: "Your network looks healthy. No issues detected.",
                action: nil,
                deepLink: nil,
                category: .general
            ))
        }

        return recs.sorted { $0.priority < $1.priority }
    }

    // MARK: - Generate from NetworkStatus

    @MainActor
    func generateRecommendations(from status: NetworkStatus, speedTest: SpeedTestResult? = nil, diagnosticResult: AdvancedDiagnosticSummary? = nil) -> [Recommendation] {
        // FIX (Issue 3/6): pull validated (non-sentinel) values, and pass validity
        // flags so the engine can skip recs that would be based on garbage data
        // (timeouts emit 999 sentinels — those must not become "Your DNS takes 999ms").
        let gatewayValid = status.router.displayableLatency != nil
        let externalValid = status.internet.displayableLatency != nil
        let dnsValid = status.dns.displayableLatency != nil

        let gatewayLatency = status.router.displayableLatency ?? 0
        let externalLatency = status.internet.displayableLatency ?? 0
        let dnsLatency = status.dns.displayableLatency ?? 0

        // Get speed test values
        let downloadSpeed = speedTest?.downloadSpeed ?? 0
        let uploadSpeed = speedTest?.uploadSpeed ?? 0
        let jitter = Double(diagnosticResult?.performanceMetrics?.jitter ?? 0)
        let packetLoss = diagnosticResult?.performanceMetrics?.packetLoss ?? 0

        // VPN info - use SmartVPNDetector as single source of truth
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        // Calculate VPN overhead as difference between tunnel latency and gateway latency
        let vpnOverhead: Double? = vpnActive && status.vpn.tunnelLatency != nil
            ? (status.vpn.tunnelLatency! - gatewayLatency)
            : nil
        let vpnServerLocation = status.vpn.serverLocation

        // Gateway IP
        let gatewayIP = status.router.gatewayIP

        return generateRecommendations(
            gatewayLatency: gatewayLatency,
            externalLatency: externalLatency,
            dnsLatency: dnsLatency,
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            jitter: jitter,
            packetLoss: packetLoss,
            vpnActive: vpnActive,
            vpnOverhead: vpnOverhead,
            vpnServerLocation: vpnServerLocation,
            gatewayIP: gatewayIP,
            gatewayValid: gatewayValid,
            dnsValid: dnsValid,
            externalValid: externalValid
        )
    }
}
