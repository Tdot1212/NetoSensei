import Testing
import Foundation
import Darwin
@testable import NetoSensei

struct WiFiAssistantTests {
    private func result(_ speed: Double, ssid: String? = "Home", server: String = "Test", vpn: Bool = false) -> SpeedTestResult {
        SpeedTestResult(downloadSpeed: speed, uploadSpeed: 10, ping: nil, jitter: nil, packetLoss: nil,
            serverUsed: server, testDuration: 10, connectionType: "WiFi", vpnActive: vpn,
            ipAddress: "203.0.113.1", networkSSID: ssid, localSubnet: "192.168.4", publicCountry: "US")
    }

    @Test func medianComparisonDoesNotPromiseCausation() throws {
        let c = try #require(WiFiSpeedComparison.evaluate(before: [result(50), result(10), result(20)], after: [result(40), result(30), result(100)]))
        #expect(c.beforeMbps == 20)
        #expect(c.afterMbps == 40)
        #expect(c.changePercent == 100)
        #expect(c.rangesOverlap)
    }

    @Test func rejectsMissingIdentityDifferentServerVPNAndIncompleteRuns() {
        let baseline = [result(10), result(11), result(12)]
        #expect(WiFiSpeedComparison.evaluate(before: baseline, after: [result(20), result(21)]) == nil)
        #expect(WiFiSpeedComparison.evaluate(before: baseline, after: [result(20, server: "Other"), result(21), result(22)]) == nil)
        #expect(WiFiSpeedComparison.evaluate(before: baseline, after: [result(20, vpn: true), result(21), result(22)]) == nil)
        let anonymous = [result(10, ssid: nil), result(11, ssid: nil), result(12, ssid: nil)]
        #expect(WiFiSpeedComparison.evaluate(before: anonymous, after: anonymous) == nil)
        #expect(WiFiSpeedComparison.evaluate(before: baseline, after: [result(.nan), result(20), result(30)]) == nil)
        #expect(WiFiSpeedComparison.evaluate(before: baseline, after: [result(0), result(20), result(30)]) == nil)
        var failed = result(99)
        failed.testUnavailableReason = "Path changed"
        #expect(WiFiSpeedComparison.evaluate(before: baseline, after: [failed, result(20), result(30)]) == nil)
    }

    @Test func reportsSlowdownAndNonOverlappingRanges() throws {
        let c = try #require(WiFiSpeedComparison.evaluate(before: [result(98), result(100), result(102)], after: [result(49), result(50), result(51)]))
        #expect(c.changePercent == -50)
        #expect(!c.rangesOverlap)
    }

    @Test func failedDNSCannotDisplayAsSlowLookup() {
        let dns = DNSInfo(resolverIP: nil, latency: 2000, lookupSuccess: false, recommendedDNS: nil)
        #expect(dns.displayableLatency == nil)
    }

    @Test func UDPAssociationCannotBecomeLatency() async throws {
        // Bind without listening: port is reserved, so TCP must fail. UDP
        // connect would succeed anyway, reproducing the old false response.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #expect(fd >= 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        #expect(bound == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        let measured = await NetworkLatencyProbe.shared.measureHandshake(host: "127.0.0.1", ports: [UInt16(bigEndian: addr.sin_port)], allowUDPFallback: true, timeout: 0.05)
        #expect(measured == nil)
    }

    @MainActor @Test func dashboardDoesNotKeepFailedDNSOrInventVPNOverhead() {
        let vm = DashboardViewModel()
        #expect(vm.vpnOverhead == nil)
        #expect(vm.vpnHealthScore == nil)
    }
}

struct MeasurementCoverageRegressionTests {
    @Test func absentSecurityChecksAreNotSecure() {
        let verdict = CombinedSecurityCheckViewModel.computeVerdict(wifi: nil, leak: nil, ipv6Leak: false, captive: nil, certs: [])
        #expect(verdict == .unknown)
    }

    @Test func missingLatencyAndLossDoNotPromiseCompetitiveGaming() {
        let result = SpeedTestResult(downloadSpeed: 200, uploadSpeed: 100, ping: nil, jitter: nil, packetLoss: nil,
            testDuration: 10, connectionType: "WiFi", vpnActive: false)
        let capability = ConnectionCapabilityAnalyzer.analyze(from: result)
        #expect(capability.gaming == .unknown)
        #expect(capability.videoCalls == .unknown)
        #expect(result.streamingCapability.gamingCapability == .unmeasured)
        #expect(result.streamingCapability.videoCallQuality == .unmeasured)
        #expect(capability.streaming4K.isCapable)
    }
}
