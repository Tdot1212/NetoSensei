import Foundation

@MainActor
enum ConnectionInvestigationRunner {
    nonisolated static let defaultHost = "www.apple.com"
    private static let speedServer = SpeedTestServerSelection.cloudflare

    nonisolated static func validHost(_ host: String) -> Bool {
        TracerouteService.validHostname(host) && host.contains(".") && host.last?.isLetter == true
    }

    static func run(
        topic: InvestigationTopic,
        host: String,
        progress: (String) -> Void
    ) async throws -> InvestigationSample {
        let started = ExitPath.lastPathChange
        let initial = route()
        let target = topic.usesHostname ? host : defaultHost
        guard validHost(target) else { throw InvalidHostname() }
        let reference = target == "www.cloudflare.com" ? defaultHost : "www.cloudflare.com"
        var readings: [InvestigationMetric: InvestigationReading] = [:]
        var observedIPv6: String?
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        switch topic {
        case .wifi, .connection, .vpn:
            progress("Comparing two websites…")
            async let site = website(target, session: session)
            async let control = website(reference, session: session)
            if topic == .wifi, initial.interface == "WiFi" {
                let gateway = await NetworkMonitorService.shared.measureGatewayReferenceRTT()
                readings[.router] = InvestigationReading(label: "Router TCP response",
                    detail: gateway.map { String(format: "%.0f ms", $0) } ?? "No timing",
                    samples: gateway.map { [$0] } ?? [])
            }
            if topic == .connection {
                let reply = await SystemDNSResolver.resolve(target)
                readings[.lookup] = InvestigationReading(label: "System lookup for \(target)",
                    detail: reply.map { String(format: "Resolved in %.0f ms", $0.latencyMs) } ?? "No address returned",
                    outcome: reply != nil)
            }
            (readings[.site], readings[.reference]) = await (site, control)
            if topic == .vpn {
                progress("Checking public IPv6 and the current exit…")
                _ = await ExitPath.resolveFresh(timeoutSeconds: 6)
                try checkPath(started)
                let address = await PublicIPv6Probe.measure()
                observedIPv6 = address
                readings[.ipv6] = InvestigationReading(label: "IPv6-only request",
                    detail: address == nil ? "No public IPv6 sample" : "Public IPv6 returned")
            }
        case .speed:
            guard !AppLoadTracker.shared.isActive else { throw OtherCheckRunning() }
            AppLoadTracker.shared.begin("guidedDownload")
            defer { AppLoadTracker.shared.end("guidedDownload") }
            var single: [Double] = []
            var parallel: [Double] = []
            for round in 1...3 {
                for requests in round.isMultiple(of: 2) ? [4, 1] : [1, 4] {
                    try checkPath(started)
                    progress("Trial \(round) of 3 · \(requests == 1 ? "one request" : "four simultaneous requests")")
                    if let sample = await download(requests: requests, session: session) {
                        if requests == 1 { single.append(sample) } else { parallel.append(sample) }
                    }
                }
            }
            readings[.single] = downloadReading("One HTTPS request", samples: single)
            readings[.parallel] = downloadReading("Four simultaneous HTTPS requests", samples: parallel)
        case .privacy:
            progress("Checking encrypted DNS replies…")
            let result = await DNSEncryptionChecker.shared.checkDNSEncryption()
            readings[.doh] = encryptedReading("DNS over HTTPS", passed: result.dohReachable)
            readings[.dot] = encryptedReading("DNS over TLS", passed: result.dotReachable)
        case .security:
            progress("Checking iOS certificate trust…")
            let certificates = await CertificateInspector.shared.inspectCertificates(hosts: [target, reference])
            for certificate in certificates {
                let outcome: Bool? = certificate.severity == .unavailable ? nil : certificate.severity != .critical
                readings[certificate.hostname == target ? .certificate : .referenceCertificate] =
                    InvestigationReading(label: certificate.hostname, detail: certificate.summary, outcome: outcome)
            }
        }

        try checkPath(started)
        let status = route()
        if topic == .vpn {
            readings[.exit] = InvestigationReading(label: "Public VPN exit",
                detail: status.exit == nil ? "Fresh exit unavailable" : "Public exit observed")
        }
        return InvestigationSample(route: status, at: Date(), readings: readings, ipv6: observedIPv6)
    }

