//
//  SpeedTestServerSelection.swift
//  NetoSensei
//
//  Commit 11 — speed-test server selection that is geographically honest.
//
//  THE BUG (real device, Guangzhou, CMCC Wi-Fi, no VPN):
//      [SpeedTest] In China, Cloudflare (China PoP) reachable (international, 1162ms)
//      ✅ Server selected: Cloudflare (China PoP) (overseas)
//      📥 Download result: 152.6 Mbps
//  The only candidate's own reachability probe took 1162 ms, the code noted
//  it was "international", appended "(overseas)" to the label — and used it
//  anyway. A number measured against a server 1100 ms away describes the
//  international route, not the user's connection.
//
//  RULES (pure, unit-tested):
//   1. Candidates follow the EXIT path (ExitPath.country — GeoIP / public IP),
//      not the device locale. With a VPN on, the honest server is near the
//      tunnel exit, not near the phone.
//   2. A candidate is DISQUALIFIED BY ITS OWN PROBE when the VPN is off and
//      the probe is implausible for a same-region path (threshold below).
//   3. With a VPN on, the probe measures phone→exit→server through the tunnel,
//      so "nearby to the exit" cannot be judged from the phone; the candidate
//      is accepted and the result is labelled "through your VPN" — the tunnel
//      path IS what the user experiences (Phase 2.1 "Via VPN/proxy" register).
//   4. No silent fallback: if nothing qualifies, the decision is
//      .unavailable(reason) and the test does not run. The old code fell
//      through to the same host and measured anyway.
//
//  THRESHOLD SOURCE. The probe is NetworkMonitorService.pingHost: a full HTTPS
//  HEAD (TCP handshake + TLS 1.3 handshake + one HTTP round trip = 3 network
//  RTTs, plus server time). Same-region network RTT is ≤ ~80 ms on Wi-Fi and
//  ≤ ~120 ms on a loaded cellular tower → HEAD ≈ 250–360 ms worst case.
//  The shortest intercontinental path from East Asia (to the US West Coast)
//  is ~130–160 ms network RTT → HEAD ≥ ~450 ms; Europe is ≥ ~600 ms. 400 ms
//  sits in the gap: it admits any same-region server on any access type and
//  rejects every cross-ocean path. The previous "< 80 ms" check was applied to
//  the same 3-RTT probe and could never be met by a real domestic HTTPS HEAD,
//  which is why every run was labelled "international".
//

import Foundation

enum SpeedTestServerSelection {

    struct Candidate: Equatable {
        let hostname: String
        let label: String
        /// Where this endpoint serves the given exit region from, in plain words.
        let servesFrom: String
    }

    struct Probe: Equatable {
        let candidate: Candidate
        let reachable: Bool
        /// HTTPS HEAD round trip in ms; nil when unreachable or unmeasured.
        let rttMs: Double?
    }

    enum Region: Equatable {
        /// Probe within the same-region envelope.
        case nearby(probeMs: Double)
        /// VPN on: the probe crosses the tunnel; distance to the exit can't be judged from the phone.
        case viaVPN(probeMs: Double?)

        var text: String {
            switch self {
            case .nearby(let ms): return "nearby — \(Int(ms)) ms probe"
            case .viaVPN(let ms): return "through your VPN" + (ms.map { " — \(Int($0)) ms probe" } ?? "")
            }
        }
    }

    enum Decision: Equatable {
        case selected(Candidate, Region)
        case unavailable(reason: String)
    }

    /// See the header for the derivation. HTTPS-HEAD milliseconds.
    static let nearbyProbeThresholdMs: Double = 400

    /// Cloudflare's speed endpoint is the only measurement API the app has
    /// (/__down?bytes= and /__up). Its anycast serves each region from the
    /// nearest PoP; from mainland China it is USUALLY served from outside the
    /// country (the JD Cloud China PoPs carry enterprise zones, not this
    /// endpoint), which is exactly what the probe rule detects.
    static let cloudflare = Candidate(hostname: "speed.cloudflare.com", label: "Cloudflare", servesFrom: "nearest Cloudflare PoP")

    /// Candidates for an exit country. One host today; the list exists so a
    /// verified domestic endpoint can be added for "CN" without touching the
    /// rules. Unknown exit (nil) uses the global list.
    static func candidates(forExitCountry country: String?) -> [Candidate] {
        switch country?.uppercased() {
        case "CN":
            return [Candidate(hostname: cloudflare.hostname, label: cloudflare.label,
                              servesFrom: "Cloudflare — served from a China PoP only if the probe is nearby; otherwise via an international route")]
        default:
            return [cloudflare]
        }
    }

    static func decide(probes: [Probe], vpnActive: Bool, exitCountry: String?) -> Decision {
        var rejections: [String] = []
        for p in probes {
            guard p.reachable else {
                rejections.append("\(p.candidate.label) didn't answer")
                continue
            }
            if vpnActive {
                return .selected(p.candidate, .viaVPN(probeMs: p.rttMs))
            }
            guard let rtt = p.rttMs else {
                rejections.append("\(p.candidate.label) answered but its distance couldn't be measured")
                continue
            }
            if rtt < nearbyProbeThresholdMs {
                return .selected(p.candidate, .nearby(probeMs: rtt))
            }
            rejections.append("\(p.candidate.label) is \(Int(rtt)) ms away on this network (an international route, not a nearby server)")
        }
        let where_ = exitCountry.map { " from \($0)" } ?? ""
        let detail = rejections.isEmpty ? "no test servers are configured for this region" : rejections.joined(separator: "; ")
        return .unavailable(reason: "Couldn't find a nearby test server on this network\(where_) — \(detail). A number measured against a distant server wouldn't describe your connection.")
    }
}
