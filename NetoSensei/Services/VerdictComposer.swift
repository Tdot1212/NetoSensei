//
//  VerdictComposer.swift
//  NetoSensei
//
//  Diagnosis v2 — the ONE composer (design §A3, §B, §C).
//
//  Pure static functions over `[CheckRecord]` + `VerdictContext`. No I/O, no
//  singletons, no clocks except the timestamp on the result — unit-tested like
//  Phases 2.1–4. Engines are check PRODUCERS; this is the only place a score,
//  a state word, a root cause or an explanation is decided.
//
//  RULES ENFORCED HERE (each pinned by a test):
//   B1  A failed check is never a pass. It contributes nothing to the score or
//       the state; two+ consecutive failures become a finding of their own.
//   B2  Coverage floor: a score exists only if the internet delay (or a speed
//       test) ran AND the router delay ran or was not applicable.
//   B3  State derives from findings, never from arithmetic on the score, so
//       the number and the word cannot disagree.
//   B4  Not-applicable is neither pass nor fail and is excluded from counts.
//   B5  Nothing is estimated or defaulted: a missing input skips its term.
//

import Foundation

enum VerdictComposer {

    /// Consecutive failures at or above this promote a check to a finding.
    static let failureStreakForFinding = 2

    // MARK: - Entry point

    static func compose(records: [CheckRecord], context: VerdictContext, now: Date = Date()) -> NetworkVerdict {
        let coverage = Coverage(records: records)
        let score = computeScore(coverage: coverage, context: context)

        // Named patterns first (most specific), then generic component findings
        // for anything a pattern did not already explain.
        var findings = VerdictPatterns.match(coverage: coverage, context: context)
        let explainedChecks = Set(findings.flatMap { $0.basedOn })
        findings += genericFindings(coverage: coverage, context: context, alreadyExplained: explainedChecks)
        if findings.isEmpty, let s = score, s.band <= .poor,
           let worst = worstEvidence(coverage: coverage, context: context) {
            // The number says poor but no single component crossed a finding
            // threshold: say so from the worst measured component, never silence.
            findings.append(Finding(
                kind: .internetSlow, severity: worst.band ?? .poor,
                confidence: Confidence(level: .medium, reason: "Several components are below par; none alone is the cause"),
                headline: "Your connection is slower than it should be",
                evidence: [worst],
                cause: "No single part of the path is broken, but several are slower than normal at the same time.",
                action: .userFixable(steps: ["Run a speed test to see whether throughput is affected", "Re-check in a few minutes — this pattern is often temporary"]),
                basedOn: coverage.ran.map { $0.id }
            ))
        }
        findings.sort(by: rank)

        let state = deriveState(findings: findings, score: score, coverage: coverage)
        let primary = findings.first { $0.action != .none } ?? findings.first
        let headline = headlineText(state: state, primary: primary, score: score, coverage: coverage)

        return NetworkVerdict(
            generatedAt: now,
            context: context,
            coverage: coverage,
            state: state,
            score: score,
            primary: primary,
            findings: findings,
            headline: headline
        )
    }

    // MARK: - Score (one rubric, ran checks only)

    /// The RootCauseAnalyzer-calibrated penalties, applied ONLY to checks that
    /// ran. VPN overhead is charged once and only when both delays ran.
    static func computeScore(coverage: Coverage, context: VerdictContext) -> Score? {
        guard meetsFloor(coverage) else { return nil }

        var score = 100
        var basedOn: [CheckID] = []
        let viaVPN = context.vpn.isOn

        if let gw = coverage.value(.gatewayLatency) {
            basedOn.append(.gatewayLatency)
            if gw > 100 { score -= 15 } else if gw > 60 { score -= 10 } else if gw > 30 { score -= 5 } else if gw > 10 { score -= 2 }
        }

        if let ext = coverage.value(.externalLatency) {
            basedOn.append(.externalLatency)
            if viaVPN {
                if ext > 800 { score -= 45 } else if ext > 600 { score -= 35 } else if ext > 400 { score -= 28 } else if ext > 250 { score -= 18 } else if ext > 100 { score -= 10 }
            } else {
                if ext > 400 { score -= 50 } else if ext > 300 { score -= 45 } else if ext > 200 { score -= 40 } else if ext > 150 { score -= 30 } else if ext > 100 { score -= 20 } else if ext > 80 { score -= 12 } else if ext > 50 { score -= 5 }
            }
        }

        if viaVPN, let ext = coverage.value(.externalLatency), let gw = coverage.value(.gatewayLatency) {
            let overhead = ext - gw   // measured, never estimated (no `ext − 30`)
            if overhead > 450 { score -= 20 } else if overhead > 300 { score -= 10 } else if overhead > 150 { score -= 5 }
        }

        if let dns = coverage.value(.dnsLatency) {
            basedOn.append(.dnsLatency)
            if dns > 300 { score -= 10 } else if dns > 200 { score -= 7 } else if dns > 100 { score -= 5 } else if dns > 50 { score -= 3 } else if dns > 20 { score -= 1 }
        }

        if let loss = coverage.value(.packetLoss), loss > 0 {
            basedOn.append(.packetLoss)
            score -= Int(loss * 5)
        }

        // Hard failures count only when repeated (B1). A single timeout is coverage.
        if let r = coverage.record(.gatewayReach), r.status.didFail, r.consecutiveFailures >= failureStreakForFinding { score -= 40 }
        if let r = coverage.record(.externalLatency), r.status.didFail, r.consecutiveFailures >= failureStreakForFinding { score -= 40 }
        if let r = coverage.record(.dnsResolve), r.status.didFail, r.consecutiveFailures >= failureStreakForFinding { score -= 20 }

        let value = max(0, min(100, score))
        return Score(value: value, band: MetricBands.score(value), basedOn: basedOn)
    }

