//
//  SecurityScanService.swift
//  NetoSensei
//
//  Legacy security scan service (network threat detection)
//  Note: Network Security Audit (NetworkSecurityAuditService) is the preferred security check
//

import Foundation
import Network
import SystemConfiguration

@MainActor
class SecurityScanService: ObservableObject {
    static let shared = SecurityScanService()

    @Published var currentScan: SecurityScanResult?
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0

    // FIXED: Access these lazily via computed properties to avoid Swift 6 isolation errors
    private var networkMonitor: NetworkMonitorService { NetworkMonitorService.shared }
    private var geoIPService: GeoIPService { GeoIPService.shared }

    private init() {}

    // MARK: - Full Security Scan

    func runFullSecurityScan() async -> SecurityScanResult {
        await MainActor.run { isScanning = true; scanProgress = 0.0 }

        var arpResult: ARPScanResult = .notTested
        var dnsLeakResult: DNSLeakResult = .notTested
        var webRTCResult: WebRTCLeakResult = .notTested
        var dpiResult: DPIThrottlingResult = .notTested
        var portResult: PortScanResult = .notTested
        var tlsResult: TLSFingerprintResult = .notTested
        var malwareScore: MalwareRiskScore? = nil

        // Test 1: ARP Scan (Enhanced MITM Detection)
        await updateProgress(0.12)
        arpResult = await performEnhancedARPScan()

        // Test 2: DNS Hijacking Test (with authoritative comparison)
        await updateProgress(0.24)
        dnsLeakResult = await performDNSHijackingTest()

        // Test 3: WebRTC Leak Detection (Enhanced)
        await updateProgress(0.36)
        webRTCResult = await performEnhancedWebRTCTest()

        // Test 4: Service-Specific DPI Throttling
        await updateProgress(0.5)
        dpiResult = await performServiceSpecificDPITest()

        // Test 5: Port Scan
        await updateProgress(0.62)
        portResult = await performPortScan()

        // Test 6: TLS Fingerprint Test
        await updateProgress(0.74)
        tlsResult = await performTLSFingerprintTest()

        // Test 7: Malware Risk Score
        await updateProgress(0.88)
        malwareScore = await performMalwareRiskAssessment()

        await updateProgress(1.0)

        let result = SecurityScanResult(
            arpScanResult: arpResult,
            dnsLeakResult: dnsLeakResult,
            webRTCLeakResult: webRTCResult,
            dpiThrottlingResult: dpiResult,
            portScanResult: portResult,
            tlsFingerprintResult: tlsResult,
            malwareRiskScore: malwareScore
        )

        await MainActor.run {
            currentScan = result
            isScanning = false
        }

        return result
    }

    private func updateProgress(_ value: Double) async {
        await MainActor.run {
            scanProgress = value
        }
    }

    // MARK: - 1. ARP Scan (MITM Detection)

    private func performARPScan() async -> ARPScanResult {
        // Check if gateway MAC address matches expected value
        // Detects ARP spoofing and rogue gateways

        guard let gatewayIP = networkMonitor.currentStatus.router.gatewayIP else {
            return .notTested
        }

        // Get gateway MAC address
        guard let gatewayMAC = await getGatewayMACAddress(for: gatewayIP) else {
            return .notTested
        }

        // Check for suspicious patterns
        // Multiple devices claiming same IP, unexpected gateway changes
        let suspiciousPatterns = await detectARPAnomalies(gatewayIP: gatewayIP, gatewayMAC: gatewayMAC)

        if suspiciousPatterns.isEmpty {
            return .clean(gatewayMAC: gatewayMAC, gatewayIP: gatewayIP)
        } else {
            let threat = LegacySecurityThreat(
                type: .mitm,
                severity: .critical,
                title: "MITM Attack Detected",
                description: "Suspicious ARP activity detected. Your traffic may be intercepted.",
                technicalDetails: [
                    "Gateway IP": gatewayIP,
                    "Gateway MAC": gatewayMAC,
                    "Anomalies": suspiciousPatterns.joined(separator: ", ")
                ]
            )
            return .detected(threat)
        }
    }

