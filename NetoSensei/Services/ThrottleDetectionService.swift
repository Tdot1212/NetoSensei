//
//  ThrottleDetectionService.swift
//  NetoSensei
//
//  Detects ISP throttling by comparing speeds to different endpoints
//  IMPROVED: Proper speed test endpoints, size validation, VPN-aware recommendations
//

import Foundation

// MARK: - Test Status

enum ThrottleTestStatus: String {
    case success = "Success"
    case failed = "Failed"
    case endpointError = "Endpoint Error"  // Returned too little data
    case timeout = "Timeout"
}

// MARK: - Throttle Result

struct ThrottleResult: Identifiable {
    let id = UUID()
    let endpoint: String       // "Cloudflare"
    let category: String       // "CDN", "Streaming", etc.
    let url: String           // The actual URL tested
    let speedMbps: Double?    // nil if failed
    let bytesReceived: Int    // How much data we got
    let expectedMinBytes: Int // Minimum expected
    let status: ThrottleTestStatus
    let throttled: Bool       // true if significantly slower than baseline
    let percentSlower: Double? // How much slower than baseline
    let note: String?         // Additional context

    var displaySpeed: String {
        switch status {
        case .success:
            if let speed = speedMbps {
                return String(format: "%.1f Mbps", speed)
            }
            return "--"
        case .failed:
            return "Failed"
        case .endpointError:
            return "Error"
        case .timeout:
            return "Timeout"
        }
    }

    var statusIcon: String {
        switch status {
        case .success:
            return throttled ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        case .failed, .timeout:
            return "xmark.circle.fill"
        case .endpointError:
            return "questionmark.circle.fill"
        }
    }

    var statusColor: String {
        switch status {
        case .success:
            return throttled ? "orange" : "green"
        case .failed, .timeout:
            return "gray"
        case .endpointError:
            return "yellow"
        }
    }

    var statusText: String {
        switch status {
        case .success:
            if throttled, let percent = percentSlower {
                return "\(Int(percent))% slower"
            }
            return "Normal"
        case .failed:
            return "Connection failed"
        case .endpointError:
            return note ?? "Endpoint returned insufficient data"
        case .timeout:
            return "Request timed out"
        }
    }
}

// MARK: - Throttle Analysis

struct ThrottleAnalysis {
    let results: [ThrottleResult]
    let throttlingDetected: Bool
    let throttledServices: [String]
    let baselineSpeed: Double     // Fastest endpoint speed
    let validTestCount: Int       // How many tests were valid
    let summary: String
    let explanation: String       // Plain-English explanation
    let timestamp: Date
    let recommendation: String
    let isVPNActive: Bool
    let confidence: Confidence

    enum Confidence: String {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        case inconclusive = "Inconclusive"
        case skipped = "Skipped"  // FIX (Phase 6.2): test not run (VPN active)
    }

    /// FIX (Phase 6.2): true when the test was deliberately skipped because
    /// VPN is active. UI should render an explanatory note and no per-CDN
    /// numbers, since the values are meaningless under a tunnel.
    var wasSkipped: Bool {
        confidence == .skipped
    }

    var overallStatus: String {
        if wasSkipped {
            return "Skipped (VPN active)"
        }
        if validTestCount < 2 {
            return "Inconclusive"
        } else if throttlingDetected {
            return "Possible Throttling"
        } else if results.allSatisfy({ $0.status != .success }) {
            return "Test Failed"
        } else {
            return "No Throttling"
        }
    }

    var overallStatusColor: String {
        if wasSkipped {
            return "blue"
        }
        if validTestCount < 2 {
            return "yellow"
        } else if throttlingDetected {
            return "orange"
        } else if results.allSatisfy({ $0.status != .success }) {
            return "gray"
        } else {
            return "green"
        }
    }
}

// MARK: - Throttle Detection Service

class ThrottleDetectionService {
    static let shared = ThrottleDetectionService()

    struct TestEndpoint {
        let name: String
        let url: String
        let category: String        // "CDN", "Streaming", "Cloud", "General"
        let expectedMinBytes: Int   // Minimum bytes expected (to detect error pages)
    }

