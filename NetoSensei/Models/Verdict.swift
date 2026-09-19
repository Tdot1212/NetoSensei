//
//  Verdict.swift
//  NetoSensei
//
//  Diagnosis v2 — the ONE verdict model (design §A, §B, §C).
//
//  Every surface that shows a score, a health word, a root cause or an
//  explanation renders from a `NetworkVerdict`. Nothing else computes one.
//  Verdicts are composed by `VerdictComposer` from coverage-tagged
//  `CheckRecord`s, so a verdict can only ever claim what actually ran.
//

import Foundation

// MARK: - Checks and coverage (§B)

enum CheckID: String, Codable, Sendable, CaseIterable {
    // Performance domain
    case gatewayReach, gatewayLatency, externalLatency, dnsResolve, dnsLatency, httpReach,
         vpnState, throughput, packetLoss, jitter
    // Privacy domain (producers land post-trip; IDs reserved so coverage lines are stable)
    case dnsHijack, vpnLeak, ipv6Leak, captivePortal, certTrust, dnsEncryption, wifiSafety

    /// Plain name for coverage lines. No jargon.
    var plainName: String {
        switch self {
        case .gatewayReach: return "router check"
        case .gatewayLatency: return "router delay"
        case .externalLatency: return "internet delay"
        case .dnsResolve: return "address lookup"
        case .dnsLatency: return "address lookup delay"
        case .httpReach: return "web check"
        case .vpnState: return "VPN status"
        case .throughput: return "speed test"
        case .packetLoss: return "dropped-data test"
        case .jitter: return "delay steadiness"
        case .dnsHijack: return "DNS hijack test"
        case .vpnLeak: return "VPN leak test"
        case .ipv6Leak: return "IPv6 leak test"
        case .captivePortal: return "login-page check"
        case .certTrust: return "certificate check"
        case .dnsEncryption: return "encrypted-DNS check"
        case .wifiSafety: return "Wi-Fi safety check"
        }
    }
}

struct Measurement: Codable, Sendable, Equatable {
    let value: Double
    let unit: String          // "ms", "%", "Mbps", "" for booleans (1 = yes)
    let at: Date
}

enum FailureReason: Codable, Sendable, Equatable {
    case timeout
    case blocked
    case intercepted
    case error(String)

    var plain: String {
        switch self {
        case .timeout: return "timed out"
        case .blocked: return "was blocked"
        case .intercepted: return "was answered by a local VPN/proxy"
        case .error(let s): return s
        }
    }
}

enum CheckStatus: Codable, Sendable, Equatable {
    case ran(Measurement)
    case failed(FailureReason)
    case notApplicable(String)     // "No VPN in use", "no router on cellular"
    case notRun(String)            // "Deep Scan only", "skipped: superseded"

    var didRun: Bool { if case .ran = self { return true } else { return false } }
    var didFail: Bool { if case .failed = self { return true } else { return false } }
    var measurement: Measurement? { if case .ran(let m) = self { return m } else { return nil } }
}

struct CheckRecord: Codable, Sendable, Equatable {
    let id: CheckID
    let status: CheckStatus
    /// Consecutive failures of this check INCLUDING this one (0 when it ran).
    /// Supplied by the producer from MeasurementValidityTracker; the composer
    /// promotes a check to a finding only at `>= 2` (one timeout is coverage,
    /// not a diagnosis — design §B rule 1).
    let consecutiveFailures: Int

    init(id: CheckID, status: CheckStatus, consecutiveFailures: Int = 0) {
        self.id = id
        self.status = status
        self.consecutiveFailures = consecutiveFailures
    }