    /// B2: internet delay ran (or a speed test ran) AND the router delay ran or
    /// did not apply (cellular / hidden by VPN). Anything less → no number.
    static func meetsFloor(_ coverage: Coverage) -> Bool {
        let internetKnown = coverage.value(.externalLatency) != nil || coverage.value(.throughput) != nil
        let gatewayStatus = coverage.record(.gatewayLatency)?.status
        let gatewaySettled: Bool = {
            switch gatewayStatus {
            case .ran: return true
            case .notApplicable: return true
            default: return false
            }
        }()
        return internetKnown && gatewaySettled
    }

    // MARK: - State (B3)

    static func deriveState(findings: [Finding], score: Score?, coverage: Coverage) -> OverallState {
        let real = findings.filter { !$0.byDesign }
        if real.contains(where: { $0.severity == .critical }) { return .broken }
        if score == nil && real.isEmpty && findings.isEmpty { return .unknown }
        // Any real finding (fair or worse) means something is not right — a
        // "fair" VPN-overhead finding with steps to take is still degradation,
        // even when the number lands in the "good" band.
        if real.contains(where: { $0.severity <= .fair }) { return .degraded }
        if let s = score, s.band <= .fair { return .degraded }
        if !findings.isEmpty && findings.allSatisfy({ $0.byDesign }) { return .degraded }
        return score == nil ? .unknown : .working
    }

    // MARK: - Generic findings

