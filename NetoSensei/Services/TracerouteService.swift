import Foundation

/// Retains the historical API name while exposing honest endpoint comparisons.
/// No intermediate hop identity or incremental latency is inferred.
@MainActor
final class TracerouteService: ObservableObject {
    static let shared = TracerouteService()
    @Published var isRunning = false
    @Published var currentHop = 0
    @Published var hops: [TracerouteHop] = []
    @Published var result: TracerouteResult?
    @Published var error: String?
    private init() {}

    func runTraceroute(to destination: String) async -> TracerouteResult {
        guard !isRunning else {
            return TracerouteResult(timestamp: Date(), destination: destination, hops: [], totalLatency: nil)
        }
        isRunning = true
        defer { isRunning = false; AppLoadTracker.shared.end("endpointChecks") }
        AppLoadTracker.shared.begin("endpointChecks")
        hops = []; result = nil; error = nil
        guard Self.validHostname(destination) else {
            error = "Enter a hostname, such as www.apple.com, without a URL or path."
            return TracerouteResult(timestamp: Date(), destination: destination, hops: [], totalLatency: nil)
        }
        if let gateway = DefaultRouteResolver.lanGateway()?.gateway {
            let seconds = await NetworkLatencyProbe.shared.measureHandshake(host: gateway, ports: [80, 443, 53], allowUDPFallback: false, timeout: 1)
            hops.append(TracerouteHop(hopNumber: 1, ipAddress: gateway, hostname: "Gateway · TCP handshake", latency: seconds.map { $0 * 1000 }))
        }
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 6
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var destinationResponse: Double?
        for host in Array(NSOrderedSet(array: ["www.apple.com", destination])) as? [String] ?? [destination] {
            guard !Task.isCancelled else { break }
            currentHop = hops.count + 1
            let response = await Self.responseTime(host: host, session: session)
            if host == destination { destinationResponse = response }
            hops.append(TracerouteHop(hopNumber: hops.count + 1, ipAddress: host, hostname: "HTTPS response · includes DNS/TLS/server time", latency: response))
        }
        let measured = TracerouteResult(timestamp: Date(), destination: destination, hops: hops, totalLatency: destinationResponse)
        result = measured
        return measured
    }

    func runPracticalTraceroute(vpnActive: Bool) async -> TracerouteResult {
        await runTraceroute(to: "www.apple.com")
    }

    nonisolated static func validHostname(_ input: String) -> Bool {
        guard !input.isEmpty, input.utf8.count <= 253, !input.hasPrefix("-"), !input.hasSuffix("-") else { return false }
        let labels = input.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-") &&
            label.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
        }
    }

    nonisolated static func responseTime(host: String, session: URLSession) async -> Double? {
        guard validHostname(host), let url = URL(string: "https://\(host)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let start = ProcessInfo.processInfo.systemUptime
        do {
            let (_, response) = try await session.data(for: request)
            guard response is HTTPURLResponse else { return nil }
            return (ProcessInfo.processInfo.systemUptime - start) * 1000
        } catch { return nil }
    }
}
