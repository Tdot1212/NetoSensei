//
//  DNSBenchmark.swift
//  NetoSensei
//
//  DNS Benchmark - Test multiple DNS servers and recommend the fastest
//  Critical for users in China where DNS can be slow or hijacked
//

@preconcurrency import Darwin
import Foundation
import Network

// MARK: - DNS Server

struct DNSServer: Identifiable {
    let id = UUID()
    let name: String
    let primaryIP: String
    let secondaryIP: String?
    let provider: String
    let isSecure: Bool  // DoH/DoT support
    let region: DNSRegion
    let description: String

    enum DNSRegion: String {
        case global = "Global"
        case china = "China"
        case japan = "Japan"
        case hongkong = "Hong Kong"
        case usa = "USA"
        case europe = "Europe"
    }
}

// MARK: - DNS Benchmark Result

struct DNSBenchmarkResult: Identifiable {
    let id = UUID()
    let server: DNSServer
    let averageLatency: Double  // ms
    let minLatency: Double
    let maxLatency: Double
    let reliability: Double  // % of successful lookups
    let lookupTimes: [Double]
    let testDomain: String
    let timestamp: Date

    var rating: Rating {
        if reliability < 80 { return .unreliable }
        if averageLatency < 20 { return .excellent }
        if averageLatency < 50 { return .good }
        if averageLatency < 100 { return .fair }
        if averageLatency < 200 { return .slow }
        return .verySlow
    }

    enum Rating: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case slow = "Slow"
        case verySlow = "Very Slow"
        case unreliable = "Unreliable"

        var icon: String {
            switch self {
            case .excellent: return "bolt.fill"
            case .good: return "checkmark.circle.fill"
            case .fair: return "minus.circle.fill"
            case .slow: return "tortoise.fill"
            case .verySlow: return "exclamationmark.triangle.fill"
            case .unreliable: return "xmark.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "blue"
            case .fair: return "yellow"
            case .slow: return "orange"
            case .verySlow, .unreliable: return "red"
            }
        }
    }
}

// MARK: - DNS Benchmark Suite

struct DNSBenchmarkSuite {
    let timestamp: Date
    let results: [DNSBenchmarkResult]
    let recommended: DNSServer?
    let currentDNS: String?
    let recommendations: [String]

    var sortedBySpeed: [DNSBenchmarkResult] {
        results.sorted { $0.averageLatency < $1.averageLatency }
    }

    var fastestReliable: DNSBenchmarkResult? {
        results
            .filter { $0.reliability >= 90 }
            .sorted { $0.averageLatency < $1.averageLatency }
            .first
    }
}

// MARK: - DNS Benchmark Engine

