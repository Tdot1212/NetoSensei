import Testing
import Foundation
@testable import NetoSensei

private final class EndpointFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let mode = request.value(forHTTPHeaderField: "X-Endpoint-Fixture") ?? "valid"
        if mode == "timeout" { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
        let headers = ["Content-Type": mode == "html" ? "text/html" : "application/octet-stream", "Content-Encoding": mode == "gzip" ? "gzip" : "identity"]
        let response = HTTPURLResponse(url: request.url!, statusCode: mode == "denied" ? 403 : 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let count = mode == "short" || request.url!.path.contains("favicon") || request.url!.path.contains("generate_204") ? 20 : 6_000_000
        client?.urlProtocol(self, didLoad: Data(repeating: 0x55, count: count))
        client?.urlProtocolDidFinishLoading(self)
    }
}
private final class EndpointClock: @unchecked Sendable {
    private var value: Double = 0
    private let lock = NSLock()
    func tick() -> Double { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
struct EndpointBenchmarkVerificationTests {
    private func session(_ mode: String) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EndpointFixture.self]; config.httpAdditionalHeaders = ["X-Endpoint-Fixture": mode]
        return URLSession(configuration: config)
    }
    @Test func actualByteMathWorksThroughVPNWithoutAttributingISPPolicy() async {
        let clock = EndpointClock(), transport = session("valid")
        defer { transport.invalidateAndCancel() }
        let result = await ThrottleDetectionService(session: transport, vpn: { true }, clock: { clock.tick() }).detectThrottling()
        #expect(ThrottleDetectionService.endpoints.count >= 3)
        #expect(result.results.allSatisfy { URL(string: $0.url)?.scheme == "https" })
        #expect(result.validTestCount == ThrottleDetectionService.endpoints.count && result.results.allSatisfy { $0.speedMbps == 48 })
        #expect(!result.wasSkipped && result.overallStatus == "Similar sampled speeds")
        #expect(!result.summary.contains("No throttling") && result.isVPNActive)
    }
    @Test func rejectedShortCompressedTextAndTimedOutSamplesStayUnavailable() async {
        for mode in ["short", "gzip", "html", "denied", "timeout"] {
            let clock = EndpointClock(), transport = session(mode)
            let result = await ThrottleDetectionService(session: transport, vpn: { false }, clock: { clock.tick() }).detectThrottling()
            #expect(result.validTestCount == 0 && result.results.allSatisfy { $0.speedMbps == nil })
            #expect(result.overallStatus == "Inconclusive")
            transport.invalidateAndCancel()
        }
    }
    @MainActor @Test func siteHTTPDenialIsNotAUsableServiceOrAFastBadge() async {
        let clock = EndpointClock(), transport = session("denied")
        defer { transport.invalidateAndCancel() }
        let benchmark = VPNBenchmark(session: transport, clock: { clock.tick() })
        await benchmark.runBenchmark(destinations: [.google])
        #expect(benchmark.results.first?.responseTimeMs == 1000)
        await benchmark.runBenchmark(destinations: [.google, .github])
        #expect(benchmark.results.map(\.destination) == [.google, .github])
        #expect(benchmark.progress == 1 && !benchmark.isRunning)
        #expect(benchmark.results.allSatisfy {
            $0.httpStatus == 403 && $0.qualityRating == "HTTP 403" && ($0.responseTimeMs ?? 0) > 0
        })
    }
    @MainActor @Test func siteTimeoutCannotBecomeResponseLatency() async {
        let clock = EndpointClock(), transport = session("timeout")
        defer { transport.invalidateAndCancel() }
        let benchmark = VPNBenchmark(session: transport, clock: { clock.tick() })
        await benchmark.runBenchmark(destinations: [.google])
        #expect(benchmark.results.first?.latencyMs == nil && benchmark.results.first?.responseTimeMs == nil)
        #expect(benchmark.results.first?.reachable == false)
    }
    @Test func cautionAndUnknownIPv6DoNotEstablishAnUnsafeNetwork() {
        let wifi = WiFiSafetyResult(overallStatus: .caution, checks: [])
        let cert = CertificateInspection(hostname: "fixture", realIssuer: "Proxy-like", isProxyIntercepted: true, proxyAppName: nil, severity: .warning, summary: "Review")
        let verdict = CombinedSecurityCheckViewModel.computeVerdict(wifi: wifi, leak: nil, ipv6Leak: false, captive: nil, certs: [cert])
        #expect(verdict == .partial)
    }
}

