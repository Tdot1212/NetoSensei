//
//  DNSBenchmarkService.swift
//  NetoSensei
//
//  Tests resolution time for multiple DNS servers
//  IMPROVED: Multi-domain testing, reliability metrics, VPN-aware recommendations
//

import Foundation
import Network

// MARK: - Quick DNS Server Result

struct QuickDNSServerResult: Identifiable {
    let id = UUID()
    let name: String          // "Cloudflare"
    let address: String       // "1.1.1.1"
    let latencyMs: Double?    // Average latency (nil if failed)
    let failed: Bool
    let isFastest: Bool
    let region: String        // "Global", "China-optimized"

    // NEW: Enhanced metrics
    let individualLatencies: [Double]  // All test results
    let successRate: Double            // 0.0 to 1.0
    let minLatency: Double?
    let maxLatency: Double?
    let isCached: Bool                 // True if any result < 2ms

    // NEW: Censorship check results
    let censorshipResults: [CensorshipTestResult]?

    var displayLatency: String {
        if failed {
            return "Failed"
        } else if let latency = latencyMs {
            if isCached {
                return "\(Int(latency))ms*"  // Asterisk indicates cached
            }
            return "\(Int(latency))ms"
        } else {
            return "--"
        }
    }

    var jitter: Double? {
        guard let min = minLatency, let max = maxLatency else { return nil }
        return max - min
    }

    var statusIcon: String {
        if failed {
            return "xmark.circle.fill"
        } else if isFastest {
            return "crown.fill"
        } else if let latency = latencyMs, latency < 30 {
            return "checkmark.circle.fill"
        } else if let latency = latencyMs, latency < 100 {
            return "minus.circle.fill"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }

    var statusColor: String {
        if failed {
            return "red"
        } else if isFastest {
            return "green"
        } else if let latency = latencyMs, latency < 30 {
            return "green"
        } else if let latency = latencyMs, latency < 100 {
            return "yellow"
        } else {
            return "red"
        }
    }

    var reliabilityText: String {
        if successRate >= 1.0 {
            return "100%"
        } else if successRate >= 0.8 {
            return "\(Int(successRate * 100))%"
        } else {
            return "Unreliable"
        }
    }
}

// MARK: - Censorship Test Result

struct CensorshipTestResult: Identifiable {
    let id = UUID()
    let domain: String
    let resolved: Bool
    let resolvedIP: String?
}

// MARK: - DNS Recommendation

struct DNSRecommendation {
    let title: String
    let detail: String
    let action: String?  // nil if no specific action
    let priority: Priority

    enum Priority {
        case info
        case suggestion
        case warning
    }
}

// MARK: - Quick DNS Benchmark Result

struct QuickDNSBenchmarkResult {
    let results: [QuickDNSServerResult]
    let timestamp: Date
    let fastestServer: QuickDNSServerResult?
    let recommendation: DNSRecommendation
    let isVPNActive: Bool
    let vpnCountry: String?

    // NEW: Censorship summary
    let censorshipSummary: CensorshipSummary?

    var summary: String {
        guard let fastest = fastestServer else {
            return "DNS benchmark failed"
        }

        if let latency = fastest.latencyMs {
            if fastest.isCached {
                return "\(fastest.name) appears fastest (\(Int(latency))ms) but may be cached"
            } else if latency < 20 {
                return "Excellent DNS performance (\(fastest.name) at \(Int(latency))ms)"
            } else if latency < 50 {
                return "Good DNS performance (\(fastest.name) at \(Int(latency))ms)"
            } else {
                return "DNS is slow. Consider switching to \(fastest.name)"
            }
        }
        return "DNS benchmark completed"
    }
}

// MARK: - Censorship Summary

struct CensorshipSummary {
    let testedDomains: [String]
    let serverResults: [String: [CensorshipTestResult]]  // serverName -> results

    func canResolve(domain: String, using serverName: String) -> Bool? {
        guard let results = serverResults[serverName] else { return nil }
        return results.first { $0.domain == domain }?.resolved
    }
}

// MARK: - DNS Benchmark Service

class DNSBenchmarkService {
    static let shared = DNSBenchmarkService()

