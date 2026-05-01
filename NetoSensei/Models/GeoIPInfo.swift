//
//  GeoIPInfo.swift
//  NetoSensei
//
//  Geolocation and IP information model
//

import Foundation

struct GeoIPInfo: Codable {
    var publicIP: String
    var ipVersion: String  // "IPv4" or "IPv6"

    // Location
    var country: String?
    var countryCode: String?
    var region: String?
    var city: String?
    var latitude: Double?
    var longitude: Double?
    var timezone: String?

    // ISP Information
    var isp: String?
    var org: String?
    var asn: String?  // Autonomous System Number
    var asnOrg: String?

    // Security flags
    var isProxy: Bool
    var isVPN: Bool
    var isTor: Bool
    var isHosting: Bool
    var isRelay: Bool

    // CGNAT detection
    var isCGNAT: Bool

    // DNS information
    var hostname: String?
    var dnsProvider: String?

    var displayLocation: String {
        var parts: [String] = []
        if let city = city { parts.append(city) }
        if let region = region { parts.append(region) }
        if let country = country { parts.append(country) }
        return parts.joined(separator: ", ")
    }

    var ispDisplay: String {
        isp ?? org ?? "Unknown ISP"
    }

    var securityWarnings: [String] {
        var warnings: [String] = []
        if isProxy { warnings.append("Proxy detected") }
        if isVPN { warnings.append("VPN detected") }
        if isTor { warnings.append("Tor exit node") }
        if isHosting { warnings.append("Hosting/Data center IP") }
        if isCGNAT { warnings.append("Carrier-grade NAT detected") }
        return warnings
    }

    var hasSecurityFlags: Bool {
        isProxy || isVPN || isTor || isHosting || isCGNAT
    }

    static var empty: GeoIPInfo {
        GeoIPInfo(
            publicIP: "0.0.0.0",
            ipVersion: "IPv4",
            isProxy: false,
            isVPN: false,
            isTor: false,
            isHosting: false,
            isRelay: false,
            isCGNAT: false
        )
    }
}

// Response models for various GeoIP APIs
struct IPAPIResponse: Codable {
    var query: String?
    var status: String?
    var country: String?
    var countryCode: String?
    var region: String?
    var regionName: String?
    var city: String?
    var lat: Double?
    var lon: Double?
    var timezone: String?
    var isp: String?
    var org: String?
    var `as`: String?
    var proxy: Bool?
    var hosting: Bool?
}

struct IPInfoResponse: Codable {
    var ip: String
    var hostname: String?
    var city: String?
    var region: String?
    var country: String?
    var loc: String?
    var org: String?
    var timezone: String?
    var asn: ASNInfo?

    struct ASNInfo: Codable {
        var asn: String?
        var name: String?
        var domain: String?
        var route: String?
        var type: String?
    }

    var privacy: PrivacyInfo?

    struct PrivacyInfo: Codable {
        var vpn: Bool?
        var proxy: Bool?
        var tor: Bool?
        var relay: Bool?
        var hosting: Bool?
    }
}