    static func genericFindings(coverage: Coverage, context: VerdictContext, alreadyExplained: Set<CheckID>) -> [Finding] {
        var out: [Finding] = []
        let viaVPN = context.vpn.isOn
        func explained(_ id: CheckID) -> Bool { alreadyExplained.contains(id) }

        // No internet: the internet delay failed repeatedly (or the web check did).
        let extFailed = coverage.record(.externalLatency).map { $0.status.didFail && $0.consecutiveFailures >= failureStreakForFinding } ?? false
        let httpFailed = coverage.record(.httpReach).map { $0.status.didFail && $0.consecutiveFailures >= failureStreakForFinding } ?? false
        if (extFailed || httpFailed) && !explained(.externalLatency) && !explained(.httpReach) {
            out.append(Finding(
                kind: .noInternet, severity: .critical,
                confidence: Confidence(level: .high, reason: "Repeated probes to the internet got no answer"),
                headline: "No internet connection",
                evidence: [],
                cause: "Your device is on a network, but nothing beyond it is answering.",
                action: .userFixable(steps: [
                    "Toggle Wi-Fi off and on, or switch to cellular",
                    "If you just joined this network, look for a login page (hotels and venues use them)",
                    "Restart the router if it is yours"
                ]),
                basedOn: [.externalLatency, .httpReach].filter { coverage.record($0) != nil }
            ))
        }

        // Router unreachable: the router check failed repeatedly on a real address.
        if let r = coverage.record(.gatewayReach), r.status.didFail, r.consecutiveFailures >= failureStreakForFinding, !explained(.gatewayReach) {
            out.append(Finding(
                kind: .routerUnreachable, severity: viaVPN ? .poor : .critical,
                confidence: Confidence(level: viaVPN ? .medium : .high, reason: viaVPN ? "A VPN can block local network access; the router may be fine" : "The router did not answer repeated probes"),
                headline: viaVPN ? "Can't reach your router through the VPN" : "Your router isn't answering",
                evidence: [],
                cause: viaVPN ? "Some VPNs block traffic to the local network while connected." : "Your phone is on the network but the router does not respond to it.",
                action: viaVPN
                    ? .notFixable(why: "The VPN is doing this on purpose to keep all traffic inside the tunnel.", expect: "Internet works normally; local devices (printers, NAS) may be unreachable.", workarounds: ["Turn on 'allow local network' in the VPN app if it has that setting"])
                    : .userFixable(steps: ["Toggle Wi-Fi off and on", "Forget and rejoin the network", "Restart the router (unplug for 30 seconds)"]),
                basedOn: [.gatewayReach]
            ))
        }

        // Router slow.
        if let gw = coverage.value(.gatewayLatency), !explained(.gatewayLatency) {
            let band = MetricBands.gatewayDelay(ms: gw)
            if band <= .poor && !context.isCellular {
                out.append(Finding(
                    kind: .routerSlow, severity: band,
                    confidence: Confidence(level: .high, reason: "Measured directly to the router, before any internet hop"),
                    headline: "Your router is slow to respond",
                    evidence: [Evidence(label: "Router delay", value: gw, unit: "ms", band: band, comparedTo: "under 10 ms is normal at home")],
                    cause: "Traffic is already slow before it leaves your home network — a weak Wi-Fi link, a busy router, or too many devices.",
                    action: .userFixable(steps: ["Move closer to the router", "Restart the router", "Disconnect devices you are not using", "Use the 5 GHz network if the router offers one"]),
                    basedOn: [.gatewayLatency]
                ))
            }
        }

        // Internet slow (generic — patterns E4/E5 usually claim this first).
        if let ext = coverage.value(.externalLatency), !explained(.externalLatency) {
            let band = MetricBands.internetDelay(ms: ext, viaVPN: viaVPN)
            if band <= .poor {
                out.append(Finding(
                    kind: .internetSlow, severity: band,
                    confidence: Confidence(level: .medium, reason: "Delay measured; the cause could not be pinned to one hop"),
                    headline: "Internet responses are slow",
                    evidence: [Evidence(label: "Internet delay", value: ext, unit: "ms", band: band, comparedTo: viaVPN ? "via VPN; under 250 ms is normal for a tunnel" : "under 60 ms is normal")],
                    cause: viaVPN ? "Every request goes through the VPN and back; the tunnel or the network behind it is slow." : "Requests take a long time to get an answer from the internet.",
                    action: .userFixable(steps: viaVPN ? ["Pick a nearer server in your VPN app", "Reconnect the VPN once"] : ["Retry in a few minutes", "Switch between Wi-Fi and cellular to see which is slow"]),
                    basedOn: [.externalLatency]
                ))
            }
        }

        // DNS failing repeatedly / slow.
        if let r = coverage.record(.dnsResolve), r.status.didFail, r.consecutiveFailures >= failureStreakForFinding, !explained(.dnsResolve) {
            out.append(Finding(
                kind: .dnsFailing, severity: .critical,
                confidence: Confidence(level: .high, reason: "Address lookups failed repeatedly"),
                headline: "Website addresses can't be looked up",
                evidence: [],
                cause: "Your phone can't turn names like apple.com into addresses, so nothing loads by name.",
                action: .userFixable(steps: ["Settings → Wi-Fi → your network → Configure DNS → Manual → add 1.1.1.1", "If a VPN is on, reconnect it", "Restart the router if it is yours"]),
                basedOn: [.dnsResolve]
            ))
        } else if let dns = coverage.value(.dnsLatency), !explained(.dnsLatency) {
            let band = MetricBands.dnsDelay(ms: dns)
            if band == .critical {
                out.append(Finding(
                    kind: .dnsSlow, severity: .poor,
                    confidence: Confidence(level: .high, reason: "Lookup time measured directly"),
                    headline: "Website address lookups are slow",
                    evidence: [Evidence(label: "Address lookup", value: dns, unit: "ms", band: band, comparedTo: "under 75 ms is normal")],
                    cause: "Every new site waits for a slow address lookup before it starts loading.",
                    action: .userFixable(steps: ["Settings → Wi-Fi → your network → Configure DNS → Manual → add 1.1.1.1 or 8.8.8.8"]),
                    basedOn: [.dnsLatency]
                ))
            }
        }

        // Dropped data / unsteady delay (from a speed test when present).
        if let loss = coverage.value(.packetLoss), !explained(.packetLoss) {
            let band = MetricBands.packetLoss(percent: loss)
            if band <= .poor {
                out.append(Finding(
                    kind: .packetLossHigh, severity: band,
                    confidence: Confidence(level: .high, reason: "Measured over repeated probes"),
                    headline: "Some of your data is getting lost",
                    evidence: [Evidence(label: "Dropped data", value: loss, unit: "%", band: band, comparedTo: "under 1% is normal")],
                    cause: "Packets are being dropped somewhere on the path — usually a weak wireless link or a congested hop.",
                    action: .userFixable(steps: ["Move closer to the router or away from the crowd", "Retry on the other connection type (Wi-Fi ↔ cellular)"]),
                    basedOn: [.packetLoss]
                ))
            }
        }
        if let j = coverage.value(.jitter), !explained(.jitter) {
            let band = MetricBands.jitter(ms: j)
            if band <= .poor {
                out.append(Finding(
                    kind: .jitterHigh, severity: band,
                    confidence: Confidence(level: .high, reason: "Measured over repeated probes"),
                    headline: "Your delay is unsteady",
                    evidence: [Evidence(label: "Delay variation", value: j, unit: "ms", band: band, comparedTo: "under 15 ms is normal")],
                    cause: "Delay is jumping around from one moment to the next, which makes calls and games stutter even when speed is fine.",
                    action: .userFixable(steps: ["Move closer to the router or away from the crowd", "Pause large downloads on this network"]),
                    basedOn: [.jitter]
                ))
            }
        }

        // Repeated failures of any other check (never a silent pass).
        for r in coverage.failed where r.consecutiveFailures >= failureStreakForFinding && !explained(r.id)
            && ![.externalLatency, .httpReach, .gatewayReach, .dnsResolve].contains(r.id) {
            if case .failed(let reason) = r.status {
                out.append(Finding(
                    kind: .checkFailingRepeatedly, severity: .fair,
                    confidence: Confidence(level: .medium, reason: "The check itself keeps failing; the cause is not measured"),
                    headline: "The \(r.id.plainName) keeps failing",
                    evidence: [],
                    cause: "This check \(reason.plain) \(r.consecutiveFailures) times in a row, so nothing can be claimed about what it measures.",
                    action: .none,
                    basedOn: [r.id]
                ))
            }
        }

        return out
    }

