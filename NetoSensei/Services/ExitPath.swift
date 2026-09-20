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

import Foundation

enum ExitPath {
    /// ISO country code of the current public IP, or nil when neither source
    /// has resolved yet. Never guessed from locale or timezone.
    @MainActor
    static func country() -> String? {
        let geo = GeoIPService.shared.currentGeoIP
        if !geo.publicIP.isEmpty, let c = geo.countryCode, !c.isEmpty { return c.uppercased() }
        if let c = SmartVPNDetector.shared.detectionResult?.publicCountry, !c.isEmpty { return c.uppercased() }
        return nil
    }
}
