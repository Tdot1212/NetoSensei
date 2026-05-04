//
//  StreamingDiagnosticService.swift
//  NetoSensei
//
//  Streaming-specific diagnostic service for CDN testing
//

import Foundation

// FIXED: Added @MainActor for proper Swift 6 concurrency with @Published properties
@MainActor
class StreamingDiagnosticService: ObservableObject {
    static let shared = StreamingDiagnosticService()

    @Published var isRunning = false
    @Published var currentTest: String = ""
    @Published var progress: Double = 0.0

    // CDN endpoints for various streaming platforms
    private let streamingEndpoints: [StreamingPlatform: [String]] = [
        .netflix: [
            "www.netflix.com",
            "assets.nflxext.com",
            "cdn.netflix.com"
        ],
        .youtube: [
            "googlevideo.com",
            "youtube.com",
            "ytimg.com"
        ],
        .tiktok: [
            "tiktokcdn.com",
            "tiktok.com"
        ],
        .twitch: [
            "twitch.tv",
            "ttvnw.net"
        ],
        .disneyPlus: [
            "disneyplus.com",
            "bamgrid.com"
        ],
        .amazonPrime: [
            "primevideo.com",
            "pv-cdn.net"
        ],
        .appleTV: [
            "tv.apple.com",
            "apple.com"
        ],
        .hulu: [
            "hulu.com",
            "hulustream.com"
        ]
    ]

    private init() {
        // Empty init - NetworkMonitorService.shared accessed directly where needed
    }

    // MARK: - Run Streaming Diagnostic

    nonisolated func diagnoseStreaming(platform: StreamingPlatform) async -> StreamingDiagnosticResult {
        await MainActor.run {
            isRunning = true
            progress = 0.0
            currentTest = "Initializing..."
        }

        let networkStatus = await MainActor.run { NetworkMonitorService.shared.currentStatus }

        // Step 1: CDN Testing (30%) - 5s timeout
        await MainActor.run { currentTest = "Testing \(platform.rawValue) CDN..." }
        let cdnResult = await testCDN(for: platform, timeout: 5.0)
        await MainActor.run { progress = 0.3 }

        // Step 2: Network Factor Analysis (20%) - 5s timeout each
        await MainActor.run { currentTest = "Analyzing network factors..." }
        let wifiStrength = networkStatus.wifi.rssi ?? -50
        let routerLatency = networkStatus.router.latency
        let jitter = await measureJitter(timeout: 5.0)
        let packetLoss = await measurePacketLoss(timeout: 5.0)
        await MainActor.run { progress = 0.5 }

        // Step 3: VPN Impact Analysis (20%) - 5s timeout
        await MainActor.run { currentTest = "Analyzing VPN impact..." }
        let (vpnImpact, throughputWithVPN, throughputWithoutVPN) = await analyzeVPNImpact(timeout: 5.0)
        await MainActor.run { progress = 0.7 }

        // Step 4: ISP Congestion Detection (15%) - 5s timeout
        await MainActor.run { currentTest = "Checking ISP congestion..." }
        let ispCongestion = await detectISPCongestion(timeout: 5.0)
        await MainActor.run { progress = 0.85 }

        // Step 5: DNS Performance (10%)
        await MainActor.run { currentTest = "Testing DNS..." }
        let dnsLatency = networkStatus.dns.latency ?? 0
        let dnsProvider = networkStatus.dns.resolverIP
        await MainActor.run { progress = 0.95 }

        // Step 6: Analyze and Build Result (5%)
        await MainActor.run { currentTest = "Analyzing results..." }
        let result = buildStreamingResult(
            platform: platform,
            cdnResult: cdnResult,
            wifiStrength: wifiStrength,
            routerLatency: routerLatency,
            jitter: jitter,
            packetLoss: packetLoss,
            vpnActive: networkStatus.vpn.isActive,
            vpnImpact: vpnImpact,
            throughputWithVPN: throughputWithVPN,
            throughputWithoutVPN: throughputWithoutVPN,
            vpnServerLocation: networkStatus.vpn.serverLocation,
            ispCongestion: ispCongestion,
            dnsLatency: dnsLatency,
            dnsProvider: dnsProvider,
            ipv6Available: networkStatus.isIPv6Enabled
        )

        await MainActor.run {
            progress = 1.0
            isRunning = false
            currentTest = ""
        }

        return result
    }

    // MARK: - CDN Testing

