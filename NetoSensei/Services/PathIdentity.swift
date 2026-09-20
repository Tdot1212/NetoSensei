//
//  PathIdentity.swift
//  NetoSensei
//
//  Commit 10 — rebuild the network status only when the path IDENTITY changed.
//
//  Measured on the user's iPhone (Commit 9 capture): 22 full rebuilds in four
//  minutes on cellular with a VPN. The gate was `NWPath.debugDescription`
//  equality, and that string embeds the interface's radio tag and the tunnel
//  interface with its ipv4/ipv6/dns flags — so every NSA-5G ↔ LTE handover
//  (10 in the same four minutes) and every tunnel negotiation step read as
//  "the network changed" and re-ran every probe.
//
//  What genuinely identifies the active path, all readable synchronously:
//   • path status (satisfied / unsatisfied / requiresConnection)
//   • the PHYSICAL interface carrying traffic: type (Wi-Fi / cellular / wired)
//     and kernel name (en0, pdp_ip0). Stable across a radio handover: the
//     radio generation changes, pdp_ip0 does not.
//   • the Wi-Fi /24 subnet of that interface (the Phase 2/4 key concept) —
//     joining a different network changes it; a handover cannot.
//   • whether traffic is ROUTED THROUGH a tunnel (the path's primary interface
//     is a utun/ipsec) — a genuine VPN on/off. NOT "a utun exists": iPhones
//     carry ipsec4/ipsec5 permanently, and the Commit 9 log showed them with
//     no VPN. The app's own VPN judgement then follows in the rebuild.
//
//  NOT part of the identity (on purpose): radio generation, the tunnel's
//  ipv4/ipv6/dns availability flags, `expensive`/`constrained`, DNS presence,
//  and the SSID (async to read; a Wi-Fi network change also flips status or
//  subnet, and the 30 s periodic rebuild is the backstop).
//
//  Why not NetworkSegment.key: that key describes a RECORD for trend
//  comparison (type|vpn|ssid|subnet|country) and needs async facts (SSID, the
//  app's VPN state, GeoIP country). Path identity is the synchronous,
//  kernel-level view used to decide whether to go and measure at all. It
//  reuses NetworkSegment.subnet(of:) so the two agree on what a subnet is.
//
//  Direction of error: conservative. Anything not proven stable rebuilds.
//

import Foundation

struct PathIdentity: Equatable, CustomStringConvertible {

    enum Status: String { case satisfied, unsatisfied, requiresConnection }
    enum Physical: String { case wifi, cellular, wired, none }

    let status: Status
    let physical: Physical
    /// Kernel interface name of the physical carrier ("en0", "pdp_ip0"); nil when none.
    let physicalName: String?
    /// /24 of the physical interface's IPv4 on Wi-Fi/wired; nil on cellular
    /// (carrier-assigned per session — not an identity, see NetworkSegment).
    let subnet: String?
    /// Traffic is routed through a tunnel interface (VPN on, as the kernel sees it).
    let viaTunnel: Bool

    var description: String {
        "\(status.rawValue)/\(physical.rawValue)(\(physicalName ?? "-"))/\(subnet ?? "-")/\(viaTunnel ? "tunnel" : "direct")"
    }

    /// The reason a rebuild is required, or nil when the identity is unchanged.
    /// `previous == nil` (first path) always rebuilds.
    static func rebuildReason(from previous: PathIdentity?, to current: PathIdentity) -> String? {
        guard let p = previous else { return "first path" }
        if p == current { return nil }
        var reasons: [String] = []
        if p.status != current.status { reasons.append("status \(p.status.rawValue) → \(current.status.rawValue)") }
        if p.physical != current.physical { reasons.append("interface \(p.physical.rawValue) → \(current.physical.rawValue)") }
        else if p.physicalName != current.physicalName { reasons.append("interface \(p.physicalName ?? "-") → \(current.physicalName ?? "-")") }
        if p.subnet != current.subnet { reasons.append("subnet \(p.subnet ?? "-") → \(current.subnet ?? "-")") }
        if p.viaTunnel != current.viaTunnel { reasons.append(current.viaTunnel ? "VPN tunnel now carrying traffic" : "VPN tunnel no longer carrying traffic") }
        return reasons.isEmpty ? "identity differs" : reasons.joined(separator: ", ")
    }
}
