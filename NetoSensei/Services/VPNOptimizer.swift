//
//  VPNOptimizer.swift
//  NetoSensei
//
//  VPN Region and Protocol Optimizer - Auto-select best VPN settings
//

import Foundation
import Network

@MainActor
class VPNOptimizer: ObservableObject {
    static let shared = VPNOptimizer()

    @Published var isOptimizing = false
    @Published var regionResults: [RegionTestResult] = []
    @Published var recommendedRegion: VPNRegion?
    @Published var recommendedProtocol: VPNProtocol?

    // MARK: - VPN Region

    struct VPNRegion: Identifiable, Codable {
        let id: String
        let name: String
        let country: String
        let countryCode: String
        let city: String?
        let latitude: Double
        let longitude: Double
        let serverAddress: String
        let testEndpoint: String // Endpoint to test latency

        var displayName: String {
            if let city = city {
                return "\(city), \(country)"
            }
            return country
        }

        var flagEmoji: String {
            // Convert country code to flag emoji
            let base: UInt32 = 127397
            var emoji = ""
            for scalar in countryCode.uppercased().unicodeScalars {
                if let emojiScalar = UnicodeScalar(base + scalar.value) {
                    emoji.append(String(emojiScalar))
                }
            }
            return emoji
        }
    }

    // MARK: - VPN Protocol

    enum VPNProtocol: String, CaseIterable, Codable {
        case wireGuard = "WireGuard"
        case openVPN = "OpenVPN"
        case ikev2 = "IKEv2"

        var displayName: String { rawValue }

        var description: String {
            switch self {
            case .wireGuard:
                return "Modern, fast, and efficient protocol"
            case .openVPN:
                return "Most compatible, widely supported"
            case .ikev2:
                return "Built into iOS, good mobile performance"
            }
        }

        var pros: [String] {
            switch self {
            case .wireGuard:
                return ["Fastest protocol", "Modern encryption", "Low battery usage", "Best for mobile"]
            case .openVPN:
                return ["Most compatible", "Highly configurable", "Open source", "Reliable"]
            case .ikev2:
                return ["Native iOS support", "Fast reconnection", "Good stability", "No app needed"]
            }
        }

        var cons: [String] {
            switch self {
            case .wireGuard:
                return ["Newer (less proven)", "Limited configuration"]
            case .openVPN:
                return ["Higher battery usage", "Slower than WireGuard"]
            case .ikev2:
                return ["Proprietary", "Less flexible", "Fewer providers"]
            }
        }

        var recommendedFor: [String] {
            switch self {
            case .wireGuard:
                return ["Speed tests", "Gaming", "Video streaming", "Mobile devices"]
            case .openVPN:
                return ["Maximum compatibility", "Firewall bypass", "Corporate networks"]
            case .ikev2:
                return ["iOS devices", "Frequent network changes", "Simple setup"]
            }
        }
    }

    // MARK: - Test Result

    struct RegionTestResult: Identifiable {
        let id = UUID()
        let region: VPNRegion
        var latency: Double? // ms
        var throughput: Double? // Mbps
        var packetLoss: Double? // %
        var jitter: Double? // ms
        var testDate: Date
        var isRecommended: Bool = false

        var score: Double {
            // Calculate overall score (0-100)
            var score: Double = 100

            // Latency impact (0-40 points)
            if let lat = latency {
                if lat < 50 { score -= 0 }
                else if lat < 100 { score -= 10 }
                else if lat < 150 { score -= 20 }
                else if lat < 200 { score -= 30 }
                else { score -= 40 }
            } else {
                score -= 40 // Couldn't test
            }

            // Throughput impact (0-30 points)
            if let tp = throughput {
                if tp > 50 { score -= 0 }
                else if tp > 20 { score -= 10 }
                else if tp > 10 { score -= 20 }
                else { score -= 30 }
            } else {
                score -= 30
            }

            // Packet loss impact (0-20 points)
            if let loss = packetLoss {
                if loss < 1 { score -= 0 }
                else if loss < 3 { score -= 5 }
                else if loss < 5 { score -= 10 }
                else { score -= 20 }
            } else {
                score -= 10
            }

            // Jitter impact (0-10 points)
            if let j = jitter {
                if j < 5 { score -= 0 }
                else if j < 10 { score -= 5 }
                else { score -= 10 }
            } else {
                score -= 5
            }

            return max(0, score)
        }