    static func ran(_ id: CheckID, _ value: Double, unit: String, at: Date = Date()) -> CheckRecord {
        CheckRecord(id: id, status: .ran(Measurement(value: value, unit: unit, at: at)))
    }
    static func failed(_ id: CheckID, _ reason: FailureReason, streak: Int = 1) -> CheckRecord {
        CheckRecord(id: id, status: .failed(reason), consecutiveFailures: streak)
    }
    static func notApplicable(_ id: CheckID, _ why: String) -> CheckRecord {
        CheckRecord(id: id, status: .notApplicable(why))
    }
    static func notRun(_ id: CheckID, _ why: String) -> CheckRecord {
        CheckRecord(id: id, status: .notRun(why))
    }
}

struct Coverage: Codable, Sendable, Equatable {
    let records: [CheckRecord]

    var ran: [CheckRecord] { records.filter { $0.status.didRun } }
    var failed: [CheckRecord] { records.filter { $0.status.didFail } }
    var notApplicable: [CheckRecord] { records.filter { if case .notApplicable = $0.status { return true } else { return false } } }
    var notRun: [CheckRecord] { records.filter { if case .notRun = $0.status { return true } else { return false } } }

    /// Checks that were attempted (ran or failed). Not-applicable and not-run
    /// are excluded from every count (§B rule 4).
    var attempted: [CheckRecord] { records.filter { $0.status.didRun || $0.status.didFail } }

    func record(_ id: CheckID) -> CheckRecord? { records.first { $0.id == id } }
    func value(_ id: CheckID) -> Double? { record(id)?.status.measurement?.value }

    /// "5 of 7 checks completed · 2 couldn't run — DNS hijack test timed out; router check: no router on cellular"
    var line: String {
        let attemptedCount = attempted.count
        let ranCount = ran.count
        var parts: [String] = []
        if attemptedCount == 0 {
            parts.append("No checks could run")
        } else if ranCount == attemptedCount {
            parts.append(attemptedCount == 1 ? "1 check completed" : "All \(attemptedCount) checks completed")
        } else {
            parts.append("\(ranCount) of \(attemptedCount) checks completed")
        }
        var reasons: [String] = []
        for f in failed {
            if case .failed(let r) = f.status { reasons.append("\(f.id.plainName) \(r.plain)") }
        }
        if !reasons.isEmpty {
            parts.append("\(failed.count) couldn't run — " + reasons.joined(separator: "; "))
        }
        let na = notApplicable
        if !na.isEmpty {
            let naText = na.map { rec -> String in
                if case .notApplicable(let why) = rec.status { return "\(rec.id.plainName): \(why)" }
                return rec.id.plainName
            }
            parts.append("not applicable — " + naText.joined(separator: "; "))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Findings (§C)

enum Domain: String, Codable, Sendable { case performance, privacy }

enum FindingKind: String, Codable, Sendable {
    // Generic component findings
    case noInternet, routerUnreachable, routerSlow, internetSlow, dnsFailing, dnsSlow,
         packetLossHigh, jitterHigh, speedLow, checkFailingRepeatedly, coverageLimited
    // Named patterns (§E) — matchers live in VerdictPatterns
    case towerCongestion, roamingSIMBackhaul, proxyInterception, vpnOverhead,
         ispSlow, vpnOrNetworkUndetermined, captivePortal, crossBorderRestriction, hotspotShared
}

struct Evidence: Codable, Sendable, Equatable {
    let label: String         // "Internet delay"
    let value: Double
    let unit: String          // "ms"
    let band: Band?           // nil when a value has no band (e.g. a count)
    let comparedTo: String?   // "fair for a VPN, would be poor without one"

    var text: String {
        let number: String
        if unit == "ms" || unit == "%" { number = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value) }
        else if unit == "Mbps" { number = String(format: "%.1f", value) }
        else { number = String(value) }
        var s = "\(label): \(number)\(unit.isEmpty ? "" : " \(unit)")"
        if let b = band { s += " (\(b.word.lowercased()))" }
        if let c = comparedTo { s += " — \(c)" }
        return s
    }
}

enum Action: Codable, Sendable, Equatable {
    case userFixable(steps: [String])
    case fixableElsewhere(who: String, what: String, meanwhile: [String])
    case notFixable(why: String, expect: String, workarounds: [String])
    case none

    var categoryWord: String {
        switch self {
        case .userFixable: return "You can fix this"
        case .fixableElsewhere: return "Someone else has to fix this"
        case .notFixable: return "Not fixable right now"
        case .none: return "Nothing to do"
        }
    }
}

struct Confidence: Codable, Sendable, Equatable {
    enum Level: String, Codable, Sendable { case high, medium, low }
    let level: Level
    let reason: String
}

struct Finding: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let kind: FindingKind
    let domain: Domain
    let severity: Band
    let confidence: Confidence
    let headline: String            // 1. what's wrong — ≤ 60 chars, no jargon
    let evidence: [Evidence]        // 2. measured numbers with units and bands
    let cause: String               // 3. why
    let action: Action              // 4. exactly one category
    let basedOn: [CheckID]
    let wouldSharpen: [CheckID]
    /// The network is doing what it was designed to do (roaming backhaul,
    /// proxy answering probes). Rendered yellow, never red; never "broken".
    let byDesign: Bool

    init(kind: FindingKind, domain: Domain = .performance, severity: Band, confidence: Confidence,
         headline: String, evidence: [Evidence], cause: String, action: Action,
         basedOn: [CheckID], wouldSharpen: [CheckID] = [], byDesign: Bool = false) {
        self.id = UUID()
        self.kind = kind
        self.domain = domain
        self.severity = severity
        self.confidence = confidence
        self.headline = headline
        self.evidence = evidence
        self.cause = cause
        self.action = action
        self.basedOn = basedOn
        self.wouldSharpen = wouldSharpen
        self.byDesign = byDesign
    }
}

// MARK: - The verdict (§A)

enum VPNContext: Codable, Sendable, Equatable {
    case off
    case on(authoritative: Bool, exitCountry: String?)
    case unknown

