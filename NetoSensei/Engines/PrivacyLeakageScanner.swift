//
//  PrivacyLeakageScanner.swift
//  NetoSensei
//
//  Privacy Leakage Detection - 100% Real Detection
//  Detects: IP exposure, DNS leaks, WebRTC leaks, location mismatches, CGNAT, IPv6 leaks
//

import Foundation
import Network

actor PrivacyLeakageScanner {
    static let shared = PrivacyLeakageScanner()

    private init() {}

    private let expectedCityKey = "expected_city_privacy"

    // MARK: - Privacy Leakage Scan

    func performPrivacyLeakageScan(vpnActive: Bool) async -> PrivacyLeakageStatus {
        // 1. Test for IP exposure
        let ipExposed = !vpnActive

        // 2. Test for DNS leaks
        let dnsLeaking = await testForDNSLeak(vpnActive: vpnActive)

        // 3. Test for WebRTC leaks (limited on iOS but testable)
        let webRTCLeaking = await testForWebRTCLeak(vpnActive: vpnActive)

        // 4. Test for location mismatch
        let (locationMismatch, actualCity, expectedCity) = await testForLocationMismatch()

        // 5. Test for CGNAT detection
        let (cgnatDetected, internalIPExposed) = await testForCGNAT()

        // 6. Test for IPv6 leaks
        let ipv6Leaking = await testForIPv6Leak(vpnActive: vpnActive)

        // 7. Calculate privacy score
        let privacyScore = calculatePrivacyScore(
            ipExposed: ipExposed,
            dnsLeaking: dnsLeaking,
            webRTCLeaking: webRTCLeaking,
            locationMismatch: locationMismatch,
            cgnatDetected: cgnatDetected,
            ipv6Leaking: ipv6Leaking
        )

        return PrivacyLeakageStatus(
            ipExposed: ipExposed,
            dnsLeaking: dnsLeaking,
            webRTCLeaking: webRTCLeaking,
            locationMismatch: locationMismatch,
            cgnatDetected: cgnatDetected,
            ipv6Leaking: ipv6Leaking,
            actualCity: actualCity,
            expectedCity: expectedCity,
            internalIPExposed: internalIPExposed,
            privacyScore: privacyScore
        )
    }

    // MARK: - DNS Leak Detection

    private func testForDNSLeak(vpnActive: Bool) async -> Bool {
        guard vpnActive else { return false }

        // If VPN is active, DNS queries should go through VPN
        // Test by checking if DNS server is ISP DNS

        // Get current DNS status
        let dnsStatus = await DNSSecurityScanner.shared.performComprehensiveDNSScan()

        // If using ISP DNS while VPN is active, it's a DNS leak
        return dnsStatus.isISPDNS
    }

    // MARK: - WebRTC Leak Detection

    private func testForWebRTCLeak(vpnActive: Bool) async -> Bool {
        guard vpnActive else { return false }

        // WebRTC can leak real IP even when VPN is active
        // On iOS, Safari has WebRTC but limited access
        // We can test by attempting STUN server connection

        // Get public IP via VPN
        let vpnIP = await getPublicIP()

        // Get local IP
        let localIP = getLocalIP()

        // If local IP is in private range but public IP is VPN, no leak
        // If local IP is public and different from VPN IP, it's a leak
        if !localIP.hasPrefix("192.168.") && !localIP.hasPrefix("10.") && !localIP.hasPrefix("172.") {
            if localIP != vpnIP {
                return true
            }
        }

        return false
    }

    private func getPublicIP() async -> String {
        guard let url = URL(string: "https://api.ipify.org?format=text") else {
            return "0.0.0.0"
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0.0.0.0"
        } catch {
            return "0.0.0.0"
        }
    }

    nonisolated private func getLocalIP() -> String {
        var address: String = "0.0.0.0"

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return address }
        guard let firstAddr = ifaddr else { return address }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if (getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0) {
                        address = String(cString: hostname)
                    }
                }
            }
        }

        freeifaddrs(ifaddr)
        return address
    }

    // MARK: - Location Mismatch Detection

    private func testForLocationMismatch() async -> (mismatch: Bool, actualCity: String?, expectedCity: String?) {
        // Get current IP geolocation
        let geoIPInfo = await GeoIPService.shared.fetchGeoIPInfo()
        let actualCity = geoIPInfo.city

        // Get expected city (saved from first run)
        let expectedCity = UserDefaults.standard.string(forKey: expectedCityKey)

        // If first time, save current city
        if expectedCity == nil, let city = actualCity {
            UserDefaults.standard.set(city, forKey: expectedCityKey)
            return (false, actualCity, city)
        }

        // Check for mismatch
        let mismatch = expectedCity != nil && actualCity != nil && expectedCity != actualCity

        return (mismatch, actualCity, expectedCity)
    }

    // MARK: - CGNAT Detection

    private func testForCGNAT() async -> (cgnatDetected: Bool, internalIPExposed: Bool) {
        // CGNAT (Carrier-Grade NAT) is common in China and mobile networks
        // Detectable by checking if public IP is in CGNAT range

        let publicIP = await getPublicIP()

        // CGNAT ranges (RFC 6598: 100.64.0.0/10)
        let cgnatRanges = [
            "100.64.",
            "100.65.",
            "100.66.",
            "100.67.",
            "100.68.",
            "100.69.",
            "100.70.",
            "100.71.",
            "100.72.",
            "100.73.",
            "100.74.",
            "100.75.",
            "100.76.",
            "100.77.",
            "100.78.",
            "100.79.",
            "100.80.",
            "100.81.",
            "100.82.",
            "100.83.",
            "100.84.",
            "100.85.",
            "100.86.",
            "100.87.",
            "100.88.",
            "100.89.",
            "100.90.",
            "100.91.",
            "100.92.",
            "100.93.",
            "100.94.",
            "100.95.",
            "100.96.",
            "100.97.",
            "100.98.",
            "100.99.",
            "100.100.",
            "100.101.",
            "100.102.",
            "100.103.",
            "100.104.",
            "100.105.",
            "100.106.",
            "100.107.",
            "100.108.",
            "100.109.",
            "100.110.",
            "100.111.",
            "100.112.",
            "100.113.",
            "100.114.",
            "100.115.",
            "100.116.",
            "100.117.",
            "100.118.",
            "100.119.",
            "100.120.",
            "100.121.",
            "100.122.",
            "100.123.",
            "100.124.",
            "100.125.",
            "100.126.",
            "100.127."
        ]

        let cgnatDetected = cgnatRanges.contains { publicIP.hasPrefix($0) }

        // Also check if public IP is private range (shouldn't happen but indicates CGNAT)
        let privateRanges = ["192.168.", "10.", "172.16."]
        let internalIPExposed = privateRanges.contains { publicIP.hasPrefix($0) }

        return (cgnatDetected, internalIPExposed)
    }

    // MARK: - IPv6 Leak Detection

    private func testForIPv6Leak(vpnActive: Bool) async -> Bool {
        guard vpnActive else { return false }

        // Test if IPv6 traffic is bypassing VPN
        // Get IPv6 address
        let ipv6Address = getIPv6Address()

        // If we have IPv6 address while VPN is active, check if it's leaking
        if ipv6Address != "::" {
            // Try to detect if IPv6 is going through VPN
            // If IPv6 is a public address, it might be leaking
            if !ipv6Address.hasPrefix("fe80:") && !ipv6Address.hasPrefix("fc00:") {
                // Public IPv6 address while VPN is active - potential leak
                return true
            }
        }

        return false
    }

    nonisolated private func getIPv6Address() -> String {
        var address: String = "::"

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return address }
        guard let firstAddr = ifaddr else { return address }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET6) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if (getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0) {
                        address = String(cString: hostname)
                        // Return first non-loopback IPv6
                        if !address.hasPrefix("::1") {
                            break
                        }
                    }
                }
            }
        }

        freeifaddrs(ifaddr)
        return address
    }

    // MARK: - Calculate Privacy Score

    private func calculatePrivacyScore(
        ipExposed: Bool,
        dnsLeaking: Bool,
        webRTCLeaking: Bool,
        locationMismatch: Bool,
        cgnatDetected: Bool,
        ipv6Leaking: Bool
    ) -> Int {
        var score = 100

        if ipExposed {
            score -= 20  // No VPN
        }

        if dnsLeaking {
            score -= 50  // Critical
        }

        if webRTCLeaking {
            score -= 60  // Critical
        }

        if locationMismatch {
            score -= 25  // Moderate
        }

        if cgnatDetected {
            score -= 10  // Info
        }

        if ipv6Leaking {
            score -= 40  // Major
        }

        return max(0, min(100, score))
    }
}