        var quality: String {
            let s = score
            if s >= 90 { return "Excellent" }
            if s >= 75 { return "Good" }
            if s >= 60 { return "Fair" }
            if s >= 40 { return "Poor" }
            return "Bad"
        }
    }

    // MARK: - Predefined Regions

    static let popularRegions: [VPNRegion] = [
        // United States
        VPNRegion(id: "us-east", name: "US East", country: "United States", countryCode: "US",
                  city: "New York", latitude: 40.7128, longitude: -74.0060,
                  serverAddress: "us-east.vpn.example.com", testEndpoint: "https://cloudflare.com/cdn-cgi/trace"),
        VPNRegion(id: "us-west", name: "US West", country: "United States", countryCode: "US",
                  city: "Los Angeles", latitude: 34.0522, longitude: -118.2437,
                  serverAddress: "us-west.vpn.example.com", testEndpoint: "https://cloudflare.com/cdn-cgi/trace"),

        // Europe
        VPNRegion(id: "uk-london", name: "UK London", country: "United Kingdom", countryCode: "GB",
                  city: "London", latitude: 51.5074, longitude: -0.1278,
                  serverAddress: "uk.vpn.example.com", testEndpoint: "https://cloudflare.com/cdn-cgi/trace"),
        VPNRegion(id: "de-frankfurt", name: "Germany", country: "Germany", countryCode: "DE",
                  city: "Frankfurt", latitude: 50.1109, longitude: 8.6821,
                  serverAddress: "de.vpn.example.com", testEndpoint: "https://cloudflare.com/cdn-cgi/trace"),
        VPNRegion(id: "nl-amsterdam", name: "Netherlands", country: "Netherlands", countryCode: "NL",
                  city: "Amsterdam", latitude: 52.3676, longitude: 4.9041,
                  serverAddress: "nl.vpn.example.com", testEndpoint: "https://cloudflare.com/cdn-cgi/trace"),

        // Asia Pacific
        VPNRegion(id: "jp-tokyo", name: "Japan", country: "Japan", countryCode: "JP",
                  city: "Tokyo", latitude: 35.6762, longitude: 139.6503,
                  serverAddress: "jp.vpn.example.com", testEndpoint: "https://cloudflare.com/cdn-cgi/trace"),
        VPNRegion(id: "sg-singapore", name: "Singapore", country: "Singapore", countryCode: "SG",
                  city: "Singapore", latitude: 1.3521, longitude: 103.8198,
                  serverAddress: "sg.vpn.example.com", testEndpoint: "https://cloudflare.com/cdn-cgi/trace"),
        VPNRegion(id: "au-sydney", name: "Australia", country: "Australia", countryCode: "AU",
                  city: "Sydney", latitude: -33.8688, longitude: 151.2093,
                  serverAddress: "au.vpn.example.com", testEndpoint: "https://cloudflare.com/cdn-cgi/trace"),

        // Americas
        VPNRegion(id: "ca-toronto", name: "Canada", country: "Canada", countryCode: "CA",
                  city: "Toronto", latitude: 43.6532, longitude: -79.3832,
                  serverAddress: "ca.vpn.example.com", testEndpoint: "https://cloudflare.com/cdn-cgi/trace"),
        VPNRegion(id: "br-saopaulo", name: "Brazil", country: "Brazil", countryCode: "BR",
                  city: "São Paulo", latitude: -23.5505, longitude: -46.6333,
                  serverAddress: "br.vpn.example.com", testEndpoint: "https://cloudflare.com/cdn-cgi/trace"),
    ]