    var isOn: Bool { if case .on = self { return true } else { return false } }
}

struct VerdictContext: Codable, Sendable, Equatable {
    let segmentKey: String
    let connectionType: String          // "WiFi", "Cellular", "Wired", "Unknown"
    let vpn: VPNContext
    let latencyIntercepted: Bool
    let publicCountry: String?
    let expectedCountry: String?
    let likelyInChina: Bool
    let radioTechnology: String?        // "LTE", "5G", … cellular only; nil when unknown

    var isCellular: Bool { connectionType.lowercased().contains("cellular") }

    init(segmentKey: String = "", connectionType: String, vpn: VPNContext, latencyIntercepted: Bool = false,
         publicCountry: String? = nil, expectedCountry: String? = nil, likelyInChina: Bool = false,
         radioTechnology: String? = nil) {
        self.segmentKey = segmentKey
        self.connectionType = connectionType
        self.vpn = vpn
        self.latencyIntercepted = latencyIntercepted
        self.publicCountry = publicCountry
        self.expectedCountry = expectedCountry
        self.likelyInChina = likelyInChina
        self.radioTechnology = radioTechnology
    }
}

enum OverallState: String, Codable, Sendable {
    case working, degraded, broken, unknown

    var word: String {
        switch self {
        case .working: return "Working"
        case .degraded: return "Degraded"
        case .broken: return "Not working"
        case .unknown: return "Unknown"
        }
    }
}

struct Score: Codable, Sendable, Equatable {
    let value: Int          // 0–100
    let band: Band
    let basedOn: [CheckID]  // checks that contributed
}

struct NetworkVerdict: Codable, Sendable {
    let generatedAt: Date
    let context: VerdictContext
    let coverage: Coverage
    let state: OverallState
    let score: Score?               // nil below the coverage floor → rendered "—"
    let primary: Finding?
    let findings: [Finding]
    let headline: String            // one plain sentence

    /// The number as the ring shows it: "—" when nothing honest can be claimed.
    var scoreText: String { score.map { String($0.value) } ?? "—" }
}