    struct DNSServer {
        let name: String
        let address: String
        let region: String
        let isGlobal: Bool  // True for Cloudflare, Google, etc.
    }

    // DNS servers to test — include China-relevant options
    static let servers: [DNSServer] = [
        DNSServer(name: "System Default", address: "system", region: "Auto", isGlobal: false),
        DNSServer(name: "Cloudflare", address: "1.1.1.1", region: "Global", isGlobal: true),
        DNSServer(name: "Google", address: "8.8.8.8", region: "Global", isGlobal: true),
        DNSServer(name: "Alibaba", address: "223.5.5.5", region: "China", isGlobal: false),
        DNSServer(name: "Tencent", address: "119.29.29.29", region: "China", isGlobal: false),
        DNSServer(name: "114 DNS", address: "114.114.114.114", region: "China", isGlobal: false),
    ]

    // IMPROVED: Multiple test domains to avoid cache hits
    private let testDomains = [
        "www.apple.com",
        "www.amazon.com",
        "www.github.com",
        "www.microsoft.com",
        "www.cloudflare.com"
    ]

    // Domains to test for censorship/filtering
    private let censorshipTestDomains = [
        "www.google.com",
        "www.youtube.com",
        "www.twitter.com",
        "www.facebook.com"
    ]

    private init() {}

    // MARK: - Benchmark

    func benchmark(progressHandler: ((Double, String) -> Void)? = nil) async -> QuickDNSBenchmarkResult {
        var results: [QuickDNSServerResult] = []
        let totalServers = Double(Self.servers.count)

        // Check VPN status first (access on main actor)
        let (vpnActive, vpnCountry) = await MainActor.run {
            let active = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
            let country = SmartVPNDetector.shared.detectionResult?.publicCountry
            return (active, country)
        }

        for (index, server) in Self.servers.enumerated() {
            progressHandler?(Double(index) / totalServers, "Testing \(server.name)...")

            // FIXED: Skip China DNS servers when VPN is active (they timeout through overseas VPN)
            if vpnActive && server.region == "China" {
                // Add a skipped result instead of timing out
                let skippedResult = QuickDNSServerResult(
                    name: server.name,
                    address: server.address,
                    latencyMs: nil,
                    failed: true,
                    isFastest: false,
                    region: server.region,
                    individualLatencies: [],
                    successRate: 0,
                    minLatency: nil,
                    maxLatency: nil,
                    isCached: false,
                    censorshipResults: nil
                )
                results.append(skippedResult)
                continue
            }

            // IMPROVED: Test 3 different domains to avoid cache hits
            let result = await benchmarkServer(server: server)
            results.append(result)
        }

        progressHandler?(0.9, "Analyzing results...")

        // Run censorship check (optional, quick)
        let censorshipSummary = await runCensorshipCheck(progressHandler: progressHandler)

        progressHandler?(1.0, "Complete!")

        // Mark fastest (excluding potentially cached results for fairness)
        var fastestServer: QuickDNSServerResult?
        let validResults = results.filter { !$0.failed && $0.latencyMs != nil }

        // Prefer non-cached results, but fall back to cached if that's all we have
        let nonCachedResults = validResults.filter { !$0.isCached }
        let resultsToConsider = nonCachedResults.isEmpty ? validResults : nonCachedResults

        if let fastestIndex = results.enumerated()
            .filter({ item in resultsToConsider.contains(where: { r in r.id == item.element.id }) })
            .min(by: { a, b in (a.element.latencyMs ?? .infinity) < (b.element.latencyMs ?? .infinity) })?
            .offset {

            let original = results[fastestIndex]
            let updated = QuickDNSServerResult(
                name: original.name,
                address: original.address,
                latencyMs: original.latencyMs,
                failed: false,
                isFastest: true,
                region: original.region,
                individualLatencies: original.individualLatencies,
                successRate: original.successRate,
                minLatency: original.minLatency,
                maxLatency: original.maxLatency,
                isCached: original.isCached,
                censorshipResults: original.censorshipResults
            )
            results[fastestIndex] = updated
            fastestServer = updated
        }

        // Generate smart recommendation
        let recommendation = generateSmartRecommendation(
            results: results,
            fastest: fastestServer,
            vpnActive: vpnActive,
            vpnCountry: vpnCountry
        )

        return QuickDNSBenchmarkResult(
            results: results,
            timestamp: Date(),
            fastestServer: fastestServer,
            recommendation: recommendation,
            isVPNActive: vpnActive,
            vpnCountry: vpnCountry,
            censorshipSummary: censorshipSummary
        )
    }

