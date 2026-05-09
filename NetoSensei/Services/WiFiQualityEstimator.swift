//
//  WiFiQualityEstimator.swift
//  NetoSensei
//
//  Estimates WiFi quality from gateway response patterns (no RSSI needed)
//

import Foundation
import Network

// MARK: - WiFi Quality Result

struct WiFiQualityResult {
    let quality: Quality
    let medianLatencyMs: Double
    let stdDevMs: Double
    let minMs: Double
    let maxMs: Double
    let sampleCount: Int
    let timeoutCount: Int
    let description: String
    let recommendation: String?

    enum Quality: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case critical = "Critical"
        case unknown = "Unknown"

        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "green"
            case .fair: return "yellow"
            case .poor: return "orange"
            case .critical: return "red"
            case .unknown: return "gray"
            }
        }

        var icon: String {
            switch self {
            case .excellent: return "wifi"
            case .good: return "wifi"
            case .fair: return "wifi.exclamationmark"
            case .poor: return "wifi.exclamationmark"
            case .critical: return "wifi.slash"
            case .unknown: return "wifi.exclamationmark"
            }
        }
    }

    // Summary for display
    var summary: String {
        if timeoutCount > 0 {
            return "\(quality.rawValue) (\(Int(medianLatencyMs))ms, \(timeoutCount) timeouts)"
        } else {
            return "\(quality.rawValue) (\(Int(medianLatencyMs))ms median, σ=\(String(format: "%.1f", stdDevMs))ms)"
        }
    }
}

// MARK: - WiFi Quality Estimator

class WiFiQualityEstimator {
    static let shared = WiFiQualityEstimator()

    // DISABLED: NWConnection spam was freezing the app
    // Set to true once the freeze issue is fixed
    private static let NWCONNECTION_TESTS_ENABLED = false

    private init() {}

    /// Run 10 rapid gateway latency tests and analyze the pattern
    func estimateQuality(gatewayIP: String) async -> WiFiQualityResult {
        // DISABLED: NWConnection tests causing app freeze
        // Creates 10 connections that can flood the system
        guard Self.NWCONNECTION_TESTS_ENABLED else {
            debugLog("⚠️ WiFi quality test DISABLED — NWConnection causing freeze")
            return WiFiQualityResult(
                quality: .unknown,
                medianLatencyMs: 0,
                stdDevMs: 0,
                minMs: 0,
                maxMs: 0,
                sampleCount: 0,
                timeoutCount: 0,
                description: "WiFi quality test temporarily disabled",
                recommendation: nil
            )
        }

        var latencies: [Double] = []
        var timeouts = 0
        let sampleCount = 10

        for _ in 0..<sampleCount {
            let latency = await measureGatewayLatency(gatewayIP: gatewayIP)
            if let ms = latency {
                latencies.append(ms)
            } else {
                timeouts += 1
            }
            // Small delay between tests
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        guard !latencies.isEmpty else {
            return WiFiQualityResult(
                quality: .critical,
                medianLatencyMs: 0,
                stdDevMs: 0,
                minMs: 0,
                maxMs: 0,
                sampleCount: sampleCount,
                timeoutCount: timeouts,
                description: "Cannot reach your router. WiFi may be disconnected.",
                recommendation: "Check your WiFi connection and try again."
            )
        }

        let sorted = latencies.sorted()
        guard let minMs = sorted.first, let maxMs = sorted.last else {
            return WiFiQualityResult(
                quality: .critical,
                medianLatencyMs: 0,
                stdDevMs: 0,
                minMs: 0,
                maxMs: 0,
                sampleCount: sampleCount,
                timeoutCount: timeouts,
                description: "Cannot reach your router. WiFi may be disconnected.",
                recommendation: "Check your WiFi connection and try again."
            )
        }
        let median = sorted[sorted.count / 2]
        let mean = latencies.reduce(0, +) / Double(latencies.count)
        let variance = latencies.map { pow($0 - mean, 2) }.reduce(0, +) / Double(latencies.count)
        let stdDev = sqrt(variance)

        // Classify based on median and consistency
        let quality: WiFiQualityResult.Quality
        let description: String
        var recommendation: String? = nil

        if timeouts > 2 {
            quality = .critical
            description = "\(timeouts)/\(sampleCount) requests to your router timed out. Your WiFi connection is very unstable."
            recommendation = "Move closer to your router. Check for heavy interference (microwaves, many Bluetooth devices)."
        } else if median < 5 && stdDev < 2 {
            quality = .excellent
            description = "Your WiFi link to the router is fast and consistent (\(String(format: "%.0f", median))ms, σ=\(String(format: "%.1f", stdDev))ms)."
        } else if median < 15 && stdDev < 8 {
            quality = .good
            description = "WiFi is working well. Response time to router: \(String(format: "%.0f", median))ms with minor variation."
        } else if median < 30 && stdDev < 15 {
            quality = .fair
            description = "WiFi has some congestion or interference. Router responds in \(String(format: "%.0f", median))ms but varies (σ=\(String(format: "%.0f", stdDev))ms)."
            recommendation = "Try: Switch to 5GHz band if available. Reduce number of connected devices."
        } else if median < 50 || stdDev > 15 {
            quality = .poor
            description = "WiFi is congested or you're far from the router. High variation in response times (\(String(format: "%.0f", minMs))-\(String(format: "%.0f", maxMs))ms)."
            recommendation = "Move closer to your router. Restart the router. Disconnect unused devices."
        } else {
            quality = .critical
            description = "WiFi link is severely degraded (\(String(format: "%.0f", median))ms median). This is likely your main bottleneck."
            recommendation = "Your router may be overloaded. Restart it. If persistent, consider upgrading your router or adding a WiFi extender."
        }

        return WiFiQualityResult(
            quality: quality,
            medianLatencyMs: median,
            stdDevMs: stdDev,
            minMs: minMs,
            maxMs: maxMs,
            sampleCount: sampleCount,
            timeoutCount: timeouts,
            description: description,
            recommendation: recommendation
        )
    }

    /// Quick estimation using existing gateway latency data
    func estimateFromLatency(gatewayLatency: Double, jitter: Double?) -> WiFiQualityResult {
        let stdDev = jitter ?? 0

        let quality: WiFiQualityResult.Quality
        let description: String
        var recommendation: String? = nil

        if gatewayLatency < 5 && stdDev < 2 {
            quality = .excellent
            description = "WiFi link is fast and consistent."
        } else if gatewayLatency < 15 && stdDev < 8 {
            quality = .good
            description = "WiFi is working well."
        } else if gatewayLatency < 30 {
            quality = .fair
            description = "WiFi has some congestion."
            recommendation = "Try switching to 5GHz band."
        } else if gatewayLatency < 50 {
            quality = .poor
            description = "WiFi is congested or you're far from router."
            recommendation = "Move closer to router or restart it."
        } else {
            quality = .critical
            description = "WiFi link is severely degraded."
            recommendation = "Restart router. Consider WiFi extender."
        }

        return WiFiQualityResult(
            quality: quality,
            medianLatencyMs: gatewayLatency,
            stdDevMs: stdDev,
            minMs: gatewayLatency,
            maxMs: gatewayLatency,
            sampleCount: 1,
            timeoutCount: 0,
            description: description,
            recommendation: recommendation
        )
    }

    // MARK: - Gateway Latency Measurement
    // FIXED: NWConnection removed - was causing app freeze

    private func measureGatewayLatency(gatewayIP: String) async -> Double? {
        // NWConnection removed - was causing app freeze
        // This function is only called when NWCONNECTION_TESTS_ENABLED = true (currently false)
        return nil
    }
}
