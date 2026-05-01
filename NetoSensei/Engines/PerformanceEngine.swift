//
//  PerformanceEngine.swift
//  NetoSensei
//
//  Performance Engine - Packet loss, jitter, throughput
//

import Foundation
import Network

actor PerformanceEngine {
    static let shared = PerformanceEngine()

    private init() {}

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

    // MARK: - Packet Loss Test
    // FIXED: Reduced number of connections to prevent "already cancelled" spam

    func packetLossTest(host: String) async -> Result<Int, DiagnosticError> {
        do {
            // FIXED: Use only 5 sequential pings to avoid connection spam
            // 5 pings is sufficient for packet loss estimation
            let totalPackets = 5
            let timeout = 6  // 6 seconds for 5 sequential pings

            return try await withTimeout(seconds: timeout) {
                var successfulPackets = 0

                for _ in 0..<totalPackets {
                    if try await self.pingHost(host) {
                        successfulPackets += 1
                    }
                    // FIXED: Add small delay between pings to avoid connection spam
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms between pings
                }

                let lossCount = totalPackets - successfulPackets
                let lossPercentage = Int((Double(lossCount) / Double(totalPackets)) * 100)

                return .success(lossPercentage)
            }
        } catch {
            return .failure(.timeout)
        }
    }

    // FIXED: Use URLSession instead of NWConnection to prevent app freeze
    private func pingHost(_ host: String) async throws -> Bool {
        guard let url = URL(string: "https://\(host)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 1.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode != nil
        } catch {
            return false
        }
    }

    // MARK: - Jitter Test
    // FIXED: Reduced number of connections to prevent "already cancelled" spam

    func jitterTest(host: String) async -> Result<Int, DiagnosticError> {
        do {
            // FIXED: Use only 5 sequential pings to avoid connection spam
            let pingCount = 5
            let timeout = 6  // 6 seconds for 5 sequential pings

            return try await withTimeout(seconds: timeout) {
                var latencies: [Double] = []

                for _ in 0..<pingCount {
                    let start = Date()
                    _ = try await self.pingHost(host)
                    let duration = Date().timeIntervalSince(start) * 1000  // ms
                    latencies.append(duration)
                    // FIXED: Add small delay between pings to avoid connection spam
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms between pings
                }

                guard !latencies.isEmpty else {
                    return .failure(.noResponse)
                }

                // Calculate jitter (variance in latency)
                let avg = latencies.reduce(0, +) / Double(latencies.count)
                let variance = latencies.map { pow($0 - avg, 2) }.reduce(0, +) / Double(latencies.count)
                let jitter = sqrt(variance)

                return .success(Int(jitter))
            }
        } catch {
            return .failure(.timeout)
        }
    }

    // MARK: - Throughput Test

    func throughputTest(url: URL) async -> Result<Double, DiagnosticError> {
        do {
            // FIXED: Use shorter timeout on cellular
            let monitor = NWPathMonitor()
            let isCellular = monitor.currentPath.usesInterfaceType(.cellular)
            monitor.cancel()

            let timeout = isCellular ? 10 : 15  // Shorter timeout on cellular

            return try await withTimeout(seconds: timeout) {
                // Download a test file and measure speed
                let start = Date()

                let (data, _) = try await URLSession.shared.data(from: url)

                let duration = Date().timeIntervalSince(start)
                let megabytes = Double(data.count) / 1_000_000
                let megabitsPerSecond = (megabytes * 8) / duration

                return .success(megabitsPerSecond)
            }
        } catch {
            return .failure(.timeout)
        }
    }

    // MARK: - Combined Performance Test

    func runPerformanceTest(host: String) async -> Result<PerformanceMetrics, DiagnosticError> {
        // Run all tests
        let packetLossResult = await packetLossTest(host: host)
        let jitterResult = await jitterTest(host: host)

        // Throughput test using Cloudflare speed test
        guard let throughputURL = URL(string: "https://speed.cloudflare.com/__down?bytes=5000000") else {
            return .failure(.invalidData)
        }
        let throughputResult = await throughputTest(url: throughputURL)

        // Extract results
        let packetLoss: Double
        let jitter: Int
        let throughput: Double

        switch packetLossResult {
        case .success(let value):
            packetLoss = Double(value)
        case .failure:
            packetLoss = 100.0
        }

        switch jitterResult {
        case .success(let value):
            jitter = value
        case .failure:
            jitter = 999
        }

        switch throughputResult {
        case .success(let value):
            throughput = value
        case .failure:
            // Use -1.0 as sentinel value meaning "test blocked/failed"
            // NEVER use 0.0 - that looks like "no speed" which is misleading
            throughput = -1.0
        }

        let metrics = PerformanceMetrics(
            packetLoss: packetLoss,
            jitter: jitter,
            throughput: throughput,
            timestamp: Date()
        )

        return .success(metrics)
    }
}