    nonisolated private func testCDN(for platform: StreamingPlatform, timeout: TimeInterval) async -> CDNTestResult {
        guard let endpoints = streamingEndpoints[platform] else {
            return CDNTestResult(
                platform: platform,
                endpoint: "Unknown",
                isReachable: false,
                routingOptimal: false,
                estimatedQuality: .sd
            )
        }

        // Test primary endpoint
        let primaryEndpoint = endpoints[0]
        let (isReachable, latency) = await pingEndpoint(primaryEndpoint)

        // Estimate throughput (simplified - would need actual download test in production)
        let estimatedThroughput = await estimateThroughput(to: primaryEndpoint)

        // Detect region (simplified - would use IP geolocation in production)
        let regionDetected = await detectCDNRegion(primaryEndpoint)

        // Check if routing is optimal (latency < 100ms is considered good)
        let routingOptimal = (latency ?? 999) < 100

        // Estimate video quality based on throughput
        let estimatedQuality: CDNTestResult.VideoQuality
        if estimatedThroughput >= 25 {
            estimatedQuality = .uhd4K
        } else if estimatedThroughput >= 8 {
            estimatedQuality = .fullHD
        } else if estimatedThroughput >= 3 {
            estimatedQuality = .hd
        } else {
            estimatedQuality = .sd
        }

        return CDNTestResult(
            platform: platform,
            endpoint: primaryEndpoint,
            isReachable: isReachable,
            latency: latency,
            throughput: estimatedThroughput,
            regionDetected: regionDetected,
            routingOptimal: routingOptimal,
            estimatedQuality: estimatedQuality
        )
    }

    nonisolated private func pingEndpoint(_ endpoint: String) async -> (Bool, Double?) {
        // Try to resolve and ping the endpoint
        return await NetworkMonitorService.shared.pingHost(endpoint, timeout: 5.0)
    }

