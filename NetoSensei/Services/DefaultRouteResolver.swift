//
//  DefaultRouteResolver.swift
//  NetoSensei
//
//  Diagnosis v2, Commit 1 (accuracy audit Phase 5b).
//
//  Reads the device's REAL default IPv4 gateway from the kernel routing table
//  via the routing sysctl (CTL_NET / PF_ROUTE / NET_RT_FLAGS). The sysctl is
//  public API on iOS; only the <net/route.h> header is absent from the iOS
//  SDK, so the message layout and flag constants are declared here (verified
//  against the macOS SDK with clang: sizeof(rt_msghdr) = 92, rtm_msglen @0,
//  rtm_index @4, rtm_flags @8, rtm_addrs @12).
//
//  Why: the previous "gateway" was a guess — `192.168.x.1` for 192.168 LANs
//  and the literal `10.0.0.1` / `172.x.0.1` for every other private range
//  (NetworkMonitorService heuristic). On hotel, venue and office networks
//  that use 10.x with a different router address, every router probe targeted
//  an address that does not exist, and the Quick Check reported "Router
//  Unreachable" (−40). A guessed address is not a measurement.
//
//  Behaviour under a TUN-mode VPN: the tunnel installs its own default route
//  (gateway `link#N` on utunN). We only accept AF_INET gateways and prefer the
//  physical interface (en*), so the LAN router is returned even when a VPN is
//  active. If only the tunnel's route exists, we return nil rather than guess.
//

import Foundation
import Darwin

enum DefaultRouteResolver {

    struct Route: Equatable {
        let gateway: String      // dotted IPv4
        let interface: String    // e.g. "en0", "utun6", "pdp_ip0"
    }

    // <net/route.h> / <sys/socket.h> values (not exported to Swift on iOS).
    private static let ctlNet: Int32 = 4          // CTL_NET
    private static let pfRoute: Int32 = 17        // PF_ROUTE
    private static let netRtFlags: Int32 = 2      // NET_RT_FLAGS
    private static let rtfUp: Int32 = 0x1         // RTF_UP
    private static let rtfGateway: Int32 = 0x2    // RTF_GATEWAY
    private static let rtaDst: Int32 = 0x1        // RTA_DST
    private static let rtaGateway: Int32 = 0x2    // RTA_GATEWAY
    private static let rtaxDst = 0                // RTAX_DST
    private static let rtaxGateway = 1            // RTAX_GATEWAY
    private static let rtaxMax = 8                // RTAX_MAX
    private static let rtMsgHdrSize = 92          // sizeof(struct rt_msghdr)
    private static let ifNameSize = 16            // IF_NAMESIZE

    /// Every IPv4 default route (destination 0.0.0.0) whose gateway is an IPv4
    /// address, in kernel order. Empty when the table cannot be read.
    static func ipv4DefaultRoutes() -> [Route] {
        var mib: [Int32] = [ctlNet, pfRoute, 0, AF_INET, netRtFlags, rtfGateway]
        var len: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, u_int(mib.count), &buf, &len, nil, 0) == 0 else { return [] }

        var routes: [Route] = []
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + rtMsgHdrSize <= len {
                let msgLen = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard msgLen >= rtMsgHdrSize, offset + msgLen <= len else { break }
                let ifIndex = raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt16.self)
                let flags = raw.loadUnaligned(fromByteOffset: offset + 8, as: Int32.self)
                let addrs = raw.loadUnaligned(fromByteOffset: offset + 12, as: Int32.self)

                let isUpGateway = (flags & rtfGateway) != 0 && (flags & rtfUp) != 0
                let hasNeeded = (addrs & rtaDst) != 0 && (addrs & rtaGateway) != 0
                if isUpGateway && hasNeeded {
                    var addrOffset = offset + rtMsgHdrSize
                    let end = offset + msgLen
                    var destinationIsDefault = false
                    var gateway: String?
                    for bit in 0..<rtaxMax {
                        guard (addrs & (1 << bit)) != 0 else { continue }
                        guard addrOffset + 2 <= end else { break }
                        let saLen = Int(raw.loadUnaligned(fromByteOffset: addrOffset, as: UInt8.self))
                        let family = raw.loadUnaligned(fromByteOffset: addrOffset + 1, as: UInt8.self)
                        if family == UInt8(AF_INET), addrOffset + 8 <= end {
                            // sockaddr_in: sin_len(1) sin_family(1) sin_port(2) sin_addr(4)
                            var addr = raw.loadUnaligned(fromByteOffset: addrOffset + 4, as: in_addr.self)
                            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                            if inet_ntop(AF_INET, &addr, &text, socklen_t(INET_ADDRSTRLEN)) != nil {
                                let str = String(cString: text)
                                if bit == rtaxDst { destinationIsDefault = (str == "0.0.0.0") }
                                if bit == rtaxGateway { gateway = str }
                            }
                        }
                        // sockaddrs are padded to a multiple of 4 bytes; sa_len 0 occupies 4.
                        addrOffset += saLen == 0 ? 4 : ((saLen + 3) & ~3)
                    }
                    if destinationIsDefault, let g = gateway {
                        var name = [CChar](repeating: 0, count: ifNameSize)
                        let ifname = if_indextoname(UInt32(ifIndex), &name).map { String(cString: $0) } ?? "if\(ifIndex)"
                        routes.append(Route(gateway: g, interface: ifname))
                    }
                }
                offset += msgLen
            }
        }
        return routes
    }

    /// The LAN router: the default route on a physical interface (en*, Wi-Fi
    /// or wired). Tunnel (utun*) and cellular (pdp_ip*) defaults are ignored —
    /// there is no "router" on cellular, and a tunnel's gateway is the VPN
    /// server, not the local network.
    static func lanGateway() -> Route? {
        ipv4DefaultRoutes().first { $0.interface.hasPrefix("en") }
    }
}
