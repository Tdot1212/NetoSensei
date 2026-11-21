import Foundation

enum WiFiRepairGuide: String, CaseIterable, Identifiable {
    case lag = "Lag or dropouts"
    case speed = "Slow downloads"
    case browsing = "Slow browsing"
    case streaming = "Buffering video"
    case vpnPrivacy = "VPN privacy"
    case certificate = "Website security warning"
    case security = "Unrecognized device"

    var isPerformance: Bool {
        switch self {
        case .lag, .speed, .browsing, .streaming: return true
        case .vpnPrivacy, .certificate, .security: return false
        }
    }
    var id: Self { self }

    var steps: [String] {
        switch self {
        case .lag:
            return [
                "Measure a baseline where the problem happens. Pause large downloads, cloud backups and uploads on devices you control, then test from the same spot.",
                "If lag continues, move close to the main router and repeat. If that helps consistently, try Ethernet, move the router into the open, or improve access point placement.",
                "If the problem also affects a wired device while the network is idle, save the results and times for your ISP. If only one app lags, compare another app before changing the router."
            ]
        case .speed:
            return [
                "Measure a baseline, then test close to the router. If your router offers a separate 5 GHz or 6 GHz network, run separate speed tests near the router. The before/after tool requires the same network name. Keep 2.4 GHz available for devices that need its range.",
                "Compare a wired test on the same router with the subscribed speed. If wired is consistently slow, check the router WAN link or cables and contact your ISP with the wired results.",
                "Use the official router app to check for firmware updates. If the router offers an automatic channel survey, use it and retest at the original location."
            ]
        case .browsing:
            return [
                "Open Diagnose → Choose a website, enter the affected site’s hostname, then run the full check. Record its HTTPS response. Try one other site as a reference.",
                "If several sites are slow, measure before and after pausing large transfers on devices you control. Stay on the same Wi-Fi and VPN server.",
                "If just one site is affected, try loading it in Safari on a trusted second connection and repeat the same hostname check. Keep both results if you contact the service."
            ]
        case .streaming:
            return [
                "In Speed → Run all checks, record the measured bandwidth and streaming endpoint response. In your streaming app, replay the same video at the same quality and note when it buffers.",
                "Pause downloads or backups you control, then replay the same video in the same spot. Use the before-and-after check to see whether responsiveness also changed.",
                "If only one service buffers, compare that same video on another trusted connection. Record playback behavior and the endpoint result separately."
            ]
        case .vpnPrivacy:
            return [
                "Open your VPN provider’s documented leak test or built-in diagnostics on a trusted network. Keep your current settings and record the provider’s DNS, public IP, IPv6 and browser WebRTC results where supported.",
                "If the provider flags a leak, check its documented DNS protection or split tunneling setting. Change one relevant setting and repeat the same provider test with the same Wi-Fi and VPN server.",
                "Use the provider’s kill-switch check if offered. Automatic reconnection alone cannot establish whether traffic stops during a tunnel failure."
            ]
        case .certificate:
            return [
                "Avoid entering credentials on the affected site. Check Settings → General → Date & Time, then retry the exact hostname on a trusted connection.",
                "Run Security → Check security and get next steps. Confirm whether the same hostname passes system trust, if it’s among the tested sites.",
                "If the warning follows the site across trusted networks, contact its operator. If it only appears on a managed network, ask its administrator whether certificate inspection is expected."
            ]
        case .security:
            return [
                "Open the official router app or page. Look under Connected devices, Clients or Network map. Check the connection type if listed, since a LAN scan can also see wired devices.",
                "Match the router entry with an address shown on a device you control. On iPhone, open Settings → Wi-Fi → ⓘ next to this network to check its IP and Wi-Fi address. On Mac, open System Settings → Wi-Fi → Details for this network. Confirm the name in General → About.",
                "If you confirm the device should not have access, use the router’s Pause or Block control for that specific client. Recheck the router list. If you suspect the password was shared, change it to a strong, unique one and reconnect only devices you recognize.",
                "Use WPA3 Personal where supported, or WPA2 AES for compatibility. Turn off WPS and remote administration if you don’t need them, update firmware, and set a unique router admin password."
            ]
        }
    }

    /// Open only a numeric address read from the local route; no guessed host,
    /// credentials, or configuration writes.
    static func routerURL(gateway: String?, localSubnet: IPv4Subnet?) -> URL? {
        guard let gateway, let localSubnet, let address = IPv4Subnet.number(gateway),
              address != localSubnet.address, (address & localSubnet.mask) == localSubnet.network,
              address != localSubnet.broadcast, address != localSubnet.network else { return nil }
        return URL(string: "https://\(gateway)")
    }
}
