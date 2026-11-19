import Testing
import Foundation
@testable import NetoSensei

struct AccuracyRegressionTests {
    @Test func throughputUnitsAndInvalidDurations() {
        #expect(MeasurementStatistics.throughputMbps(bytes: 1_000_000, duration: 1) == 8)
        #expect(MeasurementStatistics.throughputMbps(bytes: 25_000_000, duration: 2) == 100)
        for interval in [0.0, -1, .nan, .infinity] {
            #expect(MeasurementStatistics.throughputMbps(bytes: 1_000_000, duration: interval) == nil)
        }
        #expect(MeasurementStatistics.throughputMbps(bytes: 0, duration: 1) == nil)
        #expect(MeasurementStatistics.throughputMbps(bytes: -1, duration: 1) == nil)
    }

    @Test func unknownSamplesDoNotBecomeZerosOrInflateDenominators() {
        #expect(MeasurementStatistics.mean([nil, 10, nil, 30]) == 20)
        #expect(MeasurementStatistics.mean([nil, .nan, .infinity]) == nil)
        #expect(MeasurementStatistics.mean([0, 0]) == 0)
        #expect(MeasurementStatistics.mean([Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude])?.isFinite == true)
        #expect(MeasurementStatistics.standardDeviation([]) == nil)
        #expect(MeasurementStatistics.standardDeviation([20]) == nil)
        #expect(MeasurementStatistics.standardDeviation([20, 20]) == 0)
        #expect(MeasurementStatistics.standardDeviation([10, 30]) == 10)
    }

    @Test func medianUsesBothMiddleSamplesAndOneSampleHasNoJitter() {
        let result = SpeedTestEngine.pingVerdict(samplesMs: [40, 10, 30, 20], gatewayRTTms: nil, vpnActive: false)
        #expect(result.ping == 25)
        #expect(SpeedTestEngine.pingVerdict(samplesMs: [20], gatewayRTTms: nil, vpnActive: false).jitter == nil)
        #expect(SpeedTestEngine.pingVerdict(samplesMs: [.nan, -.infinity, -4], gatewayRTTms: nil, vpnActive: false).ping == nil)
    }

    @Test func realSlowLatencySurvivesCurrentRecordMigration() throws {
        var result = speed(1_200)
        result.measurementVersion = 2
        #expect(LatencyValidation.normalize(1_200) == 1_200)
        #expect(LegacySpeedRecordMigration.sanitize(result) == nil)
        let restored = try JSONDecoder().decode(SpeedTestResult.self, from: JSONEncoder().encode(result))
        #expect(restored.measurementVersion == 2)
        #expect(restored.ping == 1_200)
        result.measurementVersion = nil
        #expect(LegacySpeedRecordMigration.sanitize(result)?.ping == nil)
    }

    @Test func latencyValidationRejectsNonPhysicalValues() {
        for value in [-1.0, Double.nan, .infinity, -.infinity] {
            #expect(LatencyValidation.normalize(value) == nil)
        }
        #expect(LatencyValidation.normalize(nil) == nil)
    }

    @Test func historyNilRoundTripAndLegacyZeroLatency() throws {
        let entry = history(score: nil, gateway: nil, dns: nil)
        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        let restored = try JSONDecoder().decode(NetworkHistoryEntry.self, from: data)
        #expect(restored.healthScore == nil && restored.gatewayLatency == nil && restored.dnsLatency == nil)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["gatewayLatency"] = 0
        json["dnsLatency"] = 0
        let legacy = try JSONDecoder().decode(NetworkHistoryEntry.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.gatewayLatency == nil && legacy.dnsLatency == nil)
        #expect(MeasurementStatistics.mean([history(score: 80, gateway: 10, dns: 30).gatewayLatency, legacy.gatewayLatency]) == 10)
    }

    @Test func incompleteAdvancedMetricsCannotRateExcellent() {
        let empty = PerformanceMetrics(packetLoss: nil, jitter: nil, throughput: nil, timestamp: Date())
        #expect(empty.qualityRating == "Incomplete measurements")
        #expect(!empty.userFriendlyDescription.contains("999"))
        #expect(empty.userFriendlyDescription.contains("Unmeasured"))
    }

    @Test func comparisonRequiresTwoCompleteRecentSameServerMeasurements() {
        let wifi = connection(.wifi, download: 100, upload: 20, latency: 20)
        let missing = connection(.cellular, download: nil, upload: nil, latency: nil)
        #expect(ConnectionComparator.generateComparison(wifi: wifi, cellular: missing).winner == nil)
        let incomplete = connection(.cellular, download: 200, upload: nil, latency: nil)
        #expect(ConnectionComparator.generateComparison(wifi: wifi, cellular: incomplete).winner == nil)
        #expect(ConnectionComparator.generateComparison(wifi: wifi, cellular: incomplete).recommendation.title == "Overall rating unavailable")
        let cell = connection(.cellular, download: 50, upload: 10, latency: 60)
        #expect(ConnectionComparator.generateComparison(wifi: wifi, cellular: cell).winner == .wifi)
        var other = cell
        other.serverUsed = "Different"
        #expect(ConnectionComparator.generateComparison(wifi: wifi, cellular: other).winner == nil)
        #expect(ConnectionComparator.generateComparison(wifi: wifi, cellular: other).recommendation.title == "Different test servers")
        let tie = connection(.cellular, download: 100, upload: 20, latency: 20)
        #expect(ConnectionComparator.generateComparison(wifi: wifi, cellular: tie).winner == nil)
    }