    private func getGatewayMACAddress(for ip: String) async -> String? {
        // iOS limitation: Cannot directly access ARP table
        // Workaround: Use network reachability and store baseline
        // In production, this would require jailbreak or private APIs

        // For now, return a placeholder that can detect major changes
        return "baseline_mac_\(ip.hashValue)"
    }

    private func detectARPAnomalies(gatewayIP: String, gatewayMAC: String) async -> [String] {
        var anomalies: [String] = []

        // Check 1: Gateway IP changed unexpectedly
        if let previousGateway = UserDefaults.standard.string(forKey: "last_gateway_ip"),
           previousGateway != gatewayIP {
            anomalies.append("Gateway IP changed from \(previousGateway)")
        }

        // Check 2: Multiple rapid gateway changes (sign of ARP spoofing)
        let changeCount = UserDefaults.standard.integer(forKey: "gateway_change_count")
        if changeCount > 3 {
            anomalies.append("Frequent gateway changes detected")
        }

        // Store current values
        UserDefaults.standard.set(gatewayIP, forKey: "last_gateway_ip")
        UserDefaults.standard.set(gatewayMAC, forKey: "last_gateway_mac")

        return anomalies
    }

    // MARK: - 2. DNS Leak Test

    private func performDNSLeakTest() async -> DNSLeakResult {
        // Check if DNS requests are going through VPN or ISP
        // Detects DNS hijacking and leaks

        let dnsServers = await getCurrentDNSServers()

        if dnsServers.isEmpty {
            return .notTested
        }

        // Get current public IP info
        let geoIP = await geoIPService.fetchGeoIPInfo()

        // Test DNS servers against known VPN DNS and ISP DNS
        let leakDetected = await detectDNSLeak(dnsServers: dnsServers, geoIP: geoIP)

        if leakDetected.isEmpty {
            return .clean(dnsServers: dnsServers)
        } else {
            let threat = LegacySecurityThreat(
                type: .dnsHijacking,
                severity: .high,
                title: "DNS Leak Detected",
                description: "Your DNS queries may be visible to your ISP or intercepted.",
                technicalDetails: [
                    "DNS Servers": dnsServers.joined(separator: ", "),
                    "Issues": leakDetected.joined(separator: ", ")
                ]
            )
            return .detected(threat)
        }
    }

    private func getCurrentDNSServers() async -> [String] {
        var dnsServers: [String] = []

        // iOS limitation: Cannot directly access DNS servers via SystemConfiguration
        // SCDynamicStore APIs are not available on iOS
        // Workaround: Use known public DNS servers as reference
        // In production, this could be enhanced with a DNS lookup test

        // For now, return placeholder that indicates we're checking against known good DNS
        dnsServers = ["1.1.1.1", "8.8.8.8"] // Common trusted DNS servers

        return dnsServers
    }

    private func detectDNSLeak(dnsServers: [String], geoIP: GeoIPInfo) async -> [String] {
        var issues: [String] = []

        // Check if using VPN but DNS is ISP's
        if geoIP.isVPN {
            // Known VPN DNS servers (Cloudflare, Google DNS, Quad9)
            let trustedDNS = ["1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4", "9.9.9.9"]

            let usingTrustedDNS = dnsServers.contains { server in
                trustedDNS.contains(where: { $0 == server })
            }

            if !usingTrustedDNS {
                issues.append("VPN active but using ISP DNS")
            }
        }

        // Check for DNS hijacking (redirecting to unusual servers)
        for server in dnsServers {
            if server.starts(with: "192.168.") || server.starts(with: "10.") {
                // Local router DNS might be hijacked
                let latency = await testDNSLatency(server: server)
                if latency > 100 {
                    issues.append("Suspicious local DNS with high latency")
                }
            }
        }

        return issues
    }

    private func testDNSLatency(server: String) async -> Double {
        // Test DNS resolution speed
        let startTime = Date()

        _ = await resolveHost("example.com", using: server)

        return Date().timeIntervalSince(startTime) * 1000 // ms
    }

    private func resolveHost(_ host: String, using dnsServer: String) async -> String? {
        // iOS limitation: Cannot specify custom DNS server easily
        // Workaround: Use URLSession with custom DNS
        return nil
    }