    // MARK: - Helpers

    static func worstEvidence(coverage: Coverage, context: VerdictContext) -> Evidence? {
        var candidates: [Evidence] = []
        if let v = coverage.value(.gatewayLatency) { candidates.append(Evidence(label: "Router delay", value: v, unit: "ms", band: MetricBands.gatewayDelay(ms: v), comparedTo: nil)) }
        if let v = coverage.value(.externalLatency) { candidates.append(Evidence(label: "Internet delay", value: v, unit: "ms", band: MetricBands.internetDelay(ms: v, viaVPN: context.vpn.isOn), comparedTo: nil)) }
        if let v = coverage.value(.dnsLatency) { candidates.append(Evidence(label: "Address lookup", value: v, unit: "ms", band: MetricBands.dnsDelay(ms: v), comparedTo: nil)) }
        if let v = coverage.value(.packetLoss) { candidates.append(Evidence(label: "Dropped data", value: v, unit: "%", band: MetricBands.packetLoss(percent: v), comparedTo: nil)) }
        return candidates.min { ($0.band ?? .excellent) < ($1.band ?? .excellent) }
    }

    /// Ordering: real (not by-design) critical first, then by severity, then
    /// findings with an action before informational ones.
    static func rank(_ a: Finding, _ b: Finding) -> Bool {
        if a.byDesign != b.byDesign { return !a.byDesign }
        if a.severity != b.severity { return a.severity < b.severity }
        let aHasAction = a.action != .none, bHasAction = b.action != .none
        if aHasAction != bHasAction { return aHasAction }
        return a.kind.rawValue < b.kind.rawValue
    }

    static func headlineText(state: OverallState, primary: Finding?, score: Score?, coverage: Coverage) -> String {
        switch state {
        case .broken:
            return primary?.headline ?? "Your connection is not working"
        case .degraded:
            return primary?.headline ?? "Your connection is slower than it should be"
        case .working:
            return coverage.failed.isEmpty
                ? "Your connection is working normally"
                : "Working normally in the checks that completed"
        case .unknown:
            return coverage.attempted.isEmpty
                ? "Nothing could be checked yet"
                : "Not enough checks completed to judge this connection"
        }
    }
}
