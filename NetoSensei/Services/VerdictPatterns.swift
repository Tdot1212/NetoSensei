//
//  VerdictPatterns.swift
//  NetoSensei
//
//  Diagnosis v2 — named diagnostic patterns (design §E).
//
//  Each matcher is a pure function of coverage + context → Finding?. It uses
//  ONLY signals the app actually measures (design §1.7). Where a textbook
//  signature needs something iOS does not expose (cellular signal strength),
//  the pattern says so in its confidence instead of assuming it.
//
//  Every finding carries the §C contract: plain headline, measured evidence
//  with units and bands, a cause, and EXACTLY ONE action category — including
//  the NOT-FIXABLE category for things nothing on the phone can change.
//
//  Order = priority (most specific first). Two patterns never claim the same
//  check twice: the composer passes the checks already explained to the
//  generic findings, and E1/E2 are mutually exclusive by signature (E2 needs
//  steady delay, E1 needs unsteady delay).
//

import Foundation

enum VerdictPatterns {

    static var matchers: [(Coverage, VerdictContext) -> Finding?] {
        [
            proxyInterception,        // E3  — explains why numbers are missing before anything judges them
            captivePortal,            // E9  — a login page blocks everything else
            crossBorderRestriction,   // E10 — China, VPN off: overseas blocked by policy, not by the network
            roamingSIMBackhaul,       // E2  — cellular, steady but far
            towerCongestion,          // E1  — cellular, unsteady and slow
            vpnOverhead,              // E4  — VPN on, router fine, tunnel slow
            vpnOrNetworkUndetermined, // E6  — VPN on, router hidden: can't attribute
            ispSlow,                  // E5  — VPN off, router fine, internet slow
            hotspotShared             // E14 — informational
        ]
    }

    static func match(coverage: Coverage, context: VerdictContext) -> [Finding] {
        matchers.compactMap { $0(coverage, context) }
    }

    // MARK: - Shared helpers

    private static func evidenceInternet(_ ms: Double, viaVPN: Bool) -> Evidence {
        Evidence(label: "Internet delay", value: ms, unit: "ms",
                 band: MetricBands.internetDelay(ms: ms, viaVPN: viaVPN),
                 comparedTo: viaVPN ? "via VPN; under 250 ms is normal for a tunnel" : "under 60 ms is normal")
    }
    private static func evidenceGateway(_ ms: Double) -> Evidence {
        Evidence(label: "Router delay", value: ms, unit: "ms", band: MetricBands.gatewayDelay(ms: ms), comparedTo: "under 10 ms is normal at home")
    }
    private static func evidenceJitter(_ ms: Double) -> Evidence {
        Evidence(label: "Delay variation", value: ms, unit: "ms", band: MetricBands.jitter(ms: ms), comparedTo: "under 15 ms is steady")
    }
    private static func evidenceSpeed(_ mbps: Double) -> Evidence {
        Evidence(label: "Download speed", value: mbps, unit: "Mbps", band: MetricBands.downloadSpeed(mbps: mbps), comparedTo: nil)
    }

    private static let regionGroups: [Set<String>] = [["CN", "HK", "MO", "TW"], ["US", "PR", "VI", "GU"]]
    static func sameRegion(_ a: String, _ b: String) -> Bool {
        let ua = a.uppercased(), ub = b.uppercased()
        if ua == ub { return true }
        return regionGroups.contains { $0.contains(ua) && $0.contains(ub) }
    }

    private static func hasRepeatedFailure(_ coverage: Coverage) -> Bool {
        coverage.failed.contains { $0.consecutiveFailures >= VerdictComposer.failureStreakForFinding }
    }

    // MARK: - E3 Local proxy / VPN answering probes (Phase 2.1 flag)

    static func proxyInterception(_ coverage: Coverage, _ ctx: VerdictContext) -> Finding? {
        guard ctx.latencyIntercepted else { return nil }
        return Finding(
            kind: .proxyInterception, severity: .fair,
            confidence: Confidence(level: .high, reason: "The delay probe was answered faster than the router can be reached — only an on-device proxy can do that"),
            headline: "A VPN or proxy on this phone is answering the delay test",
            evidence: [],
            cause: "A VPN or proxy app running on this phone replies to the delay probe itself, so the number would describe the app, not the network. Speed tests still measure real throughput through the tunnel.",
            action: .notFixable(
                why: "This is how on-device tunnels work; nothing is broken.",
                expect: "No delay number while the proxy is on. Speed, dropped-data and steadiness readings are still real.",
                workarounds: ["Turn the proxy off for a moment to measure the raw network, then turn it back on"]),
            basedOn: [.externalLatency], wouldSharpen: [], byDesign: true
        )
    }

