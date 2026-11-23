import Foundation
import Testing
@testable import NetoSensei

struct ConnectionInvestigationTests {
    private let first = InvestigationRoute(generation: .distantPast, interface: "WiFi", wifi: "Test",
        vpn: .off, exit: nil)

    @Test func aSingleSiteFailureLeadsToASecondConnection() {
        let evidence: [InvestigationMetric: InvestigationReading] = [
            .site: .init(label: "Affected site", detail: "No response", outcome: false),
            .reference: .init(label: "Reference", detail: "HTTP 200", outcome: true),
            .lookup: .init(label: "System lookup", detail: "No address returned", outcome: false)
        ]
        let sample = InvestigationSample(route: first, at: .now, readings: evidence)
        let lead = InvestigationReasoning.lead(for: .connection, sample: sample)
        #expect(lead.change == .otherAccess)
        #expect(lead.evidence.contains("hostname lookup"))
        #expect(InvestigationReasoning.compare(sample, sample, using: lead).0 == .couldNotCompare)
        let cellular = InvestigationRoute(generation: .now, interface: "Cellular", wifi: nil, vpn: .off, exit: nil)
        var retest = evidence
        retest[.site] = .init(label: "Affected site", detail: "HTTP 200", outcome: true)
        #expect(InvestigationReasoning.compare(sample,
            .init(route: cellular, at: .now, readings: retest), using: lead).0 == .improved)
    }

    @Test func speedUsesRepeatedRangesAndRejectsADifferentRouteDuringTheSameComparison() {
        func sample(_ route: InvestigationRoute, _ numbers: [Double]) -> InvestigationSample {
            .init(route: route, at: .now, readings: [
                .single: .init(label: "Single", detail: "Measured", samples: numbers, outcome: true),
                .parallel: .init(label: "Parallel", detail: "Measured", samples: [11, 13, 14], outcome: true)
            ])
        }
        let baseline = sample(first, [9, 11, 13])
        let lead = InvestigationReasoning.lead(for: .speed, sample: baseline)
        #expect(lead.change == .pauseTransfers)
        #expect(InvestigationReasoning.compare(baseline, sample(first, [10, 12, 14]), using: lead).0 == .noChange)
        #expect(InvestigationReasoning.compare(baseline, sample(first, [18, 21, 25]), using: lead).0 == .improved)
        #expect(InvestigationReasoning.compare(baseline, sample(first, [1, 2, 3]), using: lead).0 == .worsened)
        let newRoute = InvestigationRoute(generation: .now, interface: "WiFi", wifi: "Other", vpn: .off, exit: nil)
        #expect(InvestigationReasoning.compare(baseline, sample(newRoute, [18, 21, 25]), using: lead).0 == .couldNotCompare)
    }

    @Test func twoSlowSiteResponsesTriggerAnAccessComparison() {
        let sample = InvestigationSample(route: first, at: .now, readings: [
            .site: .init(label: "Affected site", detail: "HTTP 200", samples: [1_600, 2_200], outcome: true),
            .reference: .init(label: "Reference", detail: "HTTP 200", samples: [1_500, 1_750], outcome: true)
        ])
        #expect(InvestigationReasoning.lead(for: .connection, sample: sample).change == .otherAccess)
    }

    @Test func localDelayAndCertificateRejectionLeadToDifferentControls() {
        let sample = InvestigationSample(route: first, at: .now, readings: [
            .router: .init(label: "Gateway", detail: "85 ms", samples: [85]),
            .certificate: .init(label: "Affected site", detail: "Trust failed", outcome: false),
            .referenceCertificate: .init(label: "Reference", detail: "Trust passed", outcome: true)
        ])
        let wifi = InvestigationReasoning.lead(for: .wifi, sample: sample)
        #expect(wifi.change == .nearRouter && wifi.metric == .router)
        #expect(wifi.acrossAccess.metric == .site)
        let security = InvestigationReasoning.lead(for: .security, sample: sample)
        #expect(security.change == .otherAccess && security.metric == .certificate)
    }

    @Test func slowSingleRequestsWithFastParallelRequestsLeadToAnAccessComparison() {
        let sample = InvestigationSample(route: first, at: .now, readings: [
            .single: .init(label: "Single", detail: "3 of 3", samples: [0.6, 0.7, 1.1], outcome: true),
            .parallel: .init(label: "Parallel", detail: "3 of 3", samples: [17, 18, 21], outcome: true)
        ])
        let lead = InvestigationReasoning.lead(for: .speed, sample: sample)
        #expect(lead.change == .otherAccess)
        #expect(lead.headline.contains("Parallel"))
    }

    @Test func encryptedTransportDoesNotEstablishBrowserResolver() {
        let sample = InvestigationSample(route: first, at: .now, readings: [
            .doh: .init(label: "DoH", detail: "Valid reply", outcome: true),
            .dot: .init(label: "DoT", detail: "Valid reply", outcome: true)
        ])
        let lead = InvestigationReasoning.lead(for: .privacy, sample: sample)
        #expect(lead.metric == .resolver)
        #expect(InvestigationReasoning.compare(sample, sample, using: lead).0 == .couldNotCompare)
        var before = sample
        var after = sample
        before.readings[.resolver] = .init(label: "Reported resolver", detail: "Different", outcome: false)
        after.readings[.resolver] = .init(label: "Reported resolver", detail: "Expected", outcome: true)
        #expect(InvestigationReasoning.compare(before, after, using: lead).0 == .improved)
    }

    @Test func eachVPNComparisonRequiresItsDeclaredChange() {
        let route = InvestigationRoute(generation: .distantPast, interface: "WiFi", wifi: "Test",
            vpn: .probablyOn, exit: "198.51.100.1")
        let otherVPN = InvestigationRoute(generation: .now, interface: "WiFi", wifi: "Test",
            vpn: .probablyOn, exit: "198.51.100.2")
        let otherWiFi = InvestigationRoute(generation: .now, interface: "WiFi", wifi: "Other",
            vpn: .probablyOn, exit: "198.51.100.1")
        #expect(route.comparisonIssue(after: otherVPN, change: .vpnServer) == nil)
        #expect(route.comparisonIssue(after: otherWiFi, change: .vpnServer) != nil)
        #expect(route.comparisonIssue(after: otherWiFi, change: .otherAccess) == nil)
        #expect(route.comparisonIssue(after: route, change: .vpnServer) != nil)
        #expect(first.comparisonIssue(after: route, change: .connectVPN) == nil)
        #expect(route.comparisonIssue(after: otherVPN, change: .connectVPN) != nil)
    }
}