    @Test func historyWithoutScoresCannotProduceStableTrend() {
        let insights = HistoryInsightsEngine.analyze(entries: Array(repeating: history(score: nil, gateway: nil, dns: nil), count: 10))
        #expect(insights.trend == .insufficient && insights.averageScore == nil && insights.vpnImpact == nil)
    }

    @Test func endpointInputsRejectURLsPathsAndInvalidLabels() {
        for value in ["", "https://apple.com", "apple.com/path", "a..com", "-a.com", "a-.com", "a.com?x=y", "a com", String(repeating: "a", count: 64)+".com"] {
            #expect(!TracerouteService.validHostname(value))
        }
        for value in ["apple.com", "192.168.1.1", "router.local", "xn--example.com"] {
            #expect(TracerouteService.validHostname(value))
        }
    }

    @Test func independentEndpointsNeverHaveAnInventedBottleneck() {
        let result = TracerouteResult(timestamp: Date(), destination: "apple.com", hops: [
            TracerouteHop(hopNumber: 1, ipAddress: "192.168.1.254", latency: nil),
            TracerouteHop(hopNumber: 2, ipAddress: "apple.com", latency: 100)
        ], totalLatency: 100)
        #expect(result.bottleneckHop == nil)
        #expect(result.hops[0].status == .unknown)
        #expect(result.hops[0].latency == nil && result.hops[0].latencyChange == nil)
    }

    @Test func timeoutsRejectInvalidIntervalsWithoutCrashing() async {
        for interval in [0.0, -1, .nan, .infinity] {
            do {
                _ = try await withTimeout(seconds: interval) { 42 }
                Issue.record("Invalid timeout was accepted")
            } catch { }
        }
        do {
            let result = try await withTimeout(seconds: 1) { 42 }
            #expect(result == 42)
        } catch { Issue.record("Immediate operation should succeed") }
    }

    @Test func beforeAfterPercentMatchesKnownChangesAcrossRange() throws {
        for percent in stride(from: -90, through: 200, by: 10) {
            var before = speed(20)
            before.downloadSpeed = 100
            before.serverUsed = "Same"
            var after = before
            after.downloadSpeed = 100 + Double(percent)
            let compared = try #require(WiFiSpeedComparison.evaluate(before: [before,before,before], after: [after,after,after]))
            #expect(abs(compared.changePercent - Double(percent)) < 0.00001)
        }
    }

    private func speed(_ ping: Double) -> SpeedTestResult {
        SpeedTestResult(downloadSpeed: 100, uploadSpeed: 20, ping: ping, jitter: 10, packetLoss: nil,
            serverUsed: "Test", testDuration: 10, connectionType: "WiFi", vpnActive: false,
            networkSSID: "Known", localSubnet: "192.168.2")
    }
    private func history(score: Int?, gateway: Double?, dns: Double?) -> NetworkHistoryEntry {
        NetworkHistoryEntry(healthScore: score, downloadSpeed: nil, uploadSpeed: nil, latency: nil,
            gatewayLatency: gateway, dnsLatency: dns, jitter: nil, packetLoss: nil, vpnActive: false,
            vpnOverhead: nil, rootCause: "Unknown", connectionType: "WiFi", wifiSSID: "Known")
    }
    private func connection(_ type: ConnectionTestResult.ConnectionType, download: Double?, upload: Double?, latency: Double?) -> ConnectionTestResult {
        var result = ConnectionTestResult(connectionType: type, downloadSpeedMbps: download, uploadSpeedMbps: upload,
            latencyMs: latency, jitterMs: 10, packetLoss: nil, timestamp: Date(), error: download == nil ? "Unavailable" : nil)
        result.serverUsed = "Same"
        return result
    }
}

struct SharedMedianVerificationTests {
    @Test func evenOddUnavailableAndLargeValuesHaveCorrectMedians() {
        #expect(MeasurementStatistics.median([1,4,2,3]) == 2.5)
        #expect(MeasurementStatistics.median([4,1,2]) == 2)
        #expect(MeasurementStatistics.median([]) == nil)
        #expect(MeasurementStatistics.median([.nan, .infinity]) == nil)
        #expect(MeasurementStatistics.median([1e308,1e308]) == 1e308)
    }
}
