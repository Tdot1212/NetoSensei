//
//  SecurityEngine.swift
//  NetoSensei
//
//  Security Engine - ARP, DNS, VPN leak detection (iOS-compatible)
//

import Foundation
import Network
// FIXED: Removed NetworkExtension import - not used in this file

actor SecurityEngine {
    static let shared = SecurityEngine()

    private init() {}

    // MARK: - DNS Hijacking Test

    func runDNSHijackTest() async -> Result<[DNSHijackResult], DiagnosticError> {
        // Region-aware DNS testing
        // China-native domains help separate ISP behavior from actual DNS failure
        //
        // FIXED: Google owns MANY IP ranges via anycast (AS15169):
        // - 142.250.0.0/15, 172.217.0.0/16, 172.253.0.0/16, 216.58.0.0/16
        // - 64.233.0.0/16, 74.125.0.0/16, 173.194.0.0/16, 209.85.0.0/16
        // - 108.177.0.0/17, 192.178.0.0/15 (includes 192.178.x and 192.179.x)
        // - 216.239.0.0/16, 35.186.0.0/15 through 35.191.0.0/16
        // All prefixes must be included to avoid false positives!
        //
        let testDomains: [(domain: String, expectedPrefixes: [String], region: DNSRegion)] = [
            // China-native domain (primary reference)
            ("baidu.com", ["110.242.", "220.181.", "39.156."], .chinaNative),

            // Overseas domains
            ("cloudflare.com", ["104.16.", "104.17.", "104.18.", "104.19.", "104.20.", "104.21.", "172.64.", "172.65.", "172.66.", "172.67."], .overseas),

            // FIXED: Google's complete IP range list (AS15169)
            // 192.178.x.x was being flagged as hijacked but Google owns this range!
            ("google.com", [
                "142.250.", "142.251.",   // Primary anycast ranges
                "172.217.", "172.253.",   // Common ranges
                "216.58.", "216.239.",    // Legacy ranges
                "64.233.", "74.125.",     // Older ranges
                "173.194.", "209.85.",    // Additional ranges
                "108.177.",               // Additional range
                "192.178.", "192.179.",   // FIXED: Google owns 192.178.0.0/15
                "35.186.", "35.187.", "35.188.", "35.189.", "35.190.", "35.191.",  // Google Cloud
                "34."                     // Google Cloud (broader range)
            ], .overseas),

            ("apple.com", ["17."], .overseas)
        ]

        var results: [DNSHijackResult] = []

        // FIXED: Check VPN status - VPN routing can cause DNS to resolve differently
        let vpnActive = await isVPNActiveAsync()

        // ISSUE 7 FIX: Known proxy/VPN fake-IP ranges used by Surge, Shadowrocket,
        // Quantumult X, Clash, etc. These intercept DNS and return synthetic addresses
        // to route traffic through the tunnel. This is NORMAL, not hijacking.
        let proxyFakeRanges = ["198.18.", "198.19.", "100.100.", "10.10.10.", "28.0.0."]

        for test in testDomains {
            do {
                let resolvedIPs = try await withTimeout(seconds: 2) {
                    try await self.resolveDomain(test.domain)
                }

                // ISSUE 7 FIX: Check if ALL resolved IPs are in proxy fake-IP ranges
                let allProxyFakeIPs = !resolvedIPs.isEmpty && resolvedIPs.allSatisfy { ip in
                    proxyFakeRanges.contains { ip.hasPrefix($0) }
                }

                if allProxyFakeIPs {
                    // This is normal VPN/proxy DNS routing, NOT hijacking
                    let result = DNSHijackResult(
                        domain: test.domain,
                        expectedIPs: test.expectedPrefixes,
                        resolvedIPs: resolvedIPs,
                        hijacked: false,
                        confidence: 1.0,
                        region: test.region,
                        note: "DNS routed through VPN/proxy tunnel (normal behavior)"
                    )
                    results.append(result)
                    continue
                }

                // Check if resolved IPs match expected prefixes
                let hijacked = !resolvedIPs.contains { resolvedIP in
                    test.expectedPrefixes.contains { prefix in
                        resolvedIP.hasPrefix(prefix)
                    }
                }

                var note: String? = nil
                if hijacked && vpnActive {
                    note = "VPN may route DNS differently - verify in VPN-off state"
                }

                let result = DNSHijackResult(
                    domain: test.domain,
                    expectedIPs: test.expectedPrefixes,
                    resolvedIPs: resolvedIPs,
                    hijacked: hijacked,
                    confidence: hijacked ? (vpnActive ? 0.5 : 0.9) : 1.0,
                    region: test.region,
                    note: note
                )
                results.append(result)

            } catch {
                // Timeout or failure - assume no hijacking
                let result = DNSHijackResult(
                    domain: test.domain,
                    expectedIPs: test.expectedPrefixes,
                    resolvedIPs: [],
                    hijacked: false,
                    confidence: 0.0,
                    region: test.region
                )
                results.append(result)
            }
        }

        // FIXED: VPN-aware interpretation
        // If VPN is active and only overseas domains appear "hijacked", it's likely VPN routing
        if vpnActive {
            let hijackedOverseas = results.filter { $0.hijacked && $0.region == .overseas }
            if !hijackedOverseas.isEmpty {
                results = results.map { result in
                    if result.hijacked && result.region == .overseas {
                        return DNSHijackResult(
                            domain: result.domain,
                            expectedIPs: result.expectedIPs,
                            resolvedIPs: result.resolvedIPs,
                            hijacked: false,  // Downgrade: VPN routing, not hijacking
                            confidence: 0.3,
                            region: result.region,
                            note: "DNS routed through VPN - different IP is expected"
                        )
                    }
                    return result
                }
            }
        }

        return .success(results)
    }

    private func resolveDomain(_ domain: String) async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            let host = CFHostCreateWithName(nil, domain as CFString).takeRetainedValue()

            CFHostStartInfoResolution(host, .addresses, nil)

            var success: DarwinBoolean = false
            guard let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as? [Data] else {
                continuation.resume(throwing: DiagnosticError.noResponse)
                return
            }

            var ips: [String] = []
            for data in addresses {
                data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
                    if let sockaddr = pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self) {
                        if sockaddr.pointee.sa_family == AF_INET {
                            let addr = pointer.baseAddress!.assumingMemoryBound(to: sockaddr_in.self)
                            let ip = String(cString: inet_ntoa(addr.pointee.sin_addr), encoding: .ascii) ?? ""
                            if !ip.isEmpty {
                                ips.append(ip)
                            }
                        }
                    }
                }
            }

            continuation.resume(returning: ips)
        }
    }

    // MARK: - VPN Leak Test

    func runVPNLeakTest() async -> Result<VPNLeakResult, DiagnosticError> {
        debugLog("🔍 [VPN Leak Test] Starting VPN leak test...")

        // FIXED: Use SmartVPNDetector's cached result instead of separate detection
        // This ensures consistency with the main VPN detection shown in the app
        debugLog("🔍 [VPN Leak Test] Checking SmartVPNDetector cached result...")
        let vpnActive: Bool
        if let cachedResult = await MainActor.run(body: { SmartVPNDetector.shared.detectionResult }) {
            vpnActive = cachedResult.isVPNActive
            debugLog("🔍 [VPN Leak Test] Using cached VPN detection: \(vpnActive)")
        } else {
            // Fallback to async check if no cached result available
            // FIXED: Replaced blocking semaphore.wait with async continuation
            vpnActive = await isVPNActiveAsync()
            debugLog("🔍 [VPN Leak Test] No cached result, using async check: \(vpnActive)")
        }
        debugLog("🔍 [VPN Leak Test] VPN active: \(vpnActive)")

        // If no VPN, skip the leak test entirely - return immediately
        if !vpnActive {
            debugLog("🔍 [VPN Leak Test] ✅ No VPN active - cannot test for leaks (no VPN to leak from)")
            debugLog("🔍 [VPN Leak Test] Returning immediately...")

            let result = VPNLeakResult(
                realIP: nil,
                vpnIP: "N/A - No VPN Active",
                leaked: false,
                leakType: .noLeak,
                timestamp: Date()
            )

            debugLog("🔍 [VPN Leak Test] ✅ Returned successfully")
            return .success(result)
        }

        // VPN is active - check for leaks
        debugLog("🔍 [VPN Leak Test] VPN active, checking for leaks...")
        guard let ipifyURL = URL(string: "https://api.ipify.org?format=json"),
              let currentIP = try? await URLSession.shared.data(from: ipifyURL).0,
              let ipResponse = try? JSONDecoder().decode([String: String].self, from: currentIP),
              let publicIP = ipResponse["ip"] else {
            debugLog("🔍 [VPN Leak Test] ❌ Failed to fetch IP")
            return .failure(.timeout)
        }
        debugLog("🔍 [VPN Leak Test] Got public IP: \(publicIP)")

        // Get stored real IP
        let storedRealIP = UserDefaults.standard.string(forKey: "real_ip_no_vpn")
        debugLog("🔍 [VPN Leak Test] Stored real IP: \(storedRealIP ?? "none")")

        var leaked = false
        var leakType: VPNLeakType = .noLeak

        if let realIP = storedRealIP, realIP == publicIP {
            leaked = true
            leakType = .ipLeak
            debugLog("🔍 [VPN Leak Test] ⚠️ VPN LEAK DETECTED!")
        }

        let result = VPNLeakResult(
            realIP: storedRealIP,
            vpnIP: publicIP,
            leaked: leaked,
            leakType: leakType,
            timestamp: Date()
        )

        debugLog("🔍 [VPN Leak Test] ✅ Test complete! Leaked: \(leaked)")
        return .success(result)
    }

    // FIXED: Async VPN detection - non-blocking, timeout-safe
    // Replaced semaphore.wait() which could block actor threads
    private func isVPNActiveAsync() async -> Bool {
        do {
            return try await withTimeout(seconds: 0.5) {
                await withCheckedContinuation { continuation in
                    let monitor = NWPathMonitor()
                    let queue = DispatchQueue(label: "vpn-quick-check")

                    // Thread-safe completion tracking
                    final class CompletionState: @unchecked Sendable {
                        var completed = false
                        let lock = NSLock()
                        func complete() -> Bool {
                            lock.lock()
                            defer { lock.unlock() }
                            if completed { return false }
                            completed = true
                            return true
                        }
                    }
                    let state = CompletionState()

                    monitor.pathUpdateHandler = { path in
                        let hasVPN = path.availableInterfaces.contains { interface in
                            let name = interface.name.lowercased()
                            return name.contains("utun") ||
                                   name.contains("ppp") ||
                                   name.contains("ipsec") ||
                                   name.contains("tun") ||
                                   name.contains("tap")
                        }
                        if state.complete() {
                            monitor.cancel()
                            continuation.resume(returning: hasVPN)
                        }
                    }

                    monitor.start(queue: queue)
                }
            }
        } catch {
            // Timeout - assume no VPN
            return false
        }
    }

    private func fetchPublicIP() async throws -> String {
        debugLog("🔍 [fetchPublicIP] Fetching from api.ipify.org...")
        guard let url = URL(string: "https://api.ipify.org?format=json") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5  // 5 second timeout

        let (data, _) = try await URLSession.shared.data(for: request)
        debugLog("🔍 [fetchPublicIP] Got response data")

        struct IPResponse: Codable {
            let ip: String
        }

        let response = try JSONDecoder().decode(IPResponse.self, from: data)
        debugLog("🔍 [fetchPublicIP] Decoded IP: \(response.ip)")
        return response.ip
    }

    private func isVPNActive() async -> Bool {
        // Use Network framework to detect VPN interfaces (iOS-compatible)
        debugLog("🔍 [isVPNActive] Starting VPN detection...")
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "vpn-detection-security")
            // FIXED: Use thread-safe ContinuationState for Swift 6 compliance
            let safeContinuation = TimeoutContinuation(continuation)

            monitor.pathUpdateHandler = { path in
                debugLog("🔍 [isVPNActive] Path update handler called")

                let hasVPN = path.availableInterfaces.contains { interface in
                    let name = interface.name.lowercased()
                    return name.contains("utun") ||
                           name.contains("ppp") ||
                           name.contains("ipsec") ||
                           name.contains("tun") ||
                           name.contains("tap")
                }

                debugLog("🔍 [isVPNActive] VPN detected: \(hasVPN), resuming continuation")
                monitor.cancel()
                safeContinuation.resume(returning: hasVPN)
            }

            monitor.start(queue: queue)
            debugLog("🔍 [isVPNActive] Monitor started, setting 2s timeout")

            queue.asyncAfter(deadline: .now() + 2) {
                debugLog("🔍 [isVPNActive] Timeout fired")
                monitor.cancel()
                debugLog("🔍 [isVPNActive] Timeout: resuming with false")
                safeContinuation.resume(returning: false)
            }
        }
    }

}

// MARK: - Timeout Helper

func withTimeout<T>(seconds: Int, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            throw DiagnosticError.timeout
        }

        // FIXED: Safe unwrap instead of force unwrap
        guard let result = try await group.next() else {
            group.cancelAll()
            throw DiagnosticError.timeout
        }

        group.cancelAll()

        return result
    }
}