    private static func route() -> InvestigationRoute {
        let network = NetworkMonitorService.shared.currentStatus
        let path = ExitPath.lastPathChange
        let detector = SmartVPNDetector.shared.detectionResult
        let fresh = detector.flatMap { !$0.isStaleData && $0.timestamp >= path ? $0 : nil }
        return InvestigationRoute(generation: path, interface: network.connectionType?.displayName,
            wifi: network.wifi.ssid ?? network.wifi.bssid,
            vpn: fresh?.vpnState ?? network.vpn.vpnState, exit: fresh?.publicIP)
    }

    private static func checkPath(_ expected: Date) throws {
        try Task.checkCancellation()
        guard expected == ExitPath.lastPathChange else { throw PathChanged() }
    }

    private struct PathChanged: LocalizedError {
        var errorDescription: String? { "The connection changed during the test. Start this run again on a stable connection." }
    }

    private struct InvalidHostname: LocalizedError {
        var errorDescription: String? { "Enter a hostname such as www.apple.com, without a URL or path." }
    }

    private struct OtherCheckRunning: LocalizedError {
        var errorDescription: String? { "Another network check is running. When it finishes, run this test on its own." }
    }

    private static func website(_ host: String, session: URLSession) async -> InvestigationReading {
        let url = URL(string: "https://\(host)/")!
        var samples: [Double] = []
        var responses: [String] = []
        for _ in 0..<2 {
            if Task.isCancelled { break }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            let start = ProcessInfo.processInfo.systemUptime
            if let (_, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse, http.url?.scheme == "https" {
                responses.append("HTTP \(http.statusCode)")
                if (200..<400).contains(http.statusCode) {
                    samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                }
            } else {
                responses.append("No HTTPS response")
            }
        }
        let codes = responses.joined(separator: " · ")
        let result = MeasurementStatistics.median(samples).map { String(format: "%@ · %.0f ms median", codes, $0) } ?? codes
        return InvestigationReading(label: "\(host) · HTTPS headers", detail: result,
            samples: samples.count == 2 ? samples : [],
            outcome: samples.count == 2 ? true : samples.isEmpty ? false : nil)
    }

    private static func download(requests: Int, session: URLSession) async -> Double? {
        let bytesPerRequest = 4_000_000 / requests
        guard let url = speedServer.downloadURL(bytes: bytesPerRequest) else { return nil }
        let start = ProcessInfo.processInfo.systemUptime
        let completed = await withTaskGroup(of: Int?.self, returning: [Int].self) { group in
            for _ in 0..<requests {
                group.addTask { await transfer(url: url, bytes: bytesPerRequest, session: session) }
            }
            var results: [Int] = []
            for await count in group {
                if let count { results.append(count) } else { group.cancelAll(); break }
            }
            return results
        }
        guard completed.count == requests else { return nil }
        return MeasurementStatistics.throughputMbps(bytes: completed.reduce(0, +),
            duration: ProcessInfo.processInfo.systemUptime - start)
    }

    private nonisolated static func transfer(url: URL, bytes: Int, session: URLSession) async -> Int? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "run", value: UUID().uuidString)]
        guard let target = components.url else { return nil }
        var request = URLRequest(url: target)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url?.scheme == "https", http.url?.host == url.host,
              http.value(forHTTPHeaderField: "Content-Encoding").map({ $0.lowercased() == "identity" }) ?? true,
              !(http.mimeType?.lowercased().hasPrefix("text/") ?? false), data.count == bytes else { return nil }
        return data.count
    }

    private static func downloadReading(_ label: String, samples: [Double]) -> InvestigationReading {
        let count = "\(samples.count) of 3 completed"
        var detail = MeasurementStatistics.median(samples).map { String(format: "%.1f Mbps median · %@", $0, count) } ?? count
        if samples.count >= 2, let low = samples.min(), let high = samples.max() {
            detail += String(format: " · %.1f–%.1f Mbps", low, high)
        }
        return InvestigationReading(label: label, detail: detail, samples: samples.count >= 2 ? samples : [],
            outcome: samples.count == 3 ? true : samples.isEmpty ? false : nil)
    }

    private static func encryptedReading(_ label: String, passed: Bool) -> InvestigationReading {
        InvestigationReading(label: label, detail: passed ? "Validated reply" : "No validated reply", outcome: passed)
    }
}