    // MARK: - E9 Captive portal

    static func captivePortal(_ coverage: Coverage, _ ctx: VerdictContext) -> Finding? {
        guard let v = coverage.value(.captivePortal), v == 1 else { return nil }
        return Finding(
            kind: .captivePortal, severity: .critical,
            confidence: Confidence(level: .high, reason: "The connectivity probe was redirected to a login page"),
            headline: "This network wants you to log in first",
            evidence: [],
            cause: "Hotels, venues and airports hold all traffic until you accept their terms on a web page. Until then nothing else works, including VPNs.",
            action: .userFixable(steps: ["Open Safari and load any http:// page — the login page should appear", "Accept the terms or enter the code from the venue", "Then re-run this check"]),
            basedOn: [.captivePortal]
        )
    }

    // MARK: - E10 Cross-border restriction (China, VPN off)

    static func crossBorderRestriction(_ coverage: Coverage, _ ctx: VerdictContext) -> Finding? {
        guard ctx.likelyInChina, !ctx.vpn.isOn else { return nil }
        guard let domestic = coverage.value(.domesticReach), domestic == 1 else { return nil }
        guard let overseas = coverage.record(.httpReach) else { return nil }
        let overseasBlocked: Bool = {
            switch overseas.status {
            case .ran(let m): return m.value == 0
            case .failed: return true
            default: return false
            }
        }()
        guard overseasBlocked else { return nil }
        return Finding(
            kind: .crossBorderRestriction, severity: .poor,
            confidence: Confidence(level: .high, reason: "Domestic sites answer; overseas sites do not; no VPN is active"),
            headline: "Overseas sites are blocked here, your network is fine",
            evidence: [],
            cause: "In mainland China, traffic to many overseas services is blocked at the border. Your Wi-Fi and provider are working — domestic sites load normally.",
            action: .notFixable(
                why: "This is network policy, not a fault on your phone or router.",
                expect: "Chinese apps and sites work normally; overseas apps stay blocked until a VPN is on.",
                workarounds: ["Turn on your VPN, then re-run this check"]),
            basedOn: [.domesticReach, .httpReach], byDesign: true
        )
    }

    // MARK: - E2 Roaming SIM home-routed backhaul

    static func roamingSIMBackhaul(_ coverage: Coverage, _ ctx: VerdictContext) -> Finding? {
        guard ctx.isCellular, !ctx.vpn.isOn else { return nil }
        guard let ipCountry = ctx.publicCountry, let expected = ctx.expectedCountry, !sameRegion(ipCountry, expected) else { return nil }
        guard let ext = coverage.value(.externalLatency), ext >= 150 else { return nil }
        // Steady delay: if jitter was measured it must not be poor (that is E1).
        if let j = coverage.value(.jitter), MetricBands.jitter(ms: j) <= .poor { return nil }
        guard !hasRepeatedFailure(coverage) else { return nil }

        var evidence = [evidenceInternet(ext, viaVPN: false)]
        if let j = coverage.value(.jitter) { evidence.append(evidenceJitter(j)) }
        let sources = ctx.publicIPVerified ? "two IP lookups agree" : "one IP lookup"
        return Finding(
            kind: .roamingSIMBackhaul, severity: MetricBands.internetDelay(ms: ext, viaVPN: false),
            confidence: Confidence(level: ctx.publicIPVerified ? .high : .medium,
                                   reason: "Cellular, no VPN; traffic exits in \(ipCountry.uppercased()) (\(sources)) while the phone's clock says \(expected.uppercased()); delay steady and inflated"),
            headline: "Your SIM is routing traffic through its home country",
            evidence: evidence,
            cause: "Your traffic exits in \(ipCountry.uppercased()) although you are in \(expected.uppercased()). Roaming SIMs send all data back to their home country before it reaches the internet, by design. That round trip adds roughly 150–300 ms to everything.",
            action: .notFixable(
                why: "Nothing on your phone is wrong; the route is decided by the SIM's carrier.",
                expect: "Web pages a beat slower, streaming fine, video calls and games laggy.",
                workarounds: ["A local eSIM gives you a direct route if low delay matters", "Use venue or hotel Wi-Fi for calls"]),
            basedOn: [.externalLatency] + (coverage.value(.jitter) != nil ? [.jitter] : []),
            wouldSharpen: coverage.value(.jitter) == nil ? [.jitter] : [],
            byDesign: true
        )
    }

