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
//  THRESHOLD SOURCE. The probe (Commit 12: SpeedTestEngine.probe, a GET of the
//  candidate's own zero-byte endpoint on a fresh, non-reused connection) is a
//  full HTTPS exchange: TCP handshake + TLS 1.3 handshake + one HTTP round
//  trip = 3 network RTTs, plus server time. Same-region network RTT is ≤ ~80 ms on Wi-Fi and
//  ≤ ~120 ms on a loaded cellular tower → HEAD ≈ 250–360 ms worst case.
//  The shortest intercontinental path from East Asia (to the US West Coast)
//  is ~130–160 ms network RTT → HEAD ≥ ~450 ms; Europe is ≥ ~600 ms. 400 ms
//  sits in the gap: it admits any same-region server on any access type and
//  rejects every cross-ocean path. The previous "< 80 ms" check was applied to
//  the same 3-RTT probe and could never be met by a real domestic HTTPS HEAD,
//  which is why every run was labelled "international".
//

//  CANDIDATES (Commit 12). A candidate is never asserted to be anywhere. Each
//  one is a concrete endpoint pair with the semantics the engine needs:
//    download: GET returning a body of a requested size (HTTP 2xx, body ≥ 90 %
//              of what was asked — a 200 HTML page is not a measurement)
//    upload:   POST accepting an arbitrary octet-stream body (HTTP 2xx)
//    probe:    GET of a zero-byte endpoint on the SAME backend (2xx), so a
//              host that answers "/" but 404s the test path never qualifies.
//  Two backend shapes exist today:
//    • Cloudflare speed:  /__down?bytes=N        POST /__up
//    • LibreSpeed (PHP):  garbage.php?ckSize=M   POST empty.php   (M = MiB, min 4)
//  The LibreSpeed hosts are the public backends librespeed.org itself lists
//  (backend-servers/servers.php) and that the official librespeed-cli uses by
//  default, each verified (HTTP 200 on empty.php) before listing. None is in
//  mainland China or East Asia. What a candidate SUPPORTS is declared
//  (download / upload); a download-only candidate yields no upload figure and
//  a stated reason — never a silent zero.
//

import Foundation

enum SpeedTestServerSelection {

    enum Capability: Hashable { case download, upload }

    /// The wire shape of a backend. Everything the engine sends is derived
    /// from this; nothing is hand-written per candidate elsewhere.
    enum Backend: Equatable {
        /// speed.cloudflare.com-style: /__down?bytes=N, POST /__up
        case cloudflare(host: String)
        /// LibreSpeed PHP backend at a base URL (no trailing slash):
        /// garbage.php?ckSize=<MiB, min 4>, POST empty.php
        case libreSpeed(base: String)
    }

    struct Candidate: Equatable {
        let label: String
        let backend: Backend
        /// Where this endpoint serves from, in plain words — descriptive only,
        /// never used to decide anything.
        let servesFrom: String
        let supports: Set<Capability>

        var hostname: String {
            switch backend {
            case .cloudflare(let h): return h
            case .libreSpeed(let base): return URL(string: base)?.host ?? base
            }
        }

        /// Zero-byte GET on the test backend itself; must answer 2xx.
        var probeURL: URL? {
            switch backend {
            case .cloudflare(let h): return URL(string: "https://\(h)/__down?bytes=0")
            case .libreSpeed(let base): return URL(string: "\(base)/empty.php")
            }
        }

        func downloadURL(bytes: Int) -> URL? {
            guard supports.contains(.download) else { return nil }
            switch backend {
            case .cloudflare(let h):
                return URL(string: "https://\(h)/__down?bytes=\(bytes)")
            case .libreSpeed(let base):
                // garbage.php takes whole MiB, minimum 4; the engine measures
                // the bytes it actually receives, so the rounding is harmless.
                let mib = max(4, Int((Double(bytes) / 1_048_576).rounded()))
                return URL(string: "\(base)/garbage.php?ckSize=\(mib)")
            }
        }

        var uploadURL: URL? {
            guard supports.contains(.upload) else { return nil }
            switch backend {
            case .cloudflare(let h): return URL(string: "https://\(h)/__up")
            case .libreSpeed(let base): return URL(string: "\(base)/empty.php")
            }
        }
    }

