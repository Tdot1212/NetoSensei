//
//  NetworkSegment.swift
//  NetoSensei
//
//  Accuracy audit Phase 4 (Trends honesty).
//
//  A "trend" is only meaningful between measurements taken on the SAME
//  network in the SAME VPN state. Comparing home Wi-Fi against cellular+VPN
//  is not a trend — it is a network change misread as one (the live bug:
//  "Down 93% (7 vs 122 Mbps)" where 122 was Wi-Fi and 7 was cellular+VPN).
//
//  This file defines the segment key every history record carries so that
//  TrendAnalyzer can refuse to compare across segments. It reuses the
//  Phase 2 `type|ssid|/24` identity concept from DashboardViewModel.
//

import Foundation

enum NetworkSegment {

    /// The /24 prefix of an IPv4 address ("192.168.1.42" → "192.168.1").
    /// Non-IPv4 or nil input → nil (never a guessed subnet).
    static func subnet(of localIP: String?) -> String? {
        guard let ip = localIP else { return nil }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2])"
    }

    /// Segment key for a measurement record.
    ///
    /// Shape: `<type>|<vpn|direct>|<ssid or ->|<subnet or ->`
    ///
    /// - Wi-Fi / wired: SSID and /24 subnet are part of the identity (two
    ///   networks can share a generic SSID like "Guest"; the subnet separates
    ///   them, and it also stands in when SSID is unreadable, e.g. no
    ///   location permission or the simulator).
    /// - Cellular: SSID does not exist and the carrier-assigned /24 changes
    ///   per session, so it is NOT a network identity. The key is
    ///   type + VPN state + the PUBLIC IP COUNTRY (Diagnosis v2, design §G):
    ///   China cellular and a US roaming SIM must not be compared as a trend.
    ///   Honest limits: with a VPN on the country is the VPN exit, not the
    ///   SIM; a home-routed roaming SIM keeps its home country abroad — which
    ///   is correct, it IS the same backhaul path. Carrier name is not used
    ///   (CoreTelephony returns "--" on iOS 16+).
    ///
    /// Records that predate the identity fields have nil SSID/subnet/country
    /// and therefore form their own coarse segment ("WiFi|direct|-|-",
    /// "Cellular|direct|-"). They are never merged with identified records —
    /// we do not invent identity for old data; they simply age out.
    static func key(connectionType: String, vpnActive: Bool, ssid: String?, subnet: String?, country: String? = nil) -> String {
        let vpn = vpnActive ? "vpn" : "direct"
        if isCellular(connectionType) {
            let c = (country?.isEmpty == false) ? country!.uppercased() : "-"
            return "\(connectionType)|\(vpn)|\(c)"
        }
        let s = (ssid?.isEmpty == false) ? ssid! : "-"
        let n = (subnet?.isEmpty == false) ? subnet! : "-"
        return "\(connectionType)|\(vpn)|\(s)|\(n)"
    }

    static func isCellular(_ connectionType: String) -> Bool {
        connectionType.lowercased().contains("cellular")
    }
}
