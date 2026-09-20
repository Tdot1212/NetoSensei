//
//  ConnectionCards.swift
//  NetoSensei
//
//  Commit 9 — pure decisions for the Home connection cards (unit-tested):
//  when the Wi-Fi card shows, when the cellular card shows, and what the
//  cellular card says. Views render these; they do not decide.
//

import Foundation

/// What the Home cellular card shows. Every field is either measured or absent.
struct CellularCardModel: Equatable {
    /// "Connected — 5G" when the generation is known, else just "Connected".
    let statusText: String
    /// nil = iOS reported no generation; no default is invented.
    let generation: String?
    /// One of: measured ms, "Via VPN/proxy" (intercepted), or nil (not measured).
    let latencyText: String?
    let latencyMs: Double?
    let dnsMs: Double?
    /// Latest speed test, only if it ran on THIS network segment recently.
    let downloadMbps: Double?
    let uploadMbps: Double?
    let packetLossPercent: Double?
    let jitterMs: Double?
    let publicIP: String?
    let vpnActive: Bool

    static func statusText(generation: String?) -> String {
        generation.map { "Connected — \($0)" } ?? "Connected"
    }
}

enum ConnectionCards {

    /// A speed test is card evidence only if it ran on this segment within this window.
    static let speedTestFreshness: TimeInterval = 10 * 60

    /// The active path is cellular with no Wi-Fi association.
    static func isCellularOnly(_ status: NetworkStatus) -> Bool {
        status.connectionType == .cellular && !status.wifi.isConnected
    }

    /// Wi-Fi card: shown whenever Wi-Fi is associated (including dual-stack,
    /// where cellular is the active path but Wi-Fi is still up — the Phase 2
    /// dual-stack fix). Hidden on cellular-only: the ABSENCE of Wi-Fi is not a
    /// failure to report when the phone is on mobile data by choice.
    static func showsWiFiCard(_ status: NetworkStatus) -> Bool {
        if status.wifi.isConnected { return true }
        if status.connectionType == .cellular { return false }
        // Not cellular and no Wi-Fi association: keep the card so its
        // "Not connected to Wi-Fi" row can explain a genuinely offline phone.
        return true
    }

    /// Cellular card: shown whenever cellular is the active path (cellular-only
    /// or dual-stack with cellular carrying traffic).
    static func showsCellularCard(_ status: NetworkStatus) -> Bool {
        status.connectionType == .cellular
    }

    /// Build the cellular card from what already ran. `smoothedLatency` is the
    /// dashboard's smoothed value; nil falls back to the raw reading.
    static func cellularCard(status: NetworkStatus,
                             generation: String?,
                             smoothedLatency: Double?,
                             smoothedDNS: Double?,
                             recentSpeedTest: SpeedTestResult?,
                             publicCountry: String?,
                             now: Date = Date()) -> CellularCardModel? {
        guard showsCellularCard(status) else { return nil }

        let intercepted = status.internet.latencyIntercepted
        let latency = intercepted ? nil : (smoothedLatency ?? status.internet.displayableLatency)
        let latencyText: String? = intercepted ? "Via VPN/proxy" : latency.map { "\(Int($0))ms" }
        let dns = smoothedDNS ?? status.dns.displayableLatency

        let vpnOn = status.vpn.isActive || status.vpn.vpnState.isLikelyOn
        let segment = NetworkSegment.key(connectionType: status.connectionType?.displayName ?? "Cellular",
                                         vpnActive: vpnOn, ssid: nil, subnet: nil, country: publicCountry)
        var download: Double?, upload: Double?, loss: Double?, jitter: Double?
        if let s = recentSpeedTest, s.segmentKey == segment, now.timeIntervalSince(s.timestamp) < speedTestFreshness {
            download = s.downloadSpeed > 0 ? s.downloadSpeed : nil
            upload = s.uploadSpeed > 0 ? s.uploadSpeed : nil
            loss = s.packetLoss
            jitter = s.jitter
        }

        return CellularCardModel(
            statusText: CellularCardModel.statusText(generation: generation),
            generation: generation,
            latencyText: latencyText,
            latencyMs: latency,
            dnsMs: dns,
            downloadMbps: download,
            uploadMbps: upload,
            packetLossPercent: loss,
            jitterMs: jitter,
            publicIP: status.publicIP,
            vpnActive: vpnOn
        )
    }
}