    /// What the engine does about upload for the selected candidate.
    enum UploadPlan: Equatable {
        case measure(URL)
        case unsupported(reason: String)
    }

    static func uploadPlan(for c: Candidate) -> UploadPlan {
        if let url = c.uploadURL { return .measure(url) }
        return .unsupported(reason: "\(c.label) accepts no uploads, so upload speed was not measured on this run.")
    }

    struct Probe: Equatable {
        let candidate: Candidate
        let reachable: Bool
        /// Full HTTPS round trip to the probe endpoint in ms; nil when
        /// unreachable, non-2xx, or unmeasured.
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

    /// See the header for the derivation. HTTPS milliseconds. Commit 11 value; pinned by test.
    static let nearbyProbeThresholdMs: Double = 400

    // MARK: Known candidates

    /// Cloudflare's speed endpoint. Its anycast serves each region from the
    /// nearest PoP; from mainland China it is USUALLY served from outside the
    /// country (1162 ms probe measured in Guangzhou), which the probe rule detects.
    static let cloudflare = Candidate(
        label: "Cloudflare", backend: .cloudflare(host: "speed.cloudflare.com"),
        servesFrom: "nearest Cloudflare PoP (anycast)", supports: [.download, .upload])

    /// Public LibreSpeed backends from librespeed.org's own list. Sponsor
    /// named in the label because the user sees whose server measured them.
    static let libreSpeedLosAngeles = Candidate(
        label: "LibreSpeed Los Angeles (Clouvider)", backend: .libreSpeed(base: "https://la.speedtest.clouvider.net/backend"),
        servesFrom: "Los Angeles, USA", supports: [.download, .upload])
    static let libreSpeedNewYork = Candidate(
        label: "LibreSpeed New York (Clouvider)", backend: .libreSpeed(base: "https://nyc.speedtest.clouvider.net/backend"),
        servesFrom: "New York, USA", supports: [.download, .upload])
    static let libreSpeedLondon = Candidate(
        label: "LibreSpeed London (Clouvider)", backend: .libreSpeed(base: "https://lon.speedtest.clouvider.net/backend"),
        servesFrom: "London, UK", supports: [.download, .upload])
    static let libreSpeedFrankfurt = Candidate(
        label: "LibreSpeed Frankfurt (Clouvider)", backend: .libreSpeed(base: "https://fra.speedtest.clouvider.net/backend"),
        servesFrom: "Frankfurt, Germany", supports: [.download, .upload])

    /// Ordered candidates for an exit country: probed in order, the first
    /// that qualifies is used. Order is a preference among QUALIFYING
    /// servers only; it never lets a distant one through. Cloudflare leads
    /// every list because its anycast is, by construction, the nearest of
    /// these when it is served locally at all.
    ///
    /// EAST ASIA HAS ONE CANDIDATE, on purpose. No mainland-China backend with
    /// these semantics could be verified: the university LibreSpeed instances
    /// are proof-of-work-gated (USTC answers 500 without a token) or
    /// unreachable/intranet-only, Ookla's network is licensed for personal
    /// non-commercial use only, and the sole public LibreSpeed backend in the
    /// region (Tokyo, A573) answered HTTP 403 from every vantage available
    /// when this was written. An unverified candidate is not added.
    static func candidates(forExitCountry country: String?) -> [Candidate] {
        switch country?.uppercased() {
        case "CN", "HK", "MO", "TW", "JP", "KR":
            return [cloudflare]
        case "US", "CA", "MX":
            return [cloudflare, libreSpeedLosAngeles, libreSpeedNewYork]
        case "GB", "IE":
            return [cloudflare, libreSpeedLondon, libreSpeedFrankfurt]
        case "DE", "FR", "NL", "BE", "LU", "AT", "CH", "PL", "CZ", "DK", "SE", "NO", "FI", "IT", "ES", "PT":
            return [cloudflare, libreSpeedFrankfurt, libreSpeedLondon]
        default:
            // Unknown or unlisted exit: the probe alone decides.
            return [cloudflare, libreSpeedLosAngeles, libreSpeedFrankfurt]
        }
    }

    // MARK: Decision (Commit 11 rules, unchanged)

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