    // MARK: - Streaming CDN Info

    struct StreamingCDN {
        let platform: String
        let cdnLocations: [(city: String, country: String, latitude: Double, longitude: Double)]
    }

    static let streamingCDNs: [StreamingCDN] = [
        StreamingCDN(platform: "Netflix", cdnLocations: [
            ("Los Angeles", "United States", 34.0522, -118.2437),
            ("New York", "United States", 40.7128, -74.0060),
            ("London", "United Kingdom", 51.5074, -0.1278),
            ("Amsterdam", "Netherlands", 52.3676, 4.9041),
            ("Tokyo", "Japan", 35.6762, 139.6503),
            ("Sydney", "Australia", -33.8688, 151.2093)
        ]),
        StreamingCDN(platform: "YouTube", cdnLocations: [
            ("Los Angeles", "United States", 34.0522, -118.2437),
            ("New York", "United States", 40.7128, -74.0060),
            ("London", "United Kingdom", 51.5074, -0.1278),
            ("Frankfurt", "Germany", 50.1109, 8.6821),
            ("Tokyo", "Japan", 35.6762, 139.6503),
            ("Singapore", "Singapore", 1.3521, 103.8198)
        ]),
        StreamingCDN(platform: "Hulu", cdnLocations: [
            ("Los Angeles", "United States", 34.0522, -118.2437),
            ("New York", "United States", 40.7128, -74.0060)
        ]),
        StreamingCDN(platform: "Disney+", cdnLocations: [
            ("Los Angeles", "United States", 34.0522, -118.2437),
            ("New York", "United States", 40.7128, -74.0060),
            ("London", "United Kingdom", 51.5074, -0.1278),
            ("Amsterdam", "Netherlands", 52.3676, 4.9041)
        ]),
        StreamingCDN(platform: "Amazon Prime", cdnLocations: [
            ("Los Angeles", "United States", 34.0522, -118.2437),
            ("New York", "United States", 40.7128, -74.0060),
            ("London", "United Kingdom", 51.5074, -0.1278),
            ("Frankfurt", "Germany", 50.1109, 8.6821),
            ("Tokyo", "Japan", 35.6762, 139.6503),
            ("Sydney", "Australia", -33.8688, 151.2093)
        ])
    ]

    private init() {}

    // MARK: - Optimize VPN

    func optimizeVPN(for purpose: OptimizationPurpose) async {
        isOptimizing = true
        regionResults = []

        debugLog("🚀 Starting VPN optimization for: \(purpose.rawValue)")

        // Test all popular regions
        var results: [RegionTestResult] = []

        for region in Self.popularRegions {
            debugLog("🌍 Testing region: \(region.displayName)")
            let result = await testRegion(region)
            results.append(result)

            // Update UI as we go
            await MainActor.run {
                regionResults = results.sorted { $0.score > $1.score }
            }

            // Small delay between tests
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }

        // Determine best region based on purpose
        let bestRegion = determineBestRegion(results: results, purpose: purpose)

        // Mark recommended
        if let best = bestRegion {
            if let index = results.firstIndex(where: { $0.region.id == best.region.id }) {
                results[index].isRecommended = true
            }
        }

        await MainActor.run {
            regionResults = results.sorted { $0.score > $1.score }
            recommendedRegion = bestRegion?.region
            isOptimizing = false
        }

        debugLog("✅ VPN optimization complete. Recommended: \(bestRegion?.region.displayName ?? "None")")
    }

    enum OptimizationPurpose: String {
        case general = "General Use"
        case streaming = "Streaming"
        case gaming = "Gaming"
        case privacy = "Privacy"
        case speed = "Speed Test"
    }

    // MARK: - Test Region