    // FIX (Phase 6.2): Use 10MB+ payloads where the endpoint supports it so
    // TCP slow-start doesn't dominate the measurement. Tiny files (favicons)
    // produced wildly inaccurate Mbps numbers (Apple 0.7, Akamai 0.1 over
    // a 122 Mbps connection). Throttle detection only runs when VPN is OFF
    // — see `detectThrottling`. Under VPN the numbers are meaningless.
    static let endpoints: [TestEndpoint] = [
        // Cloudflare speed test — 10 MB
        TestEndpoint(
            name: "Cloudflare",
            url: "https://speed.cloudflare.com/__down?bytes=10000000",
            category: "CDN",
            expectedMinBytes: 5_000_000
        ),
        // Hetzner mirror — 10 MB random-data file (used by speed-test sites)
        TestEndpoint(
            name: "Hetzner",
            url: "https://speed.hetzner.de/10MB.bin",
            category: "CDN",
            expectedMinBytes: 5_000_000
        ),
        // OVHcloud — 10 MB sample file
        TestEndpoint(
            name: "OVH",
            url: "https://proof.ovh.net/files/10Mb.dat",
            category: "CDN",
            expectedMinBytes: 5_000_000
        ),
        // ThinkBroadband — 10 MB test file (UK)
        TestEndpoint(
            name: "ThinkBroadband",
            url: "http://ipv4.download.thinkbroadband.com/10MB.zip",
            category: "CDN",
            expectedMinBytes: 5_000_000
        ),
    ]

    private init() {}

    // MARK: - Detect Throttling

    func detectThrottling(progressHandler: ((Double, String) -> Void)? = nil) async -> ThrottleAnalysis {
        let isVPNActive = await MainActor.run {
            SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        }

        // FIX (Phase 6.2): Skip the whole test under VPN. Throttle detection
        // works by comparing per-CDN throughput. Through a VPN, all traffic
        // exits at the same tunnel endpoint — the differences just reflect
        // VPN-server-to-CDN paths, not ISP behavior. Reporting 0.7 Mbps for
        // Apple while the user has a 122 Mbps line is worse than reporting
        // nothing.
        if isVPNActive {
            progressHandler?(1.0, "Skipped (VPN active)")
            return ThrottleAnalysis(
                results: [],
                throttlingDetected: false,
                throttledServices: [],
                baselineSpeed: 0,
                validTestCount: 0,
                summary: "Throttle Test only runs when VPN is disconnected.",
                explanation: "Throttle detection compares per-CDN download speeds to spot ISP-level slowdowns. With VPN active, all traffic exits through the tunnel — per-CDN comparisons reflect the VPN server's routing, not your ISP. VPN bypasses ISP throttling anyway, so the test isn't useful here.",
                timestamp: Date(),
                recommendation: "Disconnect your VPN and run this test again to check if your ISP is throttling specific services.",
                isVPNActive: true,
                confidence: .skipped
            )
        }

        var results: [ThrottleResult] = []
        let totalEndpoints = Double(Self.endpoints.count)

        for (index, endpoint) in Self.endpoints.enumerated() {
            progressHandler?(Double(index) / totalEndpoints, "Testing \(endpoint.name)...")

            let result = await testEndpoint(endpoint)
            results.append(result)
        }

        progressHandler?(0.9, "Analyzing results...")

        // Analyze results
        let analysis = analyzeResults(results: results, isVPNActive: isVPNActive)

        progressHandler?(1.0, "Complete")

        return analysis
    }

    // MARK: - Test Single Endpoint

    private func testEndpoint(_ endpoint: TestEndpoint) async -> ThrottleResult {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)