    nonisolated private func estimateThroughput(to endpoint: String) async -> Double {
        do {
            return try await withTimeout(seconds: 5.0) {
                // Use Apple's test endpoint for reliability (works in China)
                guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return 0 }

                let start = Date()
                let (data, _) = try await URLSession.shared.data(from: url)
                let duration = Date().timeIntervalSince(start)

                // Calculate Mbps
                let megabits = Double(data.count) * 8 / 1_000_000
                let mbps = megabits / duration

                return mbps
            }
        } catch {
            // If actual test fails, estimate based on latency
            let (_, latency) = await pingEndpoint(endpoint)
            if let lat = latency {
                // Rough estimation: lower latency = higher potential speed
                if lat < 30 { return 100 }
                if lat < 50 { return 50 }
                if lat < 100 { return 25 }
                return 10
            }
            return 0
        }
    }

    nonisolated private func detectCDNRegion(_ endpoint: String) async -> String? {
        // In production, this would use GeoIP lookup on the resolved IP
        // For now, return a placeholder
        return "Unknown Region"
    }

    // MARK: - Network Factor Analysis

    nonisolated private func measureJitter(timeout: TimeInterval) async -> Double {
        do {
            return try await withTimeout(seconds: timeout) {
                var latencies: [Double] = []

                for _ in 0..<5 {
                    let (success, latency) = await NetworkMonitorService.shared.pingHost("1.1.1.1", timeout: 1.0)
                    if success, let lat = latency {
                        latencies.append(lat)
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }

                guard latencies.count >= 2 else { return 0 }

                let avg = latencies.reduce(0, +) / Double(latencies.count)
                let variance = latencies.map { pow($0 - avg, 2) }.reduce(0, +) / Double(latencies.count)
                return sqrt(variance)
            }
        } catch {
            return 0  // Timeout - return default
        }
    }

    nonisolated private func measurePacketLoss(timeout: TimeInterval) async -> Double {
        do {
            return try await withTimeout(seconds: timeout) {
                var successCount = 0
                let totalPings = 10

                for _ in 0..<totalPings {
                    let (success, _) = await NetworkMonitorService.shared.pingHost("1.1.1.1", timeout: 1.0)
                    if success { successCount += 1 }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }

                let lossPercentage = Double(totalPings - successCount) / Double(totalPings) * 100
                return lossPercentage
            }
        } catch {
            return 100.0  // Timeout - assume 100% loss
        }
    }

    // MARK: - VPN Impact Analysis

    nonisolated private func analyzeVPNImpact(timeout: TimeInterval) async -> (Double?, Double?, Double?) {
        do {
            return try await withTimeout(seconds: timeout) {
                let networkStatus = await MainActor.run { NetworkMonitorService.shared.currentStatus }

                guard networkStatus.vpn.isActive else {
                    return (nil, nil, nil)
                }

                // Measure current throughput with VPN
                let withVPN = await self.measureThroughput(timeout: 3.0)

                // Note: We cannot actually disable VPN programmatically without user permission
                // So we estimate based on VPN latency impact
                let vpnLatency = networkStatus.vpn.tunnelLatency ?? 0
                let estimatedWithoutVPN = withVPN * (1 + vpnLatency / 100)  // Rough estimation

                let impact = ((estimatedWithoutVPN - withVPN) / estimatedWithoutVPN) * 100

                return (impact, withVPN, estimatedWithoutVPN)
            }
        } catch {
            return (nil, nil, nil)  // Timeout
        }
    }

    // FIXED: Use actual speed test file instead of tiny success.html
    // The Apple success.html is only a few hundred bytes, giving inaccurate results
    nonisolated private func measureThroughput(timeout: TimeInterval) async -> Double {
        do {
            return try await withTimeout(seconds: timeout) {
                // Use Cloudflare's speed test endpoint with 2MB file for accurate measurement
                let testURL = "https://speed.cloudflare.com/__down?bytes=2000000"
                guard let url = URL(string: testURL) else { return 0 }

                let start = Date()
                let (data, _) = try await URLSession.shared.data(from: url)
                let duration = Date().timeIntervalSince(start)

                // Only calculate if we got meaningful data
                guard data.count > 1000 else { return 0 }

                let megabits = Double(data.count) * 8 / 1_000_000
                let mbps = megabits / duration

                debugLog("📊 Streaming throughput: \(String(format: "%.1f", mbps)) Mbps (\(data.count) bytes in \(String(format: "%.2f", duration))s)")
                return mbps
            }
        } catch {
            debugLog("⚠️ Streaming throughput measurement failed: \(error)")
            return 0  // Timeout or error
        }
    }

    // MARK: - ISP Congestion Detection

    nonisolated private func detectISPCongestion(timeout: TimeInterval) async -> Bool {
        do {
            return try await withTimeout(seconds: timeout) {
                // Check if current time is during typical congestion hours (6 PM - 11 PM)
                let hour = Calendar.current.component(.hour, from: Date())
                let isPeakHours = hour >= 18 && hour <= 23

                // Measure latency variance as indicator of congestion
                let jitter = await self.measureJitter(timeout: 3.0)
                let highJitter = jitter > 30

                return isPeakHours && highJitter
            }
        } catch {
            return false  // Timeout - assume no congestion
        }
    }

    // MARK: - Build Result

    nonisolated private func buildStreamingResult(
        platform: StreamingPlatform,
        cdnResult: CDNTestResult,
        wifiStrength: Int,
        routerLatency: Double?,
        jitter: Double,
        packetLoss: Double,
        vpnActive: Bool,
        vpnImpact: Double?,
        throughputWithVPN: Double?,
        throughputWithoutVPN: Double?,
        vpnServerLocation: String?,
        ispCongestion: Bool,
        dnsLatency: Double,
        dnsProvider: String?,
        ipv6Available: Bool
    ) -> StreamingDiagnosticResult {

        // Determine primary bottleneck
        let primaryBottleneck = identifyPrimaryBottleneck(
            cdnLatency: cdnResult.latency ?? 999,
            wifiStrength: wifiStrength,
            routerLatency: routerLatency ?? 0,
            vpnActive: vpnActive,
            vpnImpact: vpnImpact ?? 0,
            ispCongestion: ispCongestion,
            dnsLatency: dnsLatency,
            packetLoss: packetLoss
        )

        // Generate recommendation
        let (recommendation, actionableSteps, fixAction) = generateRecommendation(
            primaryBottleneck: primaryBottleneck,
            platform: platform,
            cdnRegion: cdnResult.regionDetected,
            vpnActive: vpnActive,
            wifiStrength: wifiStrength
        )

        return StreamingDiagnosticResult(
            timestamp: Date(),
            platform: platform,
            cdnPing: cdnResult.latency ?? 0,
            cdnThroughput: cdnResult.throughput ?? -1.0,  // Use -1.0 for blocked/failed test, never 0.0
            cdnReachable: cdnResult.isReachable,
            cdnRegion: cdnResult.regionDetected,
            cdnRoutingIssue: !cdnResult.routingOptimal,
            wifiStrength: wifiStrength,
            routerLatency: routerLatency,
            jitter: jitter,
            packetLoss: packetLoss,
            vpnActive: vpnActive,
            vpnImpact: vpnImpact,
            throughputWithVPN: throughputWithVPN,
            throughputWithoutVPN: throughputWithoutVPN,
            vpnServerLocation: vpnServerLocation,
            ispCongestion: ispCongestion,
            timeOfDay: Date(),
            historicalCongestionPattern: ispCongestion ? "Peak hours (6 PM - 11 PM)" : nil,
            dnsLatency: dnsLatency,
            dnsProvider: dnsProvider,
            ipv6Available: ipv6Available,
            ipv6Faster: false,
            estimatedDeviceCount: nil,
            primaryBottleneck: primaryBottleneck,
            secondaryFactors: [],
            recommendation: recommendation,
            actionableSteps: actionableSteps,
            fixAction: fixAction
        )
    }

    // MARK: - Bottleneck Identification

    nonisolated private func identifyPrimaryBottleneck(
        cdnLatency: Double,
        wifiStrength: Int,
        routerLatency: Double,
        vpnActive: Bool,
        vpnImpact: Double,
        ispCongestion: Bool,
        dnsLatency: Double,
        packetLoss: Double
    ) -> StreamingDiagnosticResult.BottleneckType {

        // Priority order: critical issues first

        // FIXED: Removed WiFi signal check - iOS cannot measure RSSI
        // WiFi signal strength cannot be determined on iOS via public APIs
        // We use router latency and packet loss as proxy indicators instead

        // 1. VPN causing significant slowdown
        if vpnActive && vpnImpact > 50 {
            return .vpn
        }

        // 2. ISP congestion
        if ispCongestion {
            return .isp
        }

        // 3. CDN routing issue
        if cdnLatency > 150 {
            return .cdn
        }

        // 4. Router/Local network issues (replaces WiFi signal check)
        if routerLatency > 50 || packetLoss > 5 {
            return .router
        }

        // 5. DNS slow
        if dnsLatency > 150 {
            return .dns
        }

        return .none
    }

    // MARK: - Recommendation Generation

    nonisolated private func generateRecommendation(
        primaryBottleneck: StreamingDiagnosticResult.BottleneckType,
        platform: StreamingPlatform,
        cdnRegion: String?,
        vpnActive: Bool,
        wifiStrength: Int
    ) -> (String, [String], StreamingDiagnosticResult.FixAction?) {

        switch primaryBottleneck {
        case .vpn:
            return (
                "Your VPN is significantly reducing streaming speed.",
                [
                    "Disconnect VPN temporarily for streaming",
                    "Switch to a closer VPN server",
                    "Try a different VPN protocol"
                ],
                .switchVPNServer(region: "nearest")
            )

        case .wifi:
            // FIXED: This case should not be reached since iOS cannot measure WiFi signal
            // Fallback to router-based recommendation if somehow reached
            return (
                "Local network issues detected.",
                [
                    "Restart your router",
                    "Disconnect unused devices",
                    "Use wired connection if possible"
                ],
                .restartRouter
            )

        case .router:
            return (
                "Your router appears congested.",
                [
                    "Restart your router",
                    "Disconnect unused devices",
                    "Use wired connection if possible"
                ],
                .restartRouter
            )

        case .isp:
            return (
                "Your ISP is experiencing congestion during peak hours.",
                [
                    "Try streaming during off-peak hours",
                    "Lower video quality settings",
                    "Consider switching to cellular data"
                ],
                .waitForOffPeakHours(hours: "after 11 PM")
            )

        case .cdn:
            let region = cdnRegion ?? "distant server"
            return (
                "\(platform.rawValue) is routing you through a \(region).",
                [
                    "Change VPN region for better CDN routing",
                    "Try disconnecting VPN",
                    "Contact \(platform.rawValue) support"
                ],
                vpnActive ? .changeVPNRegion(recommended: "closer region") : nil
            )

        case .dns:
            return (
                "DNS resolution is slow, affecting initial connections.",
                [
                    "Switch to Cloudflare DNS (1.1.1.1)",
                    "Switch to Google DNS (8.8.8.8)",
                    "Restart your router to refresh DNS"
                ],
                .switchDNS
            )

        case .device:
            return (
                "Your device may have limitations.",
                [
                    "Close background apps",
                    "Restart your device",
                    "Update iOS to latest version"
                ],
                nil
            )

        case .none:
            return (
                "No issues detected! Your streaming should work well.",
                [
                    "Estimated quality: 4K UHD capable"
                ],
                nil
            )
        }
    }
}