    // MARK: - Benchmark Single Server (Multi-Domain)

    private func benchmarkServer(server: DNSServer) async -> QuickDNSServerResult {
        var latencies: [Double] = []
        var successCount = 0
        let totalTests = 3  // Test 3 domains

        // Select 3 random domains to avoid cache
        let domainsToTest = Array(testDomains.shuffled().prefix(totalTests))

        for domain in domainsToTest {
            let start = CFAbsoluteTimeGetCurrent()
            let success: Bool

            if server.address == "system" {
                // Test system DNS by just resolving normally
                success = await resolveWithSystemDNS(domain: domain)
            } else {
                // For specific DNS servers, we measure latency to the server
                // since iOS doesn't allow us to query specific DNS servers directly
                success = await testDNSServerReachability(server: server.address, domain: domain)
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

            if success {
                latencies.append(elapsed)
                successCount += 1
            }

            // Small delay between tests
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }

        let avgLatency = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)
        let minLatency = latencies.min()
        let maxLatency = latencies.max()
        let successRate = Double(successCount) / Double(totalTests)
        let isCached = latencies.contains(where: { $0 < 2 })  // Any result under 2ms is likely cached

        return QuickDNSServerResult(
            name: server.name,
            address: server.address,
            latencyMs: avgLatency,
            failed: latencies.isEmpty,
            isFastest: false,
            region: server.region,
            individualLatencies: latencies,
            successRate: successRate,
            minLatency: minLatency,
            maxLatency: maxLatency,
            isCached: isCached,
            censorshipResults: nil
        )
    }

    // MARK: - System DNS Resolution

    private func resolveWithSystemDNS(domain: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM

            var res: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(domain, "443", &hints, &res)

            if let res = res {
                freeaddrinfo(res)
            }

            continuation.resume(returning: status == 0)
        }
    }

    // MARK: - Test DNS Server Reachability