actor DNSBenchmark {
    static let shared = DNSBenchmark()

    private init() {}

    // DNS servers to test
    private let dnsServers: [DNSServer] = [
        // Global providers
        DNSServer(
            name: "Cloudflare",
            primaryIP: "1.1.1.1",
            secondaryIP: "1.0.0.1",
            provider: "Cloudflare",
            isSecure: true,
            region: .global,
            description: "Fast, privacy-focused. Works well in most regions."
        ),
        DNSServer(
            name: "Google",
            primaryIP: "8.8.8.8",
            secondaryIP: "8.8.4.4",
            provider: "Google",
            isSecure: true,
            region: .global,
            description: "Reliable global DNS. May be blocked in some regions."
        ),
        DNSServer(
            name: "Quad9",
            primaryIP: "9.9.9.9",
            secondaryIP: "149.112.112.112",
            provider: "Quad9",
            isSecure: true,
            region: .global,
            description: "Privacy-focused with malware blocking."
        ),
        DNSServer(
            name: "OpenDNS",
            primaryIP: "208.67.222.222",
            secondaryIP: "208.67.220.220",
            provider: "Cisco",
            isSecure: true,
            region: .global,
            description: "Good performance with optional content filtering."
        ),

        // China-optimized
        DNSServer(
            name: "AliDNS",
            primaryIP: "223.5.5.5",
            secondaryIP: "223.6.6.6",
            provider: "Alibaba",
            isSecure: true,
            region: .china,
            description: "Best for users in mainland China."
        ),
        DNSServer(
            name: "Tencent DNS",
            primaryIP: "119.29.29.29",
            secondaryIP: "182.254.116.116",
            provider: "Tencent",
            isSecure: true,
            region: .china,
            description: "Good for WeChat, QQ, and Chinese services."
        ),
        DNSServer(
            name: "114DNS",
            primaryIP: "114.114.114.114",
            secondaryIP: "114.114.115.115",
            provider: "114DNS",
            isSecure: false,
            region: .china,
            description: "Popular in China. Fast but no encryption."
        ),
        DNSServer(
            name: "Baidu DNS",
            primaryIP: "180.76.76.76",
            secondaryIP: nil,
            provider: "Baidu",
            isSecure: false,
            region: .china,
            description: "Good for Baidu services."
        ),

        // Regional
        DNSServer(
            name: "Japan (IIJ)",
            primaryIP: "210.130.0.1",
            secondaryIP: nil,
            provider: "IIJ",
            isSecure: false,
            region: .japan,
            description: "Low latency for Japan-based users."
        ),
    ]

    // Test domains to use
    // FIXED: Use China-accessible domains that resolve everywhere
    // google.com and cloudflare.com may fail/be slow from China without VPN
    private let testDomains = [
        "www.apple.com",
        "www.baidu.com",
        "www.qq.com",
        "www.taobao.com"
    ]

    // MARK: - Run Full Benchmark

    func runBenchmark(iterations: Int = 5) async -> DNSBenchmarkSuite {
        var results: [DNSBenchmarkResult] = []

        let vpnActive = await MainActor.run {
            SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        }
        let isInChina = await MainActor.run {
            SmartVPNDetector.shared.detectionResult?.isLikelyInChina ?? false
        }

        // Sort servers: prioritize China DNS when in China, global otherwise
        let sortedServers: [DNSServer]
        if isInChina && !vpnActive {
            // China without VPN: test China DNS first (114, Ali, Tencent),
            // skip overseas DNS that would fail/timeout
            sortedServers = dnsServers.sorted { a, b in
                if a.region == .china && b.region != .china { return true }
                if a.region != .china && b.region == .china { return false }
                return false
            }
        } else {
            sortedServers = dnsServers
        }

        for server in sortedServers {
            // Skip China DNS servers when VPN is active (they timeout through overseas VPN)
            if vpnActive && server.region == .china {
                let skippedResult = DNSBenchmarkResult(
                    server: server,
                    averageLatency: 999.0,
                    minLatency: 999.0,
                    maxLatency: 999.0,
                    reliability: 0,
                    lookupTimes: [],
                    testDomain: "skipped (VPN active)",
                    timestamp: Date()
                )
                results.append(skippedResult)
                continue
            }

            // Skip overseas DNS when in China without VPN (they'll likely fail)
            if isInChina && !vpnActive && server.region == .global {
                let skippedResult = DNSBenchmarkResult(
                    server: server,
                    averageLatency: 999.0,
                    minLatency: 999.0,
                    maxLatency: 999.0,
                    reliability: 0,
                    lookupTimes: [],
                    testDomain: "skipped (overseas, no VPN)",
                    timestamp: Date()
                )
                results.append(skippedResult)
                continue
            }

            let result = await benchmarkDNS(server: server, iterations: iterations)
            results.append(result)
        }

        // Find recommended server
        let fastestReliable = results
            .filter { $0.reliability >= 90 }
            .sorted { $0.averageLatency < $1.averageLatency }
            .first

        // Generate recommendations
        let recommendations = generateRecommendations(results: results, recommended: fastestReliable)

        return DNSBenchmarkSuite(
            timestamp: Date(),
            results: results,
            recommended: fastestReliable?.server,
            currentDNS: getCurrentDNS(),
            recommendations: recommendations
        )
    }

    // MARK: - Benchmark Single DNS

    private func benchmarkDNS(server: DNSServer, iterations: Int) async -> DNSBenchmarkResult {
        var lookupTimes: [Double] = []
        var successCount = 0
        let testDomain = testDomains.randomElement() ?? "www.apple.com"

        for _ in 0..<iterations {
            let (success, latency) = await performDNSLookup(
                domain: testDomain,
                dnsServer: server.primaryIP
            )

            if success, let time = latency {
                lookupTimes.append(time)
                successCount += 1
            }

            // Small delay between tests
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        let avgLatency = lookupTimes.isEmpty ? 999.0 : lookupTimes.reduce(0, +) / Double(lookupTimes.count)
        let minLatency = lookupTimes.min() ?? 999.0
        let maxLatency = lookupTimes.max() ?? 999.0
        let reliability = Double(successCount) / Double(iterations) * 100

        return DNSBenchmarkResult(
            server: server,
            averageLatency: avgLatency,
            minLatency: minLatency,
            maxLatency: maxLatency,
            reliability: reliability,
            lookupTimes: lookupTimes,
            testDomain: testDomain,
            timestamp: Date()
        )
    }

    // MARK: - DNS Lookup
    // FIXED: Send actual DNS query to the specific DNS server via UDP port 53
    // Previously used getaddrinfo() which ALWAYS uses the system DNS, making all
    // servers appear to have the same latency.

    private func performDNSLookup(domain: String, dnsServer: String) async -> (Bool, Double?) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let start = Date()

                // Build a minimal DNS query packet for A record
                let queryPacket = Self.buildDNSQuery(domain: domain)

                // Create UDP socket
                let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard socketFD >= 0 else {
                    continuation.resume(returning: (false, nil))
                    return
                }

                // FIXED: 5-second timeout (China DNS can be slower)
                var tv = timeval(tv_sec: 5, tv_usec: 0)
                setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                // DNS server address
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = UInt16(53).bigEndian
                inet_pton(AF_INET, dnsServer, &addr.sin_addr)

                // Send query
                let sendResult = queryPacket.withUnsafeBytes { buf in
                    withUnsafePointer(to: &addr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            sendto(socketFD, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }

                guard sendResult > 0 else {
                    let err = String(cString: strerror(errno))
                    print("[DNS] Send to \(dnsServer) failed: \(err)")
                    close(socketFD)
                    continuation.resume(returning: (false, nil))
                    return
                }

                // Receive response
                var buffer = [UInt8](repeating: 0, count: 512)
                let recvResult = recv(socketFD, &buffer, buffer.count, 0)
                let savedErrno = errno
                close(socketFD)

                let latency = Date().timeIntervalSince(start) * 1000

                if recvResult > 0 {
                    continuation.resume(returning: (true, latency))
                } else {
                    let err = recvResult == 0 ? "connection closed" : String(cString: strerror(savedErrno))
                    print("[DNS] Recv from \(dnsServer) failed: \(err) (errno=\(savedErrno))")
                    continuation.resume(returning: (false, nil))
                }
            }
        }
    }

    /// Build a minimal DNS A-record query packet
    private static func buildDNSQuery(domain: String) -> Data {
        var packet = Data()

        // Transaction ID (random)
        let txID = UInt16.random(in: 0...UInt16.max)
        packet.append(UInt8(txID >> 8))
        packet.append(UInt8(txID & 0xFF))

        // Flags: standard query, recursion desired
        packet.append(0x01); packet.append(0x00)
        // Questions: 1
        packet.append(0x00); packet.append(0x01)
        // Answer/Authority/Additional RRs: 0
        packet.append(0x00); packet.append(0x00)
        packet.append(0x00); packet.append(0x00)
        packet.append(0x00); packet.append(0x00)

        // Query name (encoded labels)
        let labels = domain.split(separator: ".")
        for label in labels {
            packet.append(UInt8(label.count))
            packet.append(contentsOf: label.utf8)
        }
        packet.append(0x00) // Root label

        // Type: A (1)
        packet.append(0x00); packet.append(0x01)
        // Class: IN (1)
        packet.append(0x00); packet.append(0x01)

        return packet
    }

    // MARK: - Get Current DNS

    private func getCurrentDNS() -> String? {
        // On iOS, we can't easily get the configured DNS
        // Return nil and note this in the UI
        return nil
    }

    // MARK: - Generate Recommendations

    private func generateRecommendations(results: [DNSBenchmarkResult], recommended: DNSBenchmarkResult?) -> [String] {
        var recommendations: [String] = []

        guard let best = recommended else {
            recommendations.append("Unable to determine best DNS. All tested servers had reliability issues.")
            return recommendations
        }

        // Primary recommendation
        recommendations.append("Fastest reliable DNS: \(best.server.name) (\(best.server.primaryIP)) with \(Int(best.averageLatency))ms average latency.")

        // Check for China-optimized options
        let chinaResults = results.filter { $0.server.region == .china && $0.reliability >= 80 }
        let globalResults = results.filter { $0.server.region == .global && $0.reliability >= 80 }

        if let bestChina = chinaResults.sorted(by: { $0.averageLatency < $1.averageLatency }).first {
            if bestChina.averageLatency < (globalResults.first?.averageLatency ?? 999) {
                recommendations.append("For China: \(bestChina.server.name) (\(bestChina.server.primaryIP)) is faster than global DNS in your location.")
            }
        }

        // Security recommendation
        let secureOptions = results.filter { $0.server.isSecure && $0.reliability >= 90 }
        if let bestSecure = secureOptions.sorted(by: { $0.averageLatency < $1.averageLatency }).first {
            if bestSecure.server.name != best.server.name {
                recommendations.append("For privacy: \(bestSecure.server.name) supports encrypted DNS (DoH/DoT) with \(Int(bestSecure.averageLatency))ms latency.")
            }
        }

        // Unreliable servers warning
        let unreliable = results.filter { $0.reliability < 80 }
        if !unreliable.isEmpty {
            let names = unreliable.map { $0.server.name }.joined(separator: ", ")
            recommendations.append("Avoid: \(names) - unreliable from your location.")
        }

        // How to change DNS
        recommendations.append("To change DNS: Settings > Wi-Fi > [Your Network] > Configure DNS > Manual")

        return recommendations
    }

    // MARK: - Quick Test (Single Server)

    func quickTest(server: DNSServer) async -> DNSBenchmarkResult {
        await benchmarkDNS(server: server, iterations: 3)
    }
}
