import Foundation

/// Advanced diagnostics share the primary speed-test implementation. This avoids
/// differing endpoints, timeout sentinels and HTTP-failure ratios sold as loss.
actor PerformanceEngine {
    static let shared = PerformanceEngine()
    private init() {}

    func runPerformanceTest(host: String) async -> Result<PerformanceMetrics, DiagnosticError> {
        let result = await SpeedTestEngine.shared.runSpeedTest()
        guard result.testUnavailableReason == nil, result.downloadSpeed.isFinite,
              result.downloadSpeed > 0 else { return .failure(.noResponse) }
        return .success(PerformanceMetrics(packetLoss: result.packetLoss,
            jitter: result.jitter.map { Int($0.rounded()) }, throughput: result.downloadSpeed,
            timestamp: result.timestamp))
    }
}
