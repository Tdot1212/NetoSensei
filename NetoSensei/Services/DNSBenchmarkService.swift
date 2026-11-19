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
        guard let fastestServer, let ms = fastestServer.latencyMs else { return "No unique reliable direct-resolver result" }
        return "Lowest sampled direct-query mean: \(fastestServer.name), \(String(format: "%.1f", ms)) ms"
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

final class DNSBenchmarkService {
    static let shared = DNSBenchmarkService()
    struct DNSServer: Sendable {
        let name: String
        let address: String
        let region: String
        let isGlobal: Bool
    }
    static let servers: [DNSServer] = [
        DNSServer(name: "System Default", address: "system", region: "Auto", isGlobal: false),
        DNSServer(name: "Cloudflare", address: "1.1.1.1", region: "Global", isGlobal: true),
        DNSServer(name: "Google", address: "8.8.8.8", region: "Global", isGlobal: true),
        DNSServer(name: "Alibaba", address: "223.5.5.5", region: "China", isGlobal: false),
        DNSServer(name: "Tencent", address: "119.29.29.29", region: "China", isGlobal: false),
        DNSServer(name: "114 DNS", address: "114.114.114.114", region: "China", isGlobal: false),
    ]


    struct Environment {
        var query: @Sendable (String, String) async -> DNSWireReply?
        var system: @Sendable (String) async -> SystemDNSReply?
        var vpn: @MainActor () -> (Bool, String?)
    }
    private let environment: Environment
    init(environment: Environment? = nil) {
        self.environment = environment ?? Environment(
            query: { server, domain in await DNSWireClient().query(server: server, domain: domain) },
            system: { domain in await SystemDNSResolver.resolve(domain) },
            vpn: { (SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false, SmartVPNDetector.shared.detectionResult?.publicCountry) })
    }

    func benchmark(progressHandler: ((Double, String) -> Void)? = nil) async -> QuickDNSBenchmarkResult {
        let (vpn, country) = await environment.vpn()
        var results: [QuickDNSServerResult] = []
        let domains = ["www.apple.com", "www.microsoft.com", "www.cloudflare.com"]
        for (index, server) in Self.servers.enumerated() {
            if Task.isCancelled { break }
            progressHandler?(Double(index)/Double(Self.servers.count), "Querying \(server.name)…")
            var samples: [Double] = []
            for domain in domains {
                if Task.isCancelled { break }
                if server.address == "system" {
                    if let reply = await environment.system(domain), reply.latencyMs.isFinite, reply.latencyMs >= 0 { samples.append(reply.latencyMs) }
                } else if let reply = await environment.query(server.address, domain), reply.resolved, reply.latencyMs.isFinite, reply.latencyMs >= 0 {
                    samples.append(reply.latencyMs)
                }
            }
            results.append(Self.result(server: server, samples: samples, total: domains.count, fastest: false))
        }
        // System API time includes local cache/OS work; do not rank it against
        // direct-wire resolver RTT or infer caching from a sub-2ms observation.
        let ranked = results.enumerated().filter { $0.element.address != "system" && $0.element.successRate == 1 && $0.element.latencyMs != nil }
        let minimum = ranked.compactMap { $0.element.latencyMs }.min()
        let tied = ranked.filter { $0.element.latencyMs == minimum }
        var fastest: QuickDNSServerResult?
        if tied.count == 1, let best = tied.first {
            let server = Self.servers.first { $0.address == best.element.address }!
            let marked = Self.result(server: server, samples: best.element.individualLatencies, total: domains.count, fastest: true)
            results[best.offset] = marked; fastest = marked
        }
        progressHandler?(1, "Complete")
        return QuickDNSBenchmarkResult(results: results, timestamp: Date(), fastestServer: fastest,
            recommendation: DNSRecommendation(title: fastest.map { "Lowest measured mean: \($0.name)" } ?? "No unique reliable resolver result",
                detail: "Direct entries time validated DNS replies to the listed address. System Default includes OS cache and resolver work and is not ranked with direct queries. A VPN or network policy may redirect DNS. These samples do not prove encryption, filtering, privacy, or faster internet throughput.",
                action: nil, priority: .info), isVPNActive: vpn, vpnCountry: country, censorshipSummary: nil)
    }

    static func result(server: DNSServer, samples: [Double], total: Int, fastest: Bool) -> QuickDNSServerResult {
        let valid = samples.filter { $0.isFinite && $0 >= 0 }
        return QuickDNSServerResult(name: server.name, address: server.address, latencyMs: MeasurementStatistics.mean(valid.map(Optional.some)),
            failed: valid.isEmpty, isFastest: fastest, region: server.region, individualLatencies: valid,
            successRate: total > 0 ? min(1, Double(valid.count)/Double(total)) : 0,
            minLatency: valid.min(), maxLatency: valid.max(), isCached: false, censorshipResults: nil)
    }
}