    // MARK: - E1 Crowded cell tower / venue

    static func towerCongestion(_ coverage: Coverage, _ ctx: VerdictContext) -> Finding? {
        guard ctx.isCellular else { return nil }
        guard let ext = coverage.value(.externalLatency) else { return nil }
        let viaVPN = ctx.vpn.isOn
        guard MetricBands.internetDelay(ms: ext, viaVPN: viaVPN) <= .poor else { return nil }
        // The distinguishing signal is UNSTEADY delay; without a jitter reading
        // this pattern cannot be told from a merely distant route.
        guard let j = coverage.value(.jitter), MetricBands.jitter(ms: j) <= .poor else { return nil }
        guard !hasRepeatedFailure(coverage) else { return nil }

        var evidence = [evidenceInternet(ext, viaVPN: viaVPN), evidenceJitter(j)]
        var basedOn: [CheckID] = [.externalLatency, .jitter]
        if let mbps = coverage.value(.throughput) { evidence.append(evidenceSpeed(mbps)); basedOn.append(.throughput) }
        if let loss = coverage.value(.packetLoss) {
            evidence.append(Evidence(label: "Dropped data", value: loss, unit: "%", band: MetricBands.packetLoss(percent: loss), comparedTo: nil))
            basedOn.append(.packetLoss)
        }
        let radio = ctx.radioTechnology.map { " on \($0)" } ?? ""
        return Finding(
            kind: .towerCongestion, severity: MetricBands.internetDelay(ms: ext, viaVPN: viaVPN),
            confidence: Confidence(level: .medium, reason: "Inferred from slow AND unsteady delay\(radio); iOS does not let apps read cellular signal strength, so a weak signal cannot be ruled out"),
            headline: "The cell tower here is crowded",
            evidence: evidence,
            cause: "Nothing on your phone is broken. Many people are sharing this tower, so every packet waits in line — delay jumps around and speed drops.",
            action: .notFixable(
                why: "The tower's capacity is the carrier's; your phone can't change how many people are on it.",
                expect: "Messages fine, pages slow, calls and video choppy, uploads slow. It eases when the crowd thins.",
                workarounds: ["Use the venue's Wi-Fi if there is one", "Step outside the crowd or near a window", "Switch between LTE and 5G in Settings — you may land on a less loaded cell", "Queue big uploads for later"]),
            basedOn: basedOn,
            wouldSharpen: coverage.value(.throughput) == nil ? [.throughput] : [],
            byDesign: true
        )
    }

    // MARK: - E4 VPN tunnel overhead (router fine, tunnel slow)

    static func vpnOverhead(_ coverage: Coverage, _ ctx: VerdictContext) -> Finding? {
        guard ctx.vpn.isOn, !ctx.isCellular else { return nil }
        guard let gw = coverage.value(.gatewayLatency), MetricBands.gatewayDelay(ms: gw) >= .good else { return nil }
        guard let ext = coverage.value(.externalLatency) else { return nil }
        let overhead = ext - gw   // measured, never `ext − 30`
        guard overhead >= 150 else { return nil }
        let band = MetricBands.vpnOverhead(ms: overhead)
        return Finding(
            kind: .vpnOverhead, severity: max(band, .fair),   // never worse than fair: the tunnel works, it is just far
            confidence: Confidence(level: .high, reason: "Router delay and internet delay both measured; the difference is the tunnel"),
            headline: "Your VPN is adding most of the delay",
            evidence: [evidenceGateway(gw), evidenceInternet(ext, viaVPN: true),
                       Evidence(label: "Added by the VPN", value: overhead, unit: "ms", band: band, comparedTo: "under 150 ms is normal for an international tunnel")],
            cause: "Your home network answers in \(Int(gw)) ms. The extra \(Int(overhead)) ms is the round trip to your VPN's server\(ctx.vpn.exitCountryText) and back.",
            action: .userFixable(steps: ["Pick a nearer server in your VPN app", "Try the WireGuard protocol if the app offers it", "Reconnect the VPN once — routes sometimes get stuck on a bad path"]),
            basedOn: [.gatewayLatency, .externalLatency]
        )
    }