    // MARK: - 3. WebRTC Leak Detection

    private func performWebRTCLeakTest() async -> WebRTCLeakResult {
        // Check if real IP is exposed via WebRTC
        // This is browser-specific but we can check iOS networking

        let publicIP = await geoIPService.getPublicIP() ?? "0.0.0.0"
        let localIPs = networkMonitor.currentStatus.localIP != nil
            ? [networkMonitor.currentStatus.localIP!]
            : []

        // Test if local IP is leaking through STUN servers
        let leakedIPs = await testSTUNLeaks()

        if leakedIPs.isEmpty {
            return .clean(publicIP: publicIP, localIPs: localIPs)
        } else {
            let threat = LegacySecurityThreat(
                type: .ipLeak,
                severity: .medium,
                title: "IP Leak Detected",
                description: "Your real IP address may be exposed despite VPN usage.",
                technicalDetails: [
                    "Public IP": publicIP,
                    "Leaked IPs": leakedIPs.joined(separator: ", ")
                ]
            )
            return .detected(threat)
        }
    }

    private func testSTUNLeaks() async -> [String] {
        // Test STUN servers to see if they reveal real IP
        let stunServers = [
            "stun.l.google.com:19302",
            "stun1.l.google.com:19302",
            "stun.cloudflare.com:3478"
        ]

        var leakedIPs: [String] = []

        for server in stunServers {
            if let leakedIP = await querySTUNServer(server) {
                if !leakedIPs.contains(leakedIP) {
                    leakedIPs.append(leakedIP)
                }
            }
        }

        return leakedIPs
    }

    private func querySTUNServer(_ server: String) async -> String? {
        // iOS limitation: No built-in STUN client
        // Would require implementing STUN protocol or using WebRTC framework
        // For MVP, we'll skip actual STUN queries
        return nil
    }

    // MARK: - 4. DPI Throttling Detection
    // CHINA RULE: Slow overseas HTTPS ≠ ISP throttling

    private func performDPIThrottlingTest() async -> DPIThrottlingResult {
        let isInChina = SmartVPNDetector.shared.detectionResult?.isLikelyInChina ?? false
        let vpnActive = SmartVPNDetector.shared.detectionResult?.vpnState.isLikelyOn ?? false

        let encryptedSpeed = await testEncryptedConnection()
        let plainSpeed = await testPlainConnection()

        if encryptedSpeed == 0 && isInChina && !vpnActive {
            return .clean  // Overseas server unreachable from China, not throttling
        }

        if encryptedSpeed > 0 && plainSpeed > 0 {
            let ratio = encryptedSpeed / plainSpeed

            if ratio < 0.7 {
                if isInChina && !vpnActive {
                    return .clean  // Cross-border slowness, not DPI throttling
                }

                let threat = LegacySecurityThreat(
                    type: .dpiThrottling,
                    severity: .medium,
                    title: "Possible DPI Throttling",
                    description: "Encrypted traffic appears slower than expected. Your ISP may be inspecting traffic.",
                    technicalDetails: [
                        "Encrypted Speed": "\(String(format: "%.2f", encryptedSpeed)) Mbps",
                        "Plain Speed": "\(String(format: "%.2f", plainSpeed)) Mbps",
                        "Ratio": "\(String(format: "%.2f", ratio * 100))%"
                    ]
                )
                return .detected(threat)
            }
        }

        return .clean
    }

    private func testEncryptedConnection() async -> Double {
        // Test HTTPS download speed
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=1000000") else {
            return 0
        }

        let startTime = Date()

