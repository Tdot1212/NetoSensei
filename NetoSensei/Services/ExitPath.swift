//
//  ExitPath.swift
//  NetoSensei
//
//  Commit 11 — ONE resolver for "where does this phone's traffic exit?"
//
//  Four sites resolved the public-IP country independently and disagreed:
//  a stored speed-test record keyed on GeoIP-else-detector at test time
//  ("Cellular|direct|CN"), while the Home cellular card keyed on GeoIP alone
//  at render time — empty on a fresh launch ("Cellular|direct|-") — so a
//  valid cellular test never matched its own card. Same source everywhere
//  now; the match rule itself is unchanged (loosening it would let two SIMs
//  compare as one trend, which Phase 4 §G forbids).
//
//  Order: the GeoIP service's cached lookup (verified, 5-minute cache) when it
//  has resolved, else the VPN detector's own IP lookup, else nil. With a VPN
//  on this is the tunnel EXIT, not the phone — which is exactly the reference
//  the speed-test server selection needs.
//
//  Commit 13 — FRESHNESS. Every input above is a cache: GeoIP 300 s (and its
//  clearCache() had no caller), the VPN detector 30 s cooldown plus a
//  "preserve previous result" freeze when its IP lookups time out, and the
//  monitor's own 30 s VPN cache. A network switch is the one event that makes
//  all of them wrong at once, and nothing dropped them. So:
//   • NetworkMonitorService reports each PATH-IDENTITY change here
//     (pathIdentityChanged): the GeoIP cache is cleared and the change time
//     recorded. The monitor also re-runs VPN detection itself.
//   • A user-initiated speed test calls resolveFresh(): anything older than
//     the last identity change is re-read, bounded by a timeout, and if the
//     exit path still cannot be established the answer is .unresolved — an
//     honest "not run", never a pre-switch picture.
//  The decision of which value counts is pure (resolution(_:lastPathChange:))
//  and unit-tested.
//


import Foundation

enum ExitPath {
    /// ISO country code of the current public IP, or nil when neither source
    /// has resolved yet. Never guessed from locale or timezone. Synchronous,
    /// best-available: used for record/card KEYS. For a decision that must
    /// describe the CURRENT network, use resolveFresh().
    @MainActor
    static func country() -> String? {
        let geo = GeoIPService.shared.currentGeoIP
        if !geo.publicIP.isEmpty, let c = geo.countryCode, !c.isEmpty { return c.uppercased() }
        if let c = SmartVPNDetector.shared.detectionResult?.publicCountry, !c.isEmpty { return c.uppercased() }
        return nil
    }

    // MARK: - Commit 13: freshness

    /// When the path identity last changed (Commit 10's gate). Anything
    /// observed before this describes a previous network.
    @MainActor private(set) static var lastPathChange: Date = .distantPast

    /// Called by NetworkMonitorService on every path-identity change.
    @MainActor
    static func pathIdentityChanged(at now: Date = Date()) {
        lastPathChange = now
        GeoIPService.shared.clearCache()
        debugLog("[ExitPath] Path identity changed — GeoIP cache cleared; exit path must be re-resolved")
    }

    /// What the two sources currently hold, with their observation times.
    struct Snapshot: Equatable {
        var geoCountry: String?
        var geoObservedAt: Date?
        var detectorCountry: String?
        var detectorVPNActive: Bool?
        var detectorObservedAt: Date?
        /// The detector's result was frozen from an earlier one (its IP lookups timed out).
        var detectorIsStale: Bool = false
    }

    enum Resolution: Equatable {
        case resolved(country: String?, vpnActive: Bool)
        case unresolved(reason: String)
    }

    static let unresolvedReason = "Couldn't determine your connection yet — the network just changed and its exit path hasn't been re-read. Try again in a moment."

    /// Pure: a value counts only if it was observed AFTER the last path
    /// change. VPN state is mandatory (it picks the nearby-vs-VPN rule);
    /// country comes from GeoIP, else the detector, else nil (global list;
    /// the probe rule still decides).
    static func resolution(_ s: Snapshot, lastPathChange: Date) -> Resolution {
        func fresh(_ t: Date?) -> Bool { t.map { $0 >= lastPathChange } ?? false }
        guard let vpn = s.detectorVPNActive, fresh(s.detectorObservedAt), !s.detectorIsStale else {
            return .unresolved(reason: unresolvedReason)
        }
        let geo = fresh(s.geoObservedAt) ? s.geoCountry : nil
        let det = fresh(s.detectorObservedAt) ? s.detectorCountry : nil
        let country = (geo ?? det).flatMap { $0.isEmpty ? nil : $0.uppercased() }
        return .resolved(country: country, vpnActive: vpn)
    }

    /// Current snapshot of both sources (no network).
    @MainActor
    static func snapshot() -> Snapshot {
        let geoService = GeoIPService.shared
        let geo = geoService.currentGeoIP
        let det = SmartVPNDetector.shared.detectionResult
        return Snapshot(
            geoCountry: geo.publicIP.isEmpty ? nil : geo.countryCode,
            geoObservedAt: geoService.lastFetchAt,
            detectorCountry: det?.publicCountry,
            detectorVPNActive: det?.isVPNActive,
            detectorObservedAt: det?.timestamp,
            detectorIsStale: det?.isStaleData ?? false)
    }

    /// Re-read whatever predates the last path change, bounded, then decide.
    @MainActor
    static func resolveFresh(timeoutSeconds: Int = 12) async -> Resolution {
        let change = lastPathChange
        var snap = snapshot()
        if case .resolved = resolution(snap, lastPathChange: change) {
            debugLog("[ExitPath] Exit path fresh (observed after \(change)) — no re-read needed")
            return resolution(snap, lastPathChange: change)
        }
        debugLog("[ExitPath] Exit path predates the last path change — re-reading VPN state and GeoIP")
        do {
            try await withTimeout(seconds: timeoutSeconds) {
                async let vpn: Void = { _ = await SmartVPNDetector.shared.detectVPN(forceRefresh: true) }()
                async let geo: Void = { _ = await GeoIPService.shared.fetchGeoIPInfo(forceRefresh: true) }()
                _ = await (vpn, geo)
            }
        } catch {
            debugLog("[ExitPath] Re-read timed out after \(timeoutSeconds)s")
        }
        snap = snapshot()
        let r = resolution(snap, lastPathChange: change)
        switch r {
        case .resolved(let c, let v): debugLog("[ExitPath] Resolved fresh: exit=\(c ?? "unknown") vpn=\(v)")
        case .unresolved: debugLog("[ExitPath] Still unresolved after re-read — speed test will not run")
        }
        return r
    }
}