    // MARK: - E6 VPN on, router hidden: cannot attribute

    static func vpnOrNetworkUndetermined(_ coverage: Coverage, _ ctx: VerdictContext) -> Finding? {
        guard ctx.vpn.isOn, !ctx.isCellular else { return nil }
        // Only when the tunnel is actually slow (poor or worse on the via-VPN
        // scale). A fair 300–400 ms tunnel is a working tunnel, not a finding.
        guard let ext = coverage.value(.externalLatency), MetricBands.internetDelay(ms: ext, viaVPN: true) <= .poor else { return nil }
        guard let gwStatus = coverage.record(.gatewayLatency)?.status else { return nil }
        switch gwStatus {
        case .ran: return nil
        case .notApplicable, .failed, .notRun: break
        }
        return Finding(
            kind: .vpnOrNetworkUndetermined, severity: .fair,
            confidence: Confidence(level: .low, reason: "The VPN hides the router, so the delay cannot be split between tunnel and network"),
            headline: "Slow, but can't tell whether it's the VPN or the network",
            evidence: [evidenceInternet(ext, viaVPN: true)],
            cause: "With the VPN on, the router can't be measured, so the delay can't be attributed to the tunnel or to the network behind it.",
            action: .none,
            basedOn: [.externalLatency], wouldSharpen: [.gatewayLatency]
        )
    }

    // MARK: - E5 Internet provider slow (router fine, VPN off)

    static func ispSlow(_ coverage: Coverage, _ ctx: VerdictContext) -> Finding? {
        guard !ctx.vpn.isOn, !ctx.isCellular else { return nil }
        guard let gw = coverage.value(.gatewayLatency), MetricBands.gatewayDelay(ms: gw) >= .good else { return nil }
        guard let ext = coverage.value(.externalLatency) else { return nil }
        let band = MetricBands.internetDelay(ms: ext, viaVPN: false)
        guard band <= .poor else { return nil }
        var evidence = [evidenceGateway(gw), evidenceInternet(ext, viaVPN: false)]
        var basedOn: [CheckID] = [.gatewayLatency, .externalLatency]
        if let mbps = coverage.value(.throughput) { evidence.append(evidenceSpeed(mbps)); basedOn.append(.throughput) }
        return Finding(
            kind: .ispSlow, severity: band,
            confidence: Confidence(level: .high, reason: "Router answers quickly; the delay starts beyond it"),
            headline: "Your internet provider is slow right now",
            evidence: evidence,
            cause: "Your router is fine (\(Int(gw)) ms). The slowdown starts after traffic leaves your home, on the provider's network.",
            action: .fixableElsewhere(
                who: "Your internet provider",
                what: "Congestion or a fault on their side of the connection",
                meanwhile: ["Retry in a few minutes — provider congestion often clears", "Use cellular for an urgent call", "If it lasts hours, report it to the provider with these numbers"]),
            basedOn: basedOn
        )
    }

    // MARK: - E14 Sharing another phone's hotspot (informational)

    static func hotspotShared(_ coverage: Coverage, _ ctx: VerdictContext) -> Finding? {
        guard ctx.isHotspot else { return nil }
        return Finding(
            kind: .hotspotShared, severity: .fair,
            confidence: Confidence(level: .medium, reason: "Network name matches a phone hotspot"),
            headline: "You're on another phone's hotspot",
            evidence: [],
            cause: "This Wi-Fi is another phone's cellular connection, so it behaves like cellular: delay and speed follow that phone's signal and its carrier.",
            action: .none,
            basedOn: [], byDesign: true
        )
    }
}

private extension VPNContext {
    var exitCountryText: String {
        if case .on(_, let country?) = self { return " in \(country)" }
        return ""
    }
}
