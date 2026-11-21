import Foundation

@MainActor
final class FullDiagnosticViewModel: ObservableObject {
    enum Check: String, CaseIterable, Identifiable {
        case connection = "Connection"
        case endpoints = "Endpoint responses"
        case dns = "DNS and resolvers"
        case security = "TLS, VPN and security"
        case speed = "Speed and responsiveness"
        case endpointSpeeds = "Endpoint speeds"
        case comparison = "Wi-Fi vs cellular"
        var id: Self { self }
    }

    enum Result {
        case connection(DiagnosticResult, NetworkVerdict?)
        case endpoints(TracerouteResult)
        case dns(DNSAnalysisResult, QuickDNSBenchmarkResult)
        case security(CombinedSecurityResult)
        case speed(SpeedTestResult)
        case endpointSpeeds(ThrottleAnalysis)
        case comparison(ComparisonResult)
        case unavailable(String)
    }

    @Published private(set) var results: [Check: Result] = [:]
    @Published private(set) var running: Set<Check> = []
    @Published private(set) var isRunning = false
    @Published private(set) var message: String?
    @Published private(set) var path: Date?
    @Published private(set) var checkedHost: String?

    private let connection = DiagnosticViewModel()
    private let security = CombinedSecurityCheckViewModel()
    private var operation: Task<Void, Never>?

    func run(host: String) {
        guard !isRunning else { return }
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard TracerouteService.validHostname(host) else {
            message = "Enter a hostname such as www.apple.com, without a URL or path."
            return
        }

        results = [:]
        running = [.connection, .endpoints, .dns, .security]
        isRunning = true
        message = nil
        let path = ExitPath.lastPathChange
        self.path = path
        checkedHost = host
        operation = Task { [weak self] in
            guard let self else { return }
            defer {
                self.running = []
                self.isRunning = false
                self.operation = nil
            }
            await self.runChecks(host: host, on: path)
        }
    }

    func cancel() {
        message = "Stopping checks…"
        operation?.cancel()
    }

    func report(status: NetworkStatus) -> String? {
        guard path == ExitPath.lastPathChange,
              case let .connection(diagnostic, verdict) = results[.connection] else { return nil }
        let speed: SpeedTestResult?
        if case .speed(let measurement) = results[.speed] { speed = measurement } else { speed = nil }
        return DiagnosticReportGenerator.shared.generateReport(
            diagnostic: diagnostic, speedTest: speed, vpnInfo: SmartVPNDetector.shared.detectionResult,
            verdict: verdict, networkStatus: status
        )
    }

    private func runChecks(host: String, on path: Date) async {
        AppLoadTracker.shared.begin("fullDiagnostic")
        defer { AppLoadTracker.shared.end("fullDiagnostic") }
        await withTaskGroup(of: (Check, Result).self) { group in
            group.addTask { @MainActor in
                await self.connection.runFullDiagnosticAndWait()
                guard let result = self.connection.result else {
                    return (.connection, .unavailable(self.connection.errorMessage ?? "Connection readings unavailable."))
                }
                return (.connection, .connection(result, self.connection.verdict))
            }
            group.addTask { @MainActor in
                let result = await TracerouteService.shared.runTraceroute(to: host)
                return (.endpoints, .endpoints(result))
            }
            group.addTask { @MainActor in
                let resolver = await DNSAnalyzer.shared.runFullAnalysis()
                let benchmark = await DNSBenchmarkService().benchmark()
                return (.dns, .dns(resolver, benchmark))
            }
            group.addTask { @MainActor in
                var hosts = CertificateInspector.defaultHosts
                if !hosts.contains(host) { hosts.append(host) }
                await self.security.runFullCheck(hosts: hosts, refreshVPN: false)
                guard let result = self.security.result else {
                    return (.security, .unavailable(self.security.error ?? "Security readings unavailable."))
                }
                return (.security, .security(result))
            }
            for await (check, result) in group {
                guard canContinue(on: path) else {
                    group.cancelAll()
                    break
                }
                finish(check, with: result)
            }
        }

        guard canContinue(on: path) else { return }
        running = [.speed]
        let speed = await SpeedTestEngine.shared.runSpeedTest(measureResponsiveness: true)
        guard canContinue(on: path) else { return }
        if let error = speed.testUnavailableReason {
            finish(.speed, with: .unavailable(error))
        } else {
            finish(.speed, with: .speed(speed))
        }

        // Throughput tests run separately so they don't load each other's path.
        running = [.endpointSpeeds]
        let endpoints = await ThrottleDetectionService().detectThrottling()
        guard canContinue(on: path) else { return }
        finish(.endpointSpeeds, with: .endpointSpeeds(endpoints))

        running = [.comparison]
        let comparison = await ConnectionComparator.shared.runComparison(currentSpeed: speed, reuseCurrentSpeed: true)
        guard canContinue(on: path) else { return }
        finish(.comparison, with: comparison.map(Result.comparison) ?? .unavailable("Connection comparison unavailable."))
        message = "All checks finished."
    }

    private func canContinue(on path: Date) -> Bool {
        if path != ExitPath.lastPathChange {
            results = [:]
            message = "Your connection changed. Run the check again to measure the current path."
            return false
        }
        if Task.isCancelled {
            message = "Check stopped. Finished readings are still shown."
            return false
        }
        return true
    }

    private func finish(_ check: Check, with result: Result) {
        results[check] = result
        running.remove(check)
    }
}