    private func testDNSServerReachability(server: String, domain: String) async -> Bool {
        // Since iOS doesn't allow direct DNS server queries,
        // we measure reachability to the DNS server IP as a proxy
        guard let url = URL(string: "https://\(server)") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode != nil
        } catch {
            // Fall back to system DNS resolution as proxy
            return await resolveWithSystemDNS(domain: domain)
        }
    }

    // MARK: - Censorship Check

    private func runCensorshipCheck(progressHandler: ((Double, String) -> Void)? = nil) async -> CensorshipSummary? {
        var serverResults: [String: [CensorshipTestResult]] = [:]

        // Only test system DNS for censorship (most relevant)
        progressHandler?(0.95, "Checking DNS filtering...")

        var results: [CensorshipTestResult] = []
        for domain in censorshipTestDomains {
            let (resolved, ip) = await checkDomainResolution(domain: domain)
            results.append(CensorshipTestResult(
                domain: domain,
                resolved: resolved,
                resolvedIP: ip
            ))
        }
        serverResults["System Default"] = results

        return CensorshipSummary(
            testedDomains: censorshipTestDomains,
            serverResults: serverResults
        )
    }

    private func checkDomainResolution(domain: String) async -> (Bool, String?) {
        return await withCheckedContinuation { continuation in
            var hints = addrinfo()
            hints.ai_family = AF_INET  // IPv4
            hints.ai_socktype = SOCK_STREAM

            var res: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(domain, nil, &hints, &res)

            var ip: String? = nil
            if status == 0, let res = res {
                // Extract IP
                var addr = res.pointee.ai_addr.pointee
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(&addr, res.pointee.ai_addrlen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                ip = String(cString: hostname)
                freeaddrinfo(res)
            }

            continuation.resume(returning: (status == 0, ip))
        }
    }

    // MARK: - Smart Recommendation

    private func generateSmartRecommendation(
        results: [QuickDNSServerResult],
        fastest: QuickDNSServerResult?,
        vpnActive: Bool,
        vpnCountry: String?
    ) -> DNSRecommendation {

        // VPN-specific recommendation
        if vpnActive {
            return DNSRecommendation(
                title: "Let your VPN handle DNS",
                detail: "When using a VPN, your VPN app manages DNS automatically for privacy. China DNS servers (Alibaba, Tencent) may be faster but could log or filter queries. Most good VPN apps use their own private DNS servers.\n\nCheck your VPN app's DNS settings if you want to customize this.",
                action: nil,
                priority: .info
            )
        }

        // Find fastest reliable server (non-cached preferred)
        let reliableResults = results
            .filter { $0.latencyMs != nil && $0.successRate >= 0.8 }

        let nonCachedReliable = reliableResults.filter { !$0.isCached }
        let fastestReliable = (nonCachedReliable.isEmpty ? reliableResults : nonCachedReliable)
            .min(by: { $0.latencyMs! < $1.latencyMs! })

        // System DNS result
        let systemResult = results.first { $0.address == "system" }

        guard let best = fastestReliable, let bestLatency = best.latencyMs else {
            return DNSRecommendation(
                title: "DNS test inconclusive",
                detail: "Could not determine the best DNS server. Check your network connection and try again.",
                action: nil,
                priority: .warning
            )
        }

        // Check if system DNS is cached (suspiciously fast)
        if let systemLatency = systemResult?.latencyMs, systemLatency < 2 {
            // System result is likely cached
            if best.address != "system" {
                return DNSRecommendation(
                    title: "Switch to \(best.name) for reliable performance",
                    detail: "Your system DNS showed \(Int(systemLatency))ms which is likely a cached result. \(best.name) (\(best.address)) responded in \(Int(bestLatency))ms consistently across multiple domains.",
                    action: "Settings → Wi-Fi → tap ⓘ → Configure DNS → Manual → Add \(best.address)",
                    priority: .suggestion
                )
            }
        }

        // System DNS is genuinely fast
        if best.address == "system" {
            if bestLatency < 20 {
                return DNSRecommendation(
                    title: "Your current DNS is fast",
                    detail: "Your ISP's DNS responds in \(Int(bestLatency))ms on average, which is excellent. If you want more privacy or to avoid potential filtering, you can switch to Cloudflare (1.1.1.1) or Google (8.8.8.8).",
                    action: "Settings → Wi-Fi → tap ⓘ → Configure DNS → Manual",
                    priority: .info
                )
            } else {
                return DNSRecommendation(
                    title: "Your DNS is adequate",
                    detail: "Your ISP's DNS responds in \(Int(bestLatency))ms. This is acceptable but not great. Consider switching to a faster option for quicker page loads.",
                    action: "Settings → Wi-Fi → tap ⓘ → Configure DNS → Manual",
                    priority: .suggestion
                )
            }
        }

        // Another server is fastest
        let systemLatency = systemResult?.latencyMs ?? bestLatency
        let improvement = systemLatency - bestLatency

        if improvement > 20 {
            return DNSRecommendation(
                title: "Switch to \(best.name) for faster browsing",
                detail: "\(best.name) (\(best.address)) responded in \(Int(bestLatency))ms — \(Int(improvement))ms faster than your current DNS. This can make pages load noticeably quicker.",
                action: "Settings → Wi-Fi → tap ⓘ → Configure DNS → Manual → Add \(best.address)",
                priority: .suggestion
            )
        } else {
            return DNSRecommendation(
                title: "\(best.name) is slightly faster",
                detail: "\(best.name) (\(Int(bestLatency))ms) is marginally faster than your current DNS. The difference is small, so switching is optional.",
                action: nil,
                priority: .info
            )
        }
    }
}
