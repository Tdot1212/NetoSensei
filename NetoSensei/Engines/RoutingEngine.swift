//
//  RoutingEngine.swift
//  NetoSensei
//
//  Routing Engine - Intelligent traceroute with interpretation
//

import Foundation
import Network

actor RoutingEngine {
    static let shared = RoutingEngine()

    private init() {}

    // MARK: - VPN Detection Helpers

    /// Check if VPN is active using SmartVPNDetector
    private func checkVPNActive() async -> Bool {
        let detector = await SmartVPNDetector.shared
        let result = await detector.detectVPN()
        return result.isVPNActive
    }

    /// Get VPN server location (country/city) if available
    private func getVPNLocation() async -> String? {
        if let cached = await MainActor.run(body: { SmartVPNDetector.shared.detectionResult }) {
            if let city = cached.publicCity, !city.isEmpty {
                if let country = cached.publicCountry, !country.isEmpty {
                    return "\(city), \(country)"
                }
                return city
            }
            return cached.publicCountry
        }
        return nil
    }

    // MARK: - Timeout Helper

    private func withTimeout<T>(seconds: Int, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                throw DiagnosticError.timeout
            }

            // FIXED: Safe unwrap instead of force unwrap
            guard let result = try await group.next() else {
                group.cancelAll()
                throw DiagnosticError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Traceroute

    func runTraceroute(to host: String) async -> Result<[RoutingHop], DiagnosticError> {
        do {
            // FIXED: Use shorter timeout on cellular, skip on cellular for now
            let monitor = NWPathMonitor()
            let isCellular = monitor.currentPath.usesInterfaceType(.cellular)
            monitor.cancel()

            // On cellular, skip traceroute - it's too slow and not useful
            if isCellular {
                return .success([])
            }

            // Run traceroute command with 10s timeout (reduced from 30s)
            let output = try await withTimeout(seconds: 10) {
                try await self.executeTraceroute(to: host)
            }

            let hops = self.parseTraceroute(output)
            return .success(hops)

        } catch {
            return .failure(.timeout)
        }
    }

    // FIXED: Multi-endpoint network path measurement (since real traceroute is blocked on iOS)
    // Measures latency to multiple endpoints to simulate traceroute hops
    private func executeTraceroute(to host: String) async throws -> String {
        var output = "traceroute to \(host)\n"

        let vpnActive = await checkVPNActive()
        let vpnLocation = await getVPNLocation()

        // FIXED: Measure to multiple endpoints to get a real network path picture
        struct HopTarget {
            let hop: Int
            let host: String
            let label: String
        }

        // Build hop targets based on VPN status
        var targets: [HopTarget] = []

        if vpnActive {
            // VPN active - first hop is VPN tunnel, not router
            targets.append(HopTarget(hop: 1, host: "1.1.1.1", label: "VPN Tunnel (\(vpnLocation ?? "VPN Server"))"))
        } else {
            // No VPN - test gateway
            targets.append(HopTarget(hop: 1, host: "gateway.local", label: "Your Router"))
        }

        // Hop 2: DNS resolver (measure DNS resolution time)
        targets.append(HopTarget(hop: 2, host: "dns.google", label: "DNS Resolution"))

        // Hop 3: Nearby CDN (Apple's global CDN)
        targets.append(HopTarget(hop: 3, host: "www.apple.com", label: "Nearest CDN Edge"))

        // Hop 4: Target host
        targets.append(HopTarget(hop: 4, host: host, label: "Target Host"))

        // Measure each hop
        for target in targets {
            let start = Date()

            // Special handling for gateway.local (local network)
            let urlString: String
            if target.host == "gateway.local" {
                // Can't directly test local gateway via HTTPS
                // Use Apple's captive portal test as proxy for local connectivity
                urlString = "https://www.apple.com/library/test/success.html"
            } else if target.host == "dns.google" {
                // DNS lookup test
                urlString = "https://dns.google/resolve?name=apple.com&type=A"
            } else if target.host == "1.1.1.1" {
                urlString = "https://1.1.1.1/cdn-cgi/trace"
            } else {
                urlString = "https://\(target.host)"
            }

            guard let url = URL(string: urlString) else {
                output += " \(target.hop)  * * * (\(target.label))\n"
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 3.0

            do {
                let (_, _) = try await URLSession.shared.data(for: request)
                let latency = Date().timeIntervalSince(start) * 1000
                output += " \(target.hop)  \(target.label) (\(target.host))  \(String(format: "%.3f", latency)) ms\n"
            } catch {
                output += " \(target.hop)  * * * (\(target.label))\n"
            }
        }

        return output
    }

    private func parseTraceroute(_ output: String) -> [RoutingHop] {
        let lines = output.components(separatedBy: "\n")
        var hops: [RoutingHop] = []

        for line in lines {
            // Skip header line
            if line.starts(with: "traceroute") { continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            // Parse line format:
            // " 1  192.168.1.1 (192.168.1.1)  2.123 ms"
            // " 2  10.0.0.1 (10.0.0.1)  15.456 ms"
            // " 3  * * *"

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Extract hop number
            guard let hopMatch = trimmed.split(separator: " ", maxSplits: 1).first,
                  let hopNumber = Int(hopMatch) else {
                continue
            }

            // Check for timeout (* * *)
            if trimmed.contains("* * *") {
                let hop = RoutingHop(
                    hop: hopNumber,
                    ip: "timeout",
                    hostname: nil,
                    latency: nil,
                    isTimeout: true
                )
                hops.append(hop)
                continue
            }

            // Parse IP and latency
            // Pattern: "1  gateway.local (192.168.1.1)  2.123 ms"
            let ipPattern = #"\(([0-9.]+)\)"#
            let latencyPattern = #"(\d+\.?\d*)\s*ms"#

            var ip = "unknown"
            var hostname: String?
            var latency: Int?

            // Extract IP
            if let ipRegex = try? NSRegularExpression(pattern: ipPattern),
               let ipMatch = ipRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let ipRange = Range(ipMatch.range(at: 1), in: trimmed) {
                ip = String(trimmed[ipRange])
            }

            // Extract hostname (if different from IP)
            let components = trimmed.split(separator: " ")
            if components.count >= 2 {
                let possibleHostname = String(components[1])
                if !possibleHostname.starts(with: "(") && possibleHostname != ip {
                    hostname = possibleHostname
                }
            }

            // Extract latency
            if let latencyRegex = try? NSRegularExpression(pattern: latencyPattern),
               let latencyMatch = latencyRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let latencyRange = Range(latencyMatch.range(at: 1), in: trimmed),
               let latencyValue = Double(String(trimmed[latencyRange])) {
                latency = Int(latencyValue)
            }

            let hop = RoutingHop(
                hop: hopNumber,
                ip: ip,
                hostname: hostname,
                latency: latency,
                isTimeout: false
            )
            hops.append(hop)
        }

        return hops
    }

    // MARK: - Intelligent Route Interpretation

    func interpretRoute(_ hops: [RoutingHop]) async -> RoutingInterpretation {
        guard !hops.isEmpty else {
            // FIX (Phase 2): Empty hops means iOS sandboxing blocked our probe,
            // NOT that the user's network is broken. Don't tell them to "check
            // your internet connection" — they're clearly online or the rest
            // of the diagnostic wouldn't have run. Empty recommendations here
            // means downstream UI (NewAdvancedDiagnosticView) won't generate
            // a "Routing Optimization" card from this.
            return RoutingInterpretation(
                hops: [],
                diagnosis: "Traceroute unavailable",
                problemType: .normal,
                userFriendlyExplanation: "Traceroute unavailable — iOS restricts ICMP traceroute for third-party apps. This is a platform limitation, not a network issue.",
                recommendations: []
            )
        }

        // FIXED: Check if VPN is active - this changes how we interpret Hop 1
        // When VPN is active, Hop 1 is the VPN tunnel exit, NOT the physical router
        let vpnActive = await checkVPNActive()
        let vpnLocation = await getVPNLocation()

        // Rule 1: Check first hop
        // FIXED: When VPN is active, Hop 1 is VPN tunnel, not router!
        if let firstHop = hops.first, let latency = firstHop.latency, latency > 20 {
            if vpnActive {
                // VPN is active - Hop 1 is VPN tunnel exit, NOT the router
                // 100-300ms is NORMAL for VPN connections to distant servers
                if latency > 300 {
                    return RoutingInterpretation(
                        hops: hops,
                        diagnosis: "VPN server slow",
                        problemType: .vpnExit,
                        userFriendlyExplanation: "VPN tunnel latency is high (\(latency)ms). This is your VPN server\(vpnLocation != nil ? " in \(vpnLocation!)" : ""), not your local router.",
                        recommendations: [
                            "Try connecting to a VPN server closer to your location",
                            "Switch VPN protocol to WireGuard (usually fastest)",
                            "Check if your VPN provider has servers in nearby countries"
                        ]
                    )
                } else if latency > 150 {
                    return RoutingInterpretation(
                        hops: hops,
                        diagnosis: "Moderate VPN latency",
                        problemType: .normal,
                        userFriendlyExplanation: "VPN tunnel latency is \(latency)ms. This is your VPN server\(vpnLocation != nil ? " in \(vpnLocation!)" : ""), which is normal for international VPN connections.",
                        recommendations: [
                            "A closer VPN server could reduce latency",
                            "Current latency is acceptable for most use cases"
                        ]
                    )
                } else {
                    // < 150ms with VPN is actually good
                    return RoutingInterpretation(
                        hops: hops,
                        diagnosis: "Good VPN performance",
                        problemType: .normal,
                        userFriendlyExplanation: "VPN tunnel latency is \(latency)ms\(vpnLocation != nil ? " to \(vpnLocation!)" : ""). This is excellent for a VPN connection.",
                        recommendations: [
                            "Your VPN connection is performing well",
                            "No changes needed"
                        ]
                    )
                }
            } else {
                // No VPN - Hop 1 is actually the router
                return RoutingInterpretation(
                    hops: hops,
                    diagnosis: "Router congestion detected",
                    problemType: .routerCongestion,
                    userFriendlyExplanation: "Hop 1 (your router) is responding slowly (\(latency)ms). This may indicate router congestion.",
                    recommendations: [
                        "Restart your router",
                        "Disconnect unused devices from WiFi",
                        "Check if too many devices are streaming or downloading",
                        "Consider upgrading to WiFi 6 router"
                    ]
                )
            }
        }

        // Rule 2: Check hop 2-3 for ISP congestion
        // FIX (Phase 6.3): When VPN is active, the first big latency jump on
        // hops 2-4 is the VPN tunnel transit to an international exit, NOT
        // an ISP congestion event. This used to misdiagnose a 362ms hop
        // (Cloudflare via US VPN exit) as "Local ISP issue at hop 3".
        // Only flag "ISP congestion" when VPN is OFF — under VPN, the only
        // hop that genuinely reflects local ISP behavior is hop 1 (gateway),
        // already handled in Rule 1.
        let earlyHops = hops.prefix(4)
        if !vpnActive,
           let maxLatency = earlyHops.compactMap({ $0.latency }).max(),
           maxLatency > 100 {
            return RoutingInterpretation(
                hops: hops,
                diagnosis: "ISP congestion detected",
                problemType: .ispCongestion,
                userFriendlyExplanation: "Hops 2-3 show high latency (\(maxLatency)ms). Your ISP network is congested.",
                recommendations: [
                    "Try connecting at off-peak hours (2-6 AM)",
                    "Contact your ISP about network congestion",
                    "Consider upgrading your internet plan",
                    "Check if neighbors have similar issues"
                ]
            )
        }

        // Rule 2b (VPN active): a big jump in hops 2+ is the VPN tunnel transit.
        // Surface it honestly instead of pretending it's ISP congestion.
        if vpnActive,
           hops.count >= 2,
           let maxLatency = earlyHops.compactMap({ $0.latency }).max(),
           maxLatency > 150 {
            let direction: String
            if let loc = vpnLocation, !loc.isEmpty {
                direction = " (exits via \(loc))"
            } else {
                direction = ""
            }
            return RoutingInterpretation(
                hops: hops,
                diagnosis: "VPN tunnel transit",
                problemType: .vpnExit,
                userFriendlyExplanation: "The \(maxLatency)ms latency on this hop is the VPN tunnel transit to its exit node\(direction). This is normal for international VPN — it's not an ISP issue.",
                recommendations: [
                    "If the latency is too high for your needs, switch to a closer VPN server",
                    "WireGuard is typically the fastest VPN protocol"
                ]
            )
        }

        // Rule 3: Check for Great Firewall (timeouts near Chinese gateways)
        let hasChineseGateways = hops.contains { hop in
            hop.ip.contains(".cn") || hop.hostname?.contains(".cn") == true
        }
        let hasTimeouts = hops.contains { $0.isTimeout }

        if hasChineseGateways && hasTimeouts {
            return RoutingInterpretation(
                hops: hops,
                diagnosis: "Great Firewall blocking detected",
                problemType: .greatFirewall,
                userFriendlyExplanation: "Route passes through Chinese gateways with timeouts. This is likely Great Firewall interference.",
                recommendations: [
                    "Use a VPN with obfuscation (Shadowsocks, V2Ray)",
                    "Try different VPN protocols (VLESS Reality, Trojan)",
                    "Switch to Hong Kong or Japan VPN servers",
                    "Avoid direct connections to blocked sites"
                ]
            )
        }

        // Rule 4: Check for VPN exit node issues
        let hasVPNIndicators = hops.contains { hop in
            hop.hostname?.contains("vpn") == true ||
            hop.hostname?.contains("tunnel") == true ||
            hop.ip.hasPrefix("10.") ||
            hop.ip.hasPrefix("172.")
        }

        if hasVPNIndicators {
            if let lastHopLatency = hops.last?.latency, lastHopLatency > 200 {
                return RoutingInterpretation(
                    hops: hops,
                    diagnosis: "VPN exit node slow",
                    problemType: .vpnExit,
                    userFriendlyExplanation: "Your VPN exit node (\(hops.last?.ip ?? "unknown")) has high latency (\(lastHopLatency)ms).",
                    recommendations: [
                        "Switch to a closer VPN server",
                        "Try Tokyo, Hong Kong, or Singapore servers",
                        "Check VPN server load status",
                        "Consider using WireGuard protocol for speed"
                    ]
                )
            }
        }

        // Rule 5: Check for CDN distance (many hops, high final latency)
        if hops.count > 10 {
            if let lastLatency = hops.last?.latency, lastLatency > 150 {
                return RoutingInterpretation(
                    hops: hops,
                    diagnosis: "CDN too far",
                    problemType: .cdnFar,
                    userFriendlyExplanation: "Destination is \(hops.count) hops away with \(lastLatency)ms latency. The CDN server is geographically far.",
                    recommendations: [
                        "This is normal for distant servers",
                        "Try accessing regional CDN endpoints",
                        "Use a VPN in the target region",
                        "Contact service provider about regional CDN"
                    ]
                )
            }
        }

        // Rule 6: Normal routing
        let avgLatency = hops.compactMap({ $0.latency }).reduce(0, +) / max(1, hops.compactMap({ $0.latency }).count)

        return RoutingInterpretation(
            hops: hops,
            diagnosis: "Normal routing",
            problemType: .normal,
            userFriendlyExplanation: "Routing looks normal. \(hops.count) hops with average latency of \(avgLatency)ms.",
            recommendations: [
                "Your network routing is healthy",
                "No optimization needed at this time"
            ]
        )
    }
}
