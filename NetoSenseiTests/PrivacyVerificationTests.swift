import Foundation
import Testing
@testable import NetoSensei

struct PrivacyVerificationTests {
    @Test func onlyPublicIPv6FromExpectedEndpointCounts() {
        let endpoint = PublicIPv6Probe.endpoint
        let address = "2606:4700::1111"
        let data = Data((address + "\n").utf8)
        #expect(PublicIPv6Probe.parse(data, status: 200, url: endpoint) == address)
        #expect(PublicIPv6Probe.parse(data, status: 403, url: endpoint) == nil)
        #expect(PublicIPv6Probe.parse(data, status: 200, url: URL(string: "https://example.com")) == nil)
        for invalid in ["192.0.2.1", "::1", "::ffff:192.0.2.1", "fe80::1", "<html>2001:db8::1</html>"] {
            #expect(PublicIPv6Probe.parse(Data(invalid.utf8), status: 200, url: endpoint) == nil)
        }
    }

    @Test func slowProbeCanMeasureCurrentRouteWithExplicitLabel() {
        let cloudflare = SpeedTestServerSelection.cloudflare
        let probe = SpeedTestServerSelection.Probe(candidate: cloudflare, reachable: true, rttMs: 920)
        let plan = SpeedTestServerSelection.transferPlan(probes: [probe], vpnActive: false,
            exitCountry: "CN", allowUnverifiedProximity: true)
        #expect(plan.first?.region == .currentRoute(probeMs: 920))
    }
}