struct DoTResponseVerificationTests {
    @Test func TLSHandshakeAloneCannotEstablishDNSProtocolSupport() throws {
        let query = try DNSWireCodec.query(domain: "example.com", id: 0)
        var reply = query
        reply[2] = 0x81; reply[3] = 0x80; reply[7] = 1
        reply.append(contentsOf:[0xC0,0x0C,0,1,0,1,0,0,0,60,0,4,192,0,2,1])
        let prefix = Data([UInt8(reply.count >> 8),UInt8(reply.count & 255)])
        #expect(DNSEncryptionChecker.validDoTResponse(prefix:prefix,body:reply,query:query))
        #expect(!DNSEncryptionChecker.validDoTResponse(prefix:prefix,body:Data("TLS ready".utf8),query:query))
        #expect(!DNSEncryptionChecker.validDoTResponse(prefix:Data([0,1]),body:reply,query:query))
        for count in 0..<reply.count {
            #expect(!DNSEncryptionChecker.validDoTResponse(prefix:prefix,body:reply.prefix(count),query:query))
        }
    }
}

struct KillSwitchEvidenceVerificationTests {
    @MainActor @Test func reconnectionAndPageFailureDoNotBecomeProtectionProof() {
        let advice = KillSwitchAdvisor.shared.checkKillSwitchGuidance()
        #expect(advice.guidance.contains("On-Demand alone does not prove"))
        #expect(advice.manualTestSteps.contains { $0.contains("failed page alone is inconclusive") })
        #expect(!advice.manualTestSteps.contains { $0.contains("kill-switch is working") })
    }
}

struct CertificateCountVerificationTests {
    @Test func untrustedProxyAndMissingChainsNeverProduceNegativeOrDoubleCounts() {
        func cert(_ proxy: Bool,_ severity: CertificateInspection.Severity) -> CertificateInspection {
            .init(hostname:"fixture",realIssuer:"Fixture",isProxyIntercepted:proxy,proxyAppName:nil,severity:severity,summary:"Fixture")
        }
        let counts=CertificateInspection.counts([cert(true,.critical),cert(true,.warning),cert(false,.info),cert(false,.unavailable)])
        #expect(counts.proxyLike==1 && counts.otherTrusted==1 && counts.untrusted==1 && counts.unavailable==1)
        #expect(counts.proxyLike+counts.otherTrusted+counts.untrusted+counts.unavailable==4)
    }
}

@Test func skippedPortalDoesNotGenerateLoginOrVPNConnectAdvice() {
    let skipped = CaptivePortalResult(verdict: .inconclusiveVPNActive, portalURL: nil,
        confidence: .medium, recommendation: "", probedAt: Date())
    let advice = CombinedSecurityCheckViewModel.recommendedSteps(
        leak: nil, captive: skipped, certs: [], vpnLikelyActive: true)
    #expect(advice.count == 1)
    #expect(advice.first?.contains("Open the VPN app") == true)
    #expect(!advice.contains { $0.contains("sign in") })
}

@Test func detectedPortalGetsSettingsAndVerificationSteps() {
    let detected = CaptivePortalResult(verdict: .portalDetected, portalURL: nil,
        confidence: .high, recommendation: "", probedAt: Date())
    let advice = CombinedSecurityCheckViewModel.recommendedSteps(
        leak: nil, captive: detected, certs: [], vpnLikelyActive: false)
    #expect(advice.first?.contains("Settings → Wi-Fi") == true)
    #expect(advice.first?.contains("run this check again") == true)
}