        guard let url = URL(string: endpoint.url) else {
            return ThrottleResult(
                endpoint: endpoint.name,
                category: endpoint.category,
                url: endpoint.url,
                speedMbps: nil,
                bytesReceived: 0,
                expectedMinBytes: endpoint.expectedMinBytes,
                status: .failed,
                throttled: false,
                percentSlower: nil,
                note: "Invalid URL"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode),
                  elapsed > 0 else {
                return ThrottleResult(
                    endpoint: endpoint.name,
                    category: endpoint.category,
                    url: endpoint.url,
                    speedMbps: nil,
                    bytesReceived: data.count,
                    expectedMinBytes: endpoint.expectedMinBytes,
                    status: .failed,
                    throttled: false,
                    percentSlower: nil,
                    note: "Invalid response"
                )
            }

            // IMPROVED: Check if we got actual data or an error page
            if data.count < endpoint.expectedMinBytes {
                return ThrottleResult(
                    endpoint: endpoint.name,
                    category: endpoint.category,
                    url: endpoint.url,
                    speedMbps: nil,
                    bytesReceived: data.count,
                    expectedMinBytes: endpoint.expectedMinBytes,
                    status: .endpointError,
                    throttled: false,
                    percentSlower: nil,
                    note: "Returned only \(data.count) bytes — not a valid speed test"
                )
            }

            let bytes = Double(data.count)
            let mbps = (bytes * 8) / (elapsed * 1_000_000)

            return ThrottleResult(
                endpoint: endpoint.name,
                category: endpoint.category,
                url: endpoint.url,
                speedMbps: mbps,
                bytesReceived: data.count,
                expectedMinBytes: endpoint.expectedMinBytes,
                status: .success,
                throttled: false,  // Will be updated in analysis
                percentSlower: nil,
                note: nil
            )
        } catch let error as URLError where error.code == .timedOut {
            return ThrottleResult(
                endpoint: endpoint.name,
                category: endpoint.category,
                url: endpoint.url,
                speedMbps: nil,
                bytesReceived: 0,
                expectedMinBytes: endpoint.expectedMinBytes,
                status: .timeout,
                throttled: false,
                percentSlower: nil,
                note: "Request timed out after 15 seconds"
            )
        } catch {
            return ThrottleResult(
                endpoint: endpoint.name,
                category: endpoint.category,
                url: endpoint.url,
                speedMbps: nil,
                bytesReceived: 0,
                expectedMinBytes: endpoint.expectedMinBytes,
                status: .failed,
                throttled: false,
                percentSlower: nil,
                note: error.localizedDescription
            )
        }
    }

    // MARK: - Analyze Results

    private func analyzeResults(results: [ThrottleResult], isVPNActive: Bool) -> ThrottleAnalysis {
        // Only consider successful tests with valid data
        let validResults = results.filter { $0.status == .success && $0.speedMbps != nil }
        let validTestCount = validResults.count

        guard validTestCount >= 2 else {
            return ThrottleAnalysis(
                results: results,
                throttlingDetected: false,
                throttledServices: [],
                baselineSpeed: 0,
                validTestCount: validTestCount,
                summary: "Not enough valid test results to determine throttling.",
                explanation: "We couldn't complete enough speed tests to draw conclusions. This may be due to network issues or endpoint unavailability.",
                timestamp: Date(),
                recommendation: generateRecommendation(
                    throttlingDetected: false,
                    throttledServices: [],
                    isVPNActive: isVPNActive,
                    isInconclusive: true
                ),
                isVPNActive: isVPNActive,
                confidence: .inconclusive
            )
        }

        let speeds = validResults.compactMap { $0.speedMbps }
        let maxSpeed = speeds.max() ?? 0
        let minSpeed = speeds.min() ?? 0
        let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)

        // IMPROVED: Better throttling detection logic
        // Throttling criteria (must meet ALL):
        // 1. Max speed is at least 5 Mbps (meaningful test)
        // 2. At least one service is >70% slower than max
        // 3. At least 2 services are reasonably fast (establishes baseline)

        let fastServices = validResults.filter { ($0.speedMbps ?? 0) > maxSpeed * 0.5 }
        let slowServices = validResults.filter { ($0.speedMbps ?? 0) < maxSpeed * 0.3 }

        let isLikelyThrottled = maxSpeed > 5
            && fastServices.count >= 2
            && slowServices.count >= 1

        // Mark throttled endpoints and update results
        var throttledServices: [String] = []
        var updatedResults: [ThrottleResult] = []

        for result in results {
            guard let speed = result.speedMbps, result.status == .success else {
                updatedResults.append(result)
                continue
            }

            let ratio = speed / maxSpeed
            let percentSlower = (1.0 - ratio) * 100

            // Only mark as throttled if it meets strict criteria
            let isThrottled = isLikelyThrottled && ratio < 0.3

            if isThrottled {
                throttledServices.append(result.endpoint)
            }

            updatedResults.append(ThrottleResult(
                endpoint: result.endpoint,
                category: result.category,
                url: result.url,
                speedMbps: speed,
                bytesReceived: result.bytesReceived,
                expectedMinBytes: result.expectedMinBytes,
                status: .success,
                throttled: isThrottled,
                percentSlower: percentSlower,
                note: result.note
            ))
        }

        // Generate summary and explanation
        let (summary, explanation) = generateSummaryAndExplanation(
            throttlingDetected: isLikelyThrottled,
            throttledServices: throttledServices,
            baselineSpeed: maxSpeed,
            minSpeed: minSpeed,
            avgSpeed: avgSpeed,
            validTestCount: validTestCount,
            isVPNActive: isVPNActive
        )

        let recommendation = generateRecommendation(
            throttlingDetected: isLikelyThrottled,
            throttledServices: throttledServices,
            isVPNActive: isVPNActive,
            isInconclusive: false
        )

        let confidence: ThrottleAnalysis.Confidence
        if validTestCount >= 4 && fastServices.count >= 3 {
            confidence = .high
        } else if validTestCount >= 3 && fastServices.count >= 2 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return ThrottleAnalysis(
            results: updatedResults,
            throttlingDetected: isLikelyThrottled,
            throttledServices: throttledServices,
            baselineSpeed: maxSpeed,
            validTestCount: validTestCount,
            summary: summary,
            explanation: explanation,
            timestamp: Date(),
            recommendation: recommendation,
            isVPNActive: isVPNActive,
            confidence: confidence
        )
    }

    // MARK: - Generate Summary and Explanation

    private func generateSummaryAndExplanation(
        throttlingDetected: Bool,
        throttledServices: [String],
        baselineSpeed: Double,
        minSpeed: Double,
        avgSpeed: Double,
        validTestCount: Int,
        isVPNActive: Bool
    ) -> (summary: String, explanation: String) {

        let summary: String
        let explanation: String

        if throttlingDetected {
            let services = throttledServices.joined(separator: ", ")
            summary = "Speed differences detected. \(services) may be slower than your baseline (\(String(format: "%.1f", baselineSpeed)) Mbps)."

            if isVPNActive {
                explanation = "We detected speed differences even through your VPN. This is often due to:\n" +
                    "• Different CDN server locations (some servers are closer to your VPN exit point)\n" +
                    "• Network routing differences\n" +
                    "• Temporary server load\n\n" +
                    "This is usually NOT ISP throttling since your traffic is encrypted through the VPN."
            } else {
                explanation = "Some services loaded significantly slower than others. This COULD mean your ISP is throttling specific traffic, but it could also be caused by:\n" +
                    "• The service's servers being far away or busy\n" +
                    "• Network routing issues\n" +
                    "• Temporary congestion\n\n" +
                    "To confirm ISP throttling, try running this test with a VPN enabled and compare the results."
            }
        } else {
            summary = "No throttling detected. Speeds are consistent across tested services (baseline: \(String(format: "%.1f", baselineSpeed)) Mbps)."

            if isVPNActive {
                explanation = "All services show consistent performance through your VPN. Your VPN is providing equal access to all tested endpoints."
            } else {
                explanation = "All the services we tested load at similar speeds. Your ISP appears to be treating all traffic fairly without selective throttling."
            }
        }

        return (summary, explanation)
    }

    // MARK: - Generate Recommendation

    private func generateRecommendation(
        throttlingDetected: Bool,
        throttledServices: [String],
        isVPNActive: Bool,
        isInconclusive: Bool
    ) -> String {

        if isInconclusive {
            return "We couldn't complete enough tests to determine if throttling is occurring. Please check your network connection and try again."
        }

        if !throttlingDetected {
            if isVPNActive {
                return "No throttling detected through your VPN connection. Your VPN is providing consistent speeds across all services."
            } else {
                return "No throttling detected. Your ISP appears to treat all traffic equally. No action needed."
            }
        }

        // Throttling detected
        if isVPNActive {
            return "Speed differences detected even through your VPN. This is likely due to:\n" +
                "• Different server locations for each service\n" +
                "• Your VPN server being closer to some CDNs than others\n\n" +
                "Try switching to a different VPN server location and running the test again to compare."
        } else {
            return "Your ISP may be slowing down certain services. A VPN can bypass this by encrypting your traffic so your ISP can't identify which service you're using.\n\n" +
                "Try connecting to a VPN and run this test again to compare results."
        }
    }
}