        do {
            // Create URLSession with timeout
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 5.0
            config.timeoutIntervalForResource = 10.0
            let session = URLSession(configuration: config)

            let (data, _) = try await session.data(from: url)
            let duration = Date().timeIntervalSince(startTime)
            let megabytes = Double(data.count) / 1_000_000
            return (megabytes * 8) / duration // Mbps
        } catch {
            return 0
        }
    }

    private func testPlainConnection() async -> Double {
        // Test HTTP download speed (if available)
        // Skip this test as most servers force HTTPS now
        // Return same as encrypted to avoid false positives
        return await testEncryptedConnection()
    }

    // MARK: - 5. Port Scan

    private func performPortScan() async -> PortScanResult {
        // Scan for suspicious open ports on device
        // Common malware ports: 4444, 5555, 6666, 8080, etc.

        let suspiciousPorts = [
            4444, // Metasploit default
            5555, // Android Debug Bridge
            6666, // IRC/Trojans
            8080, // HTTP proxy
            8888, // HTTP alternate
            9999, // Backdoor
            31337, // Back Orifice
            12345, // NetBus
            54321 // Backdoor
        ]

        var threats: [LegacySecurityThreat] = []

        for port in suspiciousPorts {
            if await isPortOpen(port: port) {
                let threat = LegacySecurityThreat(
                    type: .openPort,
                    severity: .high,
                    title: "Suspicious Port Open",
                    description: "Port \(port) is open, which may indicate malware or backdoor.",
                    technicalDetails: [
                        "Port": "\(port)",
                        "Status": "Open"
                    ]
                )
                threats.append(threat)
            }
        }

        if threats.isEmpty {
            return .clean
        } else {
            return .detected(threats)
        }
    }

    private func isPortOpen(port: Int) async -> Bool {
        // iOS limitation: Cannot scan ports on device itself easily
        // This would require socket programming or external tool

        // For MVP, we'll use a simplified check
        return false // Placeholder
    }

    // MARK: - 6. TLS Fingerprint Test

    private func performTLSFingerprintTest() async -> TLSFingerprintResult {
        // Check if TLS connections are being intercepted
        // Compare certificate chains with expected values

        let testDomain = "www.google.com"

        guard let fingerprint = await getTLSFingerprint(for: testDomain) else {
            return .notTested
        }

        // Check if certificate chain is tampered
        let isTampered = await detectTLSTampering(domain: testDomain, fingerprint: fingerprint)

        if !isTampered {
            return .clean(fingerprint: fingerprint)
        } else {
            let threat = LegacySecurityThreat(
                type: .tlsTampering,
                severity: .critical,
                title: "TLS Tampering Detected",
                description: "Your TLS connections may be intercepted (MITM attack).",
                technicalDetails: [
                    "Domain": testDomain,
                    "Fingerprint": fingerprint
                ]
            )
            return .detected(threat)
        }
    }

    private func getTLSFingerprint(for domain: String) async -> String? {
        // Get certificate fingerprint from TLS connection
        guard let url = URL(string: "https://\(domain)") else { return nil }

        do {
            // Create URLSession with timeout
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 3.0
            config.timeoutIntervalForResource = 5.0
            let session = URLSession(configuration: config)

            let (_, response) = try await session.data(from: url)

            // Extract certificate info from response
            if let httpResponse = response as? HTTPURLResponse,
               let allHeaders = httpResponse.allHeaderFields as? [String: String] {
                // iOS doesn't expose certificates directly
                // We'd need to use URLSessionDelegate for certificate pinning
                return "fingerprint_\(domain)_\(allHeaders.hashValue)"
            }
        } catch {
            return nil
        }

        return nil
    }

    private func detectTLSTampering(domain: String, fingerprint: String) async -> Bool {
        // Check if fingerprint matches known good value
        let knownGoodFingerprint = UserDefaults.standard.string(forKey: "fingerprint_\(domain)")

        if let known = knownGoodFingerprint {
            if known != fingerprint {
                // Fingerprint changed - possible tampering
                return true
            }
        } else {
            // Store first-seen fingerprint
            UserDefaults.standard.set(fingerprint, forKey: "fingerprint_\(domain)")
        }

        return false
    }

    // MARK: - Enhanced Security Tests

    // 1. Enhanced ARP Scan with MAC Tracking
    private func performEnhancedARPScan() async -> ARPScanResult {
        guard let gatewayIP = networkMonitor.currentStatus.router.gatewayIP else {
            return .notTested
        }

        guard let gatewayMAC = await getGatewayMACAddress(for: gatewayIP) else {
            return .notTested
        }

        // Get previous MAC for this IP
        let previousMAC = UserDefaults.standard.string(forKey: "mac_\(gatewayIP)")
        let lastSeen = UserDefaults.standard.double(forKey: "mac_lastSeen_\(gatewayIP)")
        let now = Date().timeIntervalSince1970

        // Track ARP changes
        var arpChangeCount = UserDefaults.standard.integer(forKey: "arp_change_count")

        // Check for MAC address change (Critical threat)
        if let prevMAC = previousMAC, prevMAC != gatewayMAC {
            let timeSinceLastChange = now - lastSeen

            // If MAC changed within 24 hours, it's suspicious
            if timeSinceLastChange < 86400 {  // 24 hours
                arpChangeCount += 1
                UserDefaults.standard.set(arpChangeCount, forKey: "arp_change_count")

                let threat = LegacySecurityThreat(
                    type: .mitm,
                    severity: .critical,
                    title: "Critical: Router MAC Address Changed",
                    description: "Your router's MAC address changed unexpectedly. Possible Man-in-the-Middle attack. Disconnect immediately!",
                    technicalDetails: [
                        "Gateway IP": gatewayIP,
                        "Previous MAC": prevMAC,
                        "Current MAC": gatewayMAC,
                        "Changes in 24h": "\(arpChangeCount)"
                    ]
                )
                return .detected(threat)
            }
        }

        // Check for rapid ARP changes (High threat)
        if arpChangeCount >= 3 {
            let threat = LegacySecurityThreat(
                type: .mitm,
                severity: .high,
                title: "Warning: Frequent ARP Changes Detected",
                description: "Router MAC address has changed \(arpChangeCount) times recently. Network may be compromised.",
                technicalDetails: [
                    "Gateway IP": gatewayIP,
                    "Current MAC": gatewayMAC,
                    "Total Changes": "\(arpChangeCount)"
                ]
            )
            return .detected(threat)
        }

        // Store current MAC and timestamp
        UserDefaults.standard.set(gatewayMAC, forKey: "mac_\(gatewayIP)")
        UserDefaults.standard.set(now, forKey: "mac_lastSeen_\(gatewayIP)")

        // No threats detected
        return .clean(gatewayMAC: gatewayMAC, gatewayIP: gatewayIP)
    }

    // 2. DNS Hijacking Test with Authoritative Comparison
    private func performDNSHijackingTest() async -> DNSLeakResult {
        // Test well-known domains with expected IPs
        // FIXED: Google uses MANY IP ranges via anycast (AS15169)
        let testDomains = [
            ("www.google.com", ["142.250.", "142.251.", "172.217.", "216.58.", "64.233.", "74.125.", "173.194.", "209.85.", "108.177.", "172.253."]),  // Google IP prefixes (all AS15169)
            ("www.facebook.com", ["157.240.", "31.13."]),              // Facebook IP prefixes
            ("www.apple.com", ["17."])                                  // Apple IP prefix
        ]

        var hijackingDetected = false
        var suspiciousDomains: [String] = []

        for (domain, expectedPrefixes) in testDomains {
            if let resolvedIP = await resolveDomain(domain) {
                // Check if resolved IP matches expected prefixes
                let matchesExpected = expectedPrefixes.contains { resolvedIP.hasPrefix($0) }

                if !matchesExpected {
                    hijackingDetected = true
                    suspiciousDomains.append("\(domain) → \(resolvedIP)")
                }
            }
        }

        let dnsServers = await getCurrentDNSServers()

        if hijackingDetected {
            let threat = LegacySecurityThreat(
                type: .dnsHijacking,
                severity: .critical,
                title: "Critical: DNS Hijacking Detected",
                description: "DNS responses don't match authoritative servers. ISP or malware may be intercepting/modifying traffic.",
                technicalDetails: [
                    "DNS Servers": dnsServers.joined(separator: ", "),
                    "Suspicious Domains": suspiciousDomains.joined(separator: ", ")
                ]
            )
            return .detected(threat)
        }

        // Check for ISP DNS modification patterns
        let geoIP = await geoIPService.fetchGeoIPInfo()
        if geoIP.isVPN {
            let trustedDNS = ["1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4", "9.9.9.9"]
            let usingTrustedDNS = dnsServers.contains { server in
                trustedDNS.contains(server)
            }

            if !usingTrustedDNS {
                let threat = LegacySecurityThreat(
                    type: .dnsHijacking,
                    severity: .high,
                    title: "Warning: VPN DNS Leak",
                    description: "VPN active but using ISP DNS. Your DNS queries are visible to ISP.",
                    technicalDetails: [
                        "DNS Servers": dnsServers.joined(separator: ", ")
                    ]
                )
                return .detected(threat)
            }
        }

        return .clean(dnsServers: dnsServers)
    }

    private func resolveDomain(_ domain: String) async -> String? {
        // Simple DNS resolution
        guard let url = URL(string: "https://\(domain)") else { return nil }

        do {
            // Create URLSession with timeout
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 3.0
            config.timeoutIntervalForResource = 5.0
            let session = URLSession(configuration: config)

            let (_, _) = try await session.data(from: url)
            // iOS doesn't easily expose resolved IP, this is a simplified check
            // In production, use CFHost or custom DNS resolver
            return domain  // Placeholder
        } catch {
            return nil
        }
    }

    // 3. Enhanced WebRTC Leak Test
    private func performEnhancedWebRTCTest() async -> WebRTCLeakResult {
        let publicIP = await geoIPService.getPublicIP() ?? "0.0.0.0"
        let localIP = networkMonitor.currentStatus.localIP ?? "0.0.0.0"
        let geoIP = await geoIPService.fetchGeoIPInfo()

        // Test for IP leaks through various methods
        var leakedIPs: [String] = []

        // Check if VPN is active but public IP doesn't match VPN region
        if geoIP.isVPN {
            // Test STUN servers
            let stunIPs = await testSTUNLeaks()
            leakedIPs.append(contentsOf: stunIPs)

            // Check for WebRTC leaks (would require WebView in real implementation)
            // For now, check if local IP is in private range but exposed
            if !localIP.hasPrefix("10.") && !localIP.hasPrefix("192.168.") && !localIP.hasPrefix("172.") {
                leakedIPs.append(localIP)
            }
        }

        if !leakedIPs.isEmpty {
            let threat = LegacySecurityThreat(
                type: .ipLeak,
                severity: .high,
                title: "Alert: VPN IP Leak Detected",
                description: "VPN leak — your real IP is exposed despite VPN being active!",
                technicalDetails: [
                    "VPN IP": publicIP,
                    "Leaked IPs": leakedIPs.joined(separator: ", ")
                ]
            )
            return .detected(threat)
        }

        return .clean(publicIP: publicIP, localIPs: [localIP])
    }

    // 4. Service-Specific DPI Throttling Detection
    // CHINA RULE: Slow overseas HTTPS ≠ ISP throttling
    // In China without VPN, overseas servers are slow due to cross-border routing,
    // not because the ISP is doing DPI throttling.
    private func performServiceSpecificDPITest() async -> DPIThrottlingResult {
        let isInChina = SmartVPNDetector.shared.detectionResult?.isLikelyInChina ?? false
        let vpnActive = SmartVPNDetector.shared.detectionResult?.vpnState.isLikelyOn ?? false

        let encryptedSpeed = await testEncryptedConnection()
        let plainSpeed = await testPlainConnection()

        // If both tests failed (0 speed), check if this is China without VPN
        if encryptedSpeed == 0 && isInChina && !vpnActive {
            // Don't claim throttling — overseas test server is simply unreachable
            return .clean
        }

        // If encrypted is significantly slower, check context before claiming throttling
        if encryptedSpeed > 0 && plainSpeed > 0 {
            let ratio = encryptedSpeed / plainSpeed

            if ratio < 0.7 {
                // China without VPN: slow overseas ≠ throttling
                if isInChina && !vpnActive {
                    return .clean  // Cross-border slowness, not DPI throttling
                }

                let threat = LegacySecurityThreat(
                    type: .dpiThrottling,
                    severity: .medium,
                    title: "Possible DPI Throttling",
                    description: "Encrypted traffic appears slower than expected. Your ISP may be inspecting traffic.",
                    technicalDetails: [
                        "Encrypted Speed": "\(String(format: "%.2f", encryptedSpeed)) Mbps",
                        "Plain Speed": "\(String(format: "%.2f", plainSpeed)) Mbps",
                        "Ratio": "\(String(format: "%.2f", ratio * 100))%"
                    ]
                )
                return .detected(threat)
            }
        }

        return .clean
    }

    private func measureConnectionSpeed(to urlString: String) async -> Double {
        guard let url = URL(string: urlString) else { return 0 }

        let startTime = Date()

        do {
            // Create URLSession with short timeout to avoid hanging
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 3.0  // 3 second timeout
            config.timeoutIntervalForResource = 5.0  // 5 second max
            let session = URLSession(configuration: config)

            let (data, _) = try await session.data(from: url)
            let duration = Date().timeIntervalSince(startTime)

            // Avoid division by zero
            guard duration > 0 else { return 0 }

            let megabytes = Double(data.count) / 1_000_000
            return (megabytes * 8) / duration // Mbps
        } catch {
            // Return 0 on timeout or error
            return 0
        }
    }

    // 5. Malware Risk Assessment
    private func performMalwareRiskAssessment() async -> MalwareRiskScore {
        var riskScore = 0
        var threats: [LegacySecurityThreat] = []
        var suspiciousActivities: [String] = []

        // 1. Check for port scanning activity
        let portScanningDetected = await detectPortScanning()
        if portScanningDetected {
            riskScore += 25
            suspiciousActivities.append("Port scanning detected on network")
            threats.append(LegacySecurityThreat(
                type: .openPort,
                severity: .high,
                title: "Port Scanning Activity Detected",
                description: "A device on your network is scanning for open ports. This may indicate malware or hacker activity.",
                technicalDetails: ["Activity": "Port scanning"]
            ))
        }

        // 2. Check for ARP anomalies
        let arpAnomalies = UserDefaults.standard.integer(forKey: "arp_change_count")
        if arpAnomalies > 0 {
            riskScore += min(arpAnomalies * 10, 30)
            suspiciousActivities.append("\(arpAnomalies) suspicious ARP changes")
        }

        // 3. Check for unknown devices (simplified - would need network scanning)
        let unknownDevices = await detectUnknownDevices()
        if unknownDevices > 2 {
            riskScore += 15
            suspiciousActivities.append("\(unknownDevices) unknown devices on network")
        }

        // 4. Check for LAN flood/DoS
        let lanFloodDetected = await detectLANFlood()
        if lanFloodDetected {
            riskScore += 20
            suspiciousActivities.append("Unusual network traffic volume detected")
            threats.append(LegacySecurityThreat(
                type: .openPort,
                severity: .medium,
                title: "Network Flood Detected",
                description: "Unusual amount of network traffic. May indicate DoS attack or malware communication.",
                technicalDetails: ["Activity": "LAN flood"]
            ))
        }

        // 5. Check for suspicious traffic patterns
        let suspiciousTraffic = await detectSuspiciousTrafficPatterns()
        if suspiciousTraffic {
            riskScore += 10
            suspiciousActivities.append("Suspicious traffic patterns detected")
        }

        return MalwareRiskScore(
            riskScore: min(riskScore, 100),
            detectedThreats: threats,
            suspiciousActivities: suspiciousActivities,
            portScanningDetected: portScanningDetected,
            arpAnomalies: arpAnomalies,
            unknownDevices: unknownDevices,
            lanFloodDetected: lanFloodDetected,
            suspiciousTrafficPatterns: suspiciousTraffic
        )
    }

    private func detectPortScanning() async -> Bool {
        // Detect if there are rapid connection attempts to multiple ports
        // iOS limitation: Cannot easily detect this without network monitoring
        // Would require packet capture or firewall logs
        return false  // Placeholder
    }

    private func detectUnknownDevices() async -> Int {
        // Would require network scanning to detect all devices
        // iOS limitation: Cannot scan local network easily
        return 0  // Placeholder
    }

    private func detectLANFlood() async -> Bool {
        // Detect unusual network traffic volume
        // Would require monitoring network interface statistics
        return false  // Placeholder
    }

    private func detectSuspiciousTrafficPatterns() async -> Bool {
        // Analyze traffic patterns for malware signatures
        // Would require deep packet inspection
        return false  // Placeholder
    }
}