    nonisolated private func testRegion(_ region: VPNRegion) async -> RegionTestResult {
        // Test latency
        let latency = await testLatency(endpoint: region.testEndpoint)

        // Test packet loss and jitter
        let (packetLoss, jitter) = await testPacketLossAndJitter(endpoint: region.testEndpoint)

        // Test throughput (simplified - just download speed indicator)
        let throughput = await testThroughput(endpoint: region.testEndpoint)

        return RegionTestResult(
            region: region,
            latency: latency,
            throughput: throughput,
            packetLoss: packetLoss,
            jitter: jitter,
            testDate: Date()
        )
    }

    nonisolated private func testLatency(endpoint: String) async -> Double? {
        guard let url = URL(string: endpoint) else { return nil }

        let start = Date()
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            let duration = Date().timeIntervalSince(start)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                let latencyMs = duration * 1000
                return latencyMs
            }
        } catch {
            return nil
        }
        return nil
    }

    nonisolated private func testPacketLossAndJitter(endpoint: String) async -> (packetLoss: Double?, jitter: Double?) {
        guard let url = URL(string: endpoint) else { return (nil, nil) }

        var latencies: [Double] = []
        let testCount = 5

        for _ in 0..<testCount {
            let start = Date()
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                let duration = Date().timeIntervalSince(start)

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    latencies.append(duration * 1000)
                }
            } catch {
                // Count as packet loss
                continue
            }
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s between pings
        }

        let packetLoss = Double(testCount - latencies.count) / Double(testCount) * 100

        // Calculate jitter (variance in latency)
        var jitter: Double?
        if latencies.count >= 2 {
            let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
            let variance = latencies.map { pow($0 - avgLatency, 2) }.reduce(0, +) / Double(latencies.count)
            jitter = sqrt(variance)
        }

        return (packetLoss, jitter)
    }

    nonisolated private func testThroughput(endpoint: String) async -> Double? {
        // Simplified throughput test - download 1MB
        let testURL = "https://speed.cloudflare.com/__down?bytes=1000000"
        guard let url = URL(string: testURL) else { return nil }

        let start = Date()
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let duration = Date().timeIntervalSince(start)

            let megabits = Double(data.count) * 8 / 1_000_000
            let mbps = megabits / duration
            return mbps
        } catch {
            return nil
        }
    }

    // MARK: - Best Region Selection

    private func determineBestRegion(results: [RegionTestResult], purpose: OptimizationPurpose) -> RegionTestResult? {
        guard !results.isEmpty else { return nil }

        switch purpose {
        case .general, .privacy:
            // Best overall score
            return results.max { $0.score < $1.score }

        case .streaming:
            // Prioritize throughput over latency
            return results.filter { ($0.throughput ?? 0) > 5 }
                .max { ($0.throughput ?? 0) < ($1.throughput ?? 0) }

        case .gaming, .speed:
            // Prioritize lowest latency
            return results.filter { ($0.latency ?? 999) < 150 }
                .min { ($0.latency ?? 999) < ($1.latency ?? 999) }
        }
    }

    // MARK: - Protocol Recommendation

    func recommendProtocol(for purpose: OptimizationPurpose, currentNetworkType: String?) -> VPNProtocol {
        switch purpose {
        case .general:
            return .wireGuard // Best overall
        case .streaming:
            return .wireGuard // Fastest
        case .gaming:
            return .wireGuard // Lowest latency
        case .privacy:
            return .openVPN // Most mature
        case .speed:
            return .wireGuard // Fastest
        }
    }

    // MARK: - Quick Recommendation

    func getQuickRecommendation(currentLatency: Double?, forStreaming: Bool = false) async -> VPNRegion? {
        // If latency is good, no need to change
        if let lat = currentLatency, lat < 100 {
            return nil // Current VPN is fine
        }

        // Test top 3 regions quickly
        let topRegions = Self.popularRegions.prefix(3)
        var bestResult: RegionTestResult?

        for region in topRegions {
            let result = await testRegion(region)

            if let best = bestResult {
                if result.score > best.score {
                    bestResult = result
                }
            } else {
                bestResult = result
            }
        }

        return bestResult?.region
    }

    // MARK: - Distance Calculation

    static func calculateDistance(from userLocation: (lat: Double, lon: Double), to region: VPNRegion) -> Double {
        // Haversine formula for great-circle distance
        let lat1Rad = userLocation.lat * .pi / 180
        let lat2Rad = region.latitude * .pi / 180
        let dLat = (region.latitude - userLocation.lat) * .pi / 180
        let dLon = (region.longitude - userLocation.lon) * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        let radiusOfEarth: Double = 6371 // km
        return radiusOfEarth * c
    }

    func findNearestRegion(to userLocation: (lat: Double, lon: Double)) -> VPNRegion? {
        return Self.popularRegions.min { region1, region2 in
            let dist1 = Self.calculateDistance(from: userLocation, to: region1)
            let dist2 = Self.calculateDistance(from: userLocation, to: region2)
            return dist1 < dist2
        }
    }

    // MARK: - Streaming Optimization

    func optimizeForStreaming(platform: String) -> VPNRegion? {
        // Find CDN locations for the platform
        guard let cdn = Self.streamingCDNs.first(where: { $0.platform == platform }) else {
            debugLog("⚠️ No CDN info for platform: \(platform)")
            return nil
        }

        debugLog("🎬 Optimizing VPN for \(platform) streaming...")

        // For each CDN location, find the closest VPN region
        var bestRegion: VPNRegion?
        var shortestDistance: Double = .infinity

        for cdnLocation in cdn.cdnLocations {
            let cdnCoords = (lat: cdnLocation.latitude, lon: cdnLocation.longitude)

            for vpnRegion in Self.popularRegions {
                let distance = Self.calculateDistance(from: cdnCoords, to: vpnRegion)

                if distance < shortestDistance {
                    shortestDistance = distance
                    bestRegion = vpnRegion
                }
            }
        }

        if let best = bestRegion {
            debugLog("✅ Best VPN region for \(platform): \(best.displayName) (\(Int(shortestDistance))km from CDN)")
        }

        return bestRegion
    }

    func getBestStreamingRegions() -> [String: VPNRegion] {
        var recommendations: [String: VPNRegion] = [:]

        for cdn in Self.streamingCDNs {
            if let region = optimizeForStreaming(platform: cdn.platform) {
                recommendations[cdn.platform] = region
            }
        }

        return recommendations
    }

    // MARK: - Streaming Recommendation

    struct StreamingRecommendation {
        let platform: String
        let vpnRegion: VPNRegion
        let distanceToCDN: Double // km
        let estimatedLatency: Double // ms (rough estimate based on distance)

        var description: String {
            "For \(platform), connect to \(vpnRegion.displayName) VPN server (≈\(Int(estimatedLatency))ms to CDN)"
        }
    }

    func getStreamingRecommendations() -> [StreamingRecommendation] {
        var recommendations: [StreamingRecommendation] = []

        for cdn in Self.streamingCDNs {
            var closestDistance: Double = .infinity
            var closestRegion: VPNRegion?

            // Find closest VPN region to any of the CDN locations
            for cdnLocation in cdn.cdnLocations {
                let cdnCoords = (lat: cdnLocation.latitude, lon: cdnLocation.longitude)

                for vpnRegion in Self.popularRegions {
                    let distance = Self.calculateDistance(from: cdnCoords, to: vpnRegion)

                    if distance < closestDistance {
                        closestDistance = distance
                        closestRegion = vpnRegion
                    }
                }
            }

            if let region = closestRegion {
                // Rough estimate: 1ms per 100km + base latency of 10ms
                let estimatedLatency = (closestDistance / 100) + 10

                recommendations.append(StreamingRecommendation(
                    platform: cdn.platform,
                    vpnRegion: region,
                    distanceToCDN: closestDistance,
                    estimatedLatency: estimatedLatency
                ))
            }
        }

        return recommendations.sorted { $0.estimatedLatency < $1.estimatedLatency }
    }
}
