//
//  ConnectionComparator.swift
//  NetoSensei
//
//  Compares Wi-Fi and Cellular performance side-by-side.
//  Measures download/upload speed, latency, jitter, and provides
//  use-case specific recommendations.
//

import Foundation
import Network
import CoreTelephony

// MARK: - Data Models

struct ConnectionTestResult: Identifiable {
    let id = UUID()
    let connectionType: ConnectionType
    let downloadSpeedMbps: Double?
    let uploadSpeedMbps: Double?
    let latencyMs: Double?
    let jitterMs: Double?
    let packetLoss: Double?
    let timestamp: Date
    let error: String?

    enum ConnectionType: String {
        case wifi = "Wi-Fi"
        case cellular = "Cellular"

        var icon: String {
            switch self {
            case .wifi: return "wifi"
            case .cellular: return "antenna.radiowaves.left.and.right"
            }
        }
    }

    var isSuccessful: Bool {
        error == nil && downloadSpeedMbps != nil
    }

    var overallScore: Double {
        guard let download = downloadSpeedMbps,
              let latency = latencyMs else { return 0 }

        let downloadScore = min(download / 100.0 * 100, 100)
        let uploadScore = min((uploadSpeedMbps ?? 0) / 50.0 * 100, 100)
        let latencyScore = max(0, 100 - latency)

        return (downloadScore * 0.5) + (uploadScore * 0.2) + (latencyScore * 0.3)
    }

    var qualityRating: QualityRating {
        // FIX (Issue 2): Recalibrated for modern bandwidth norms. The previous
        // ladder labeled 28 Mbps as "Poor", which is wrong — 25 Mbps is
        // Netflix's recommended 4K minimum. Latency is no longer required for
        // the rating (it was double-gating: a great connection with 80ms RTT
        // would drop to "Fair" even with 100 Mbps download).
        //
        // Tiers (general internet quality):
        //   > 100 Mbps  → Excellent
        //   25-100 Mbps → Good (4K streaming, video calls)
        //   10-25  Mbps → Fair (basic streaming, video calls)
        //   3-10   Mbps → Poor (struggles with streaming)
        //   < 3    Mbps → Very Poor (basic browsing only)
        guard isSuccessful, let download = downloadSpeedMbps else { return .unavailable }

        if download >= 100 { return .excellent }
        if download >= 25 { return .good }
        if download >= 10 { return .fair }
        if download >= 3 { return .poor }
        return .veryPoor
    }

    enum QualityRating: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case veryPoor = "Very Poor"
        case unavailable = "Unavailable"

        var icon: String {
            switch self {
            case .excellent: return "star.fill"
            case .good: return "hand.thumbsup.fill"
            case .fair: return "hand.thumbsup"
            case .poor: return "hand.thumbsdown"
            case .veryPoor: return "hand.thumbsdown.fill"
            case .unavailable: return "xmark.circle"
            }
        }
    }
}

struct ComparisonResult {
    let wifiResult: ConnectionTestResult
    let cellularResult: ConnectionTestResult
    let winner: ConnectionTestResult.ConnectionType?
    let recommendation: Recommendation
    let useCases: [UseCase]
    let timestamp: Date

    struct Recommendation {
        let title: String
        let description: String
        let suggestedConnection: ConnectionTestResult.ConnectionType?
    }

    struct UseCase: Identifiable {
        let id = UUID()
        let activity: String
        let icon: String
        let recommended: ConnectionTestResult.ConnectionType
        let reason: String
    }
}

struct CellularInfo {
    let carrierName: String?
    let radioTechnology: String?

    var technologyIcon: String {
        guard let tech = radioTechnology?.uppercased() else { return "antenna.radiowaves.left.and.right" }
        if tech.contains("5G") { return "5g" }
        if tech.contains("LTE") || tech.contains("4G") { return "4g" }
        if tech.contains("3G") { return "3g" }
        return "antenna.radiowaves.left.and.right"
    }
}

// MARK: - Connection Comparator Service

@MainActor
class ConnectionComparator: ObservableObject {
    static let shared = ConnectionComparator()

    @Published var isRunning = false
    @Published var currentTest: ConnectionTestResult.ConnectionType?
    @Published var progress: Double = 0
    @Published var wifiResult: ConnectionTestResult?
    @Published var cellularResult: ConnectionTestResult?
    @Published var comparisonResult: ComparisonResult?
    @Published var error: String?
    @Published var cellularInfo: CellularInfo?

    // FIX (Issue 1): use the SAME endpoints/sizes as SpeedTestEngine so the
    // Wi-Fi number here matches what the main Speed Test reports. The previous
    // 10MB-only test under-measured fast connections (122 Mbps showed as 28).
    private let primaryDownloadURL = "https://speed.cloudflare.com/__down?bytes=25000000"
    private let fallbackDownloadURL = "https://speed.cloudflare.com/__down?bytes=10000000"
    private let uploadTestURL = "https://speed.cloudflare.com/__up"
    private let latencyTestHosts = ["1.1.1.1", "8.8.8.8", "www.apple.com"]

    /// FIX (Issue 6): special error string the view checks for, to render the
    /// "manual Wi-Fi toggle" instructions instead of a meaningless "Unavailable".
    /// `nonisolated` so the cellular test (which runs off the main actor) can
    /// reference it without crossing the isolation boundary.
    nonisolated static let manualToggleError = "MANUAL_TOGGLE_REQUIRED"

    private init() {
        updateCellularInfo()
    }

    // MARK: - Run Comparison

    func runComparison() async -> ComparisonResult? {
        return await BackgroundTaskManager.shared.runInBackground(
            id: "speedComparison",
            name: "Speed Test",
            operation: {
                return await self.performComparison()
            },
            resultFormatter: { result in
                guard let r = result else { return "Failed" }
                let download = r.wifiResult.downloadSpeedMbps ?? 0
                return "Download: \(String(format: "%.1f", download)) Mbps"
            }
        )
    }

    private func performComparison() async -> ComparisonResult? {
        isRunning = true
        progress = 0
        error = nil
        wifiResult = nil
        cellularResult = nil
        comparisonResult = nil

        // FIX (Issue 1/6): Detect both interfaces AND which is primary so we
        // can decide whether cellular forcing is feasible.
        let interfaces = await detectInterfaces()

        // Test Wi-Fi
        if interfaces.wifi {
            currentTest = .wifi
            progress = 0.1
            wifiResult = await testWiFiConnection()
            progress = 0.45
        } else {
            wifiResult = unavailableResult(type: .wifi)
        }

        // Test Cellular
        if interfaces.cellular {
            currentTest = .cellular
            progress = 0.5
            cellularResult = await testCellularConnection(wifiIsPrimary: interfaces.wifiIsPrimary)
            progress = 0.9
        } else {
            cellularResult = unavailableResult(type: .cellular)
        }

        guard let wifi = wifiResult, let cellular = cellularResult else {
            isRunning = false
            return nil
        }

        let comparison = generateComparison(wifi: wifi, cellular: cellular)
        comparisonResult = comparison

        progress = 1.0
        currentTest = nil
        isRunning = false

        return comparison
    }

    // MARK: - Detect Interfaces

    /// FIX (Issue 6): Detects WiFi/cellular availability AND which is primary.
    /// `wifiIsPrimary` matters because URLSession routes through the primary
    /// path and cannot be forced to a non-primary interface — so when WiFi is
    /// primary and cellular is also up, the cellular test must surface manual
    /// instructions instead of running URLSession against cellular (which would
    /// silently use WiFi and report meaningless numbers).
    private nonisolated func detectInterfaces() async -> (wifi: Bool, cellular: Bool, wifiIsPrimary: Bool) {
        // Check the primary path on a generic monitor.
        let primary = await primaryPath()
        // Check cellular reachability via a cellular-required monitor.
        let cellularReachable = await pathSatisfied(requiring: .cellular)
        // Check wifi reachability via a wifi-required monitor.
        let wifiReachable = await pathSatisfied(requiring: .wifi)

        let wifiIsPrimary = primary?.usesInterfaceType(.wifi) ?? false
        return (wifiReachable, cellularReachable, wifiIsPrimary)
    }

    private nonisolated func primaryPath() async -> NWPath? {
        await withCheckedContinuation { (continuation: CheckedContinuation<NWPath?, Never>) in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "connection.check.primary")
            let flag = OnceFlag()
            monitor.pathUpdateHandler = { path in
                if flag.claim() {
                    monitor.cancel()
                    continuation.resume(returning: path)
                }
            }
            monitor.start(queue: queue)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if flag.claim() {
                    monitor.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private nonisolated func pathSatisfied(requiring interface: NWInterface.InterfaceType) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let monitor = NWPathMonitor(requiredInterfaceType: interface)
            let queue = DispatchQueue(label: "connection.check.\(interface)")
            let flag = OnceFlag()
            monitor.pathUpdateHandler = { path in
                if flag.claim() {
                    monitor.cancel()
                    continuation.resume(returning: path.status == .satisfied)
                }
            }
            monitor.start(queue: queue)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if flag.claim() {
                    monitor.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func unavailableResult(type: ConnectionTestResult.ConnectionType) -> ConnectionTestResult {
        ConnectionTestResult(
            connectionType: type,
            downloadSpeedMbps: nil,
            uploadSpeedMbps: nil,
            latencyMs: nil,
            jitterMs: nil,
            packetLoss: nil,
            timestamp: Date(),
            error: "\(type.rawValue) not available"
        )
    }

    // MARK: - Test WiFi (URLSession with cellular blocked)

    /// FIX (Issue 1): WiFi test now uses the SAME methodology as the main
    /// Speed Test (SpeedTestEngine): 25MB Cloudflare endpoint, URLSession
    /// configured to block cellular fallback. Eliminates the "28 Mbps vs
    /// 122 Mbps" discrepancy between this tool and the main Speed Test.
    private nonisolated func testWiFiConnection() async -> ConnectionTestResult {
        let session = wifiOnlySession()

        async let latency = measureLatency(session: session)
        async let jitter = measureJitter(session: session)
        async let downloadSpeed = measureDownloadSpeed(session: session)
        async let uploadSpeed = measureUploadSpeed(session: session)

        let (lat, jit, dl, ul) = await (latency, jitter, downloadSpeed, uploadSpeed)

        return ConnectionTestResult(
            connectionType: .wifi,
            downloadSpeedMbps: dl,
            uploadSpeedMbps: ul,
            latencyMs: lat,
            jitterMs: jit,
            packetLoss: nil,
            timestamp: Date(),
            error: nil
        )
    }

    // MARK: - Test Cellular (NWConnection-based forcing or fallback message)

    /// FIX (Issue 6): URLSession cannot be reliably forced onto a non-primary
    /// interface. Strategy:
    ///   1. Probe `NWConnection` with `requiredInterfaceType = .cellular`. If
    ///      it does not reach `.ready` within 5s (state goes `.failed` /
    ///      `.waiting`), surface the manual-toggle instructions.
    ///   2. If WiFi is the primary path, URLSession will silently use WiFi and
    ///      give meaningless numbers — surface manual-toggle instructions even
    ///      when the cellular probe succeeds.
    ///   3. Only when WiFi is OFF (cellular IS the primary path) do we run the
    ///      same URLSession-based test as WiFi, against cellular.
    private nonisolated func testCellularConnection(wifiIsPrimary: Bool) async -> ConnectionTestResult {
        let cellularProbeOK = await probeCellularReachable(timeout: 5.0)
        guard cellularProbeOK else {
            return ConnectionTestResult(
                connectionType: .cellular,
                downloadSpeedMbps: nil,
                uploadSpeedMbps: nil,
                latencyMs: nil,
                jitterMs: nil,
                packetLoss: nil,
                timestamp: Date(),
                error: Self.manualToggleError
            )
        }

        // Cellular is reachable. But if WiFi is primary, URLSession will use
        // WiFi — running the test would mislabel WiFi numbers as cellular.
        if wifiIsPrimary {
            return ConnectionTestResult(
                connectionType: .cellular,
                downloadSpeedMbps: nil,
                uploadSpeedMbps: nil,
                latencyMs: nil,
                jitterMs: nil,
                packetLoss: nil,
                timestamp: Date(),
                error: Self.manualToggleError
            )
        }

        // WiFi is off — cellular is the only available interface, so URLSession
        // is implicitly using cellular. Run the standard test.
        let session = URLSession(configuration: .ephemeral)
        async let latency = measureLatency(session: session)
        async let jitter = measureJitter(session: session)
        async let downloadSpeed = measureDownloadSpeed(session: session)
        async let uploadSpeed = measureUploadSpeed(session: session)

        let (lat, jit, dl, ul) = await (latency, jitter, downloadSpeed, uploadSpeed)

        return ConnectionTestResult(
            connectionType: .cellular,
            downloadSpeedMbps: dl,
            uploadSpeedMbps: ul,
            latencyMs: lat,
            jitterMs: jit,
            packetLoss: nil,
            timestamp: Date(),
            error: nil
        )
    }

    /// URLSession that refuses cellular fallback (forces WiFi if WiFi is up).
    private nonisolated func wifiOnlySession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.allowsCellularAccess = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    /// Tries to open a TCP connection to `1.1.1.1:443` constrained to the
    /// cellular interface. Returns `true` if it reaches `.ready` within
    /// `timeout`; otherwise `false` (state .failed / .waiting / timeout).
    private nonisolated func probeCellularReachable(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .cellular
            let endpoint = NWEndpoint.hostPort(host: "1.1.1.1", port: 443)
            let connection = NWConnection(to: endpoint, using: parameters)
            let flag = OnceFlag()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if flag.claim() {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    if flag.claim() {
                        continuation.resume(returning: false)
                    }
                case .waiting:
                    // .waiting means we can't establish on the requested
                    // interface — treat as unavailable per the user's spec.
                    if flag.claim() {
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if flag.claim() {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Latency

    private nonisolated func measureLatency(session: URLSession) async -> Double? {
        var latencies: [Double] = []

        for host in latencyTestHosts {
            if let ms = await pingHost(host) {
                latencies.append(ms)
            }
        }

        guard !latencies.isEmpty else { return nil }
        return latencies.sorted()[latencies.count / 2]
    }

    /// Thread-safe once-guard for NWConnection callbacks.
    private final class OnceFlag: @unchecked Sendable {
        private var _done = false
        private let lock = NSLock()
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if _done { return false }
            _done = true
            return true
        }
    }

    private nonisolated func pingHost(_ host: String) async -> Double? {
        let start = CFAbsoluteTimeGetCurrent()

        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: 443
            )
            let connection = NWConnection(to: endpoint, using: .tcp)
            let flag = OnceFlag()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if flag.claim() {
                        let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
                        connection.cancel()
                        continuation.resume(returning: latency)
                    }
                case .failed, .cancelled:
                    if flag.claim() {
                        continuation.resume(returning: nil)
                    }
                case .waiting:
                    if flag.claim() {
                        connection.cancel()
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if flag.claim() {
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Jitter

    private nonisolated func measureJitter(session: URLSession) async -> Double? {
        var latencies: [Double] = []

        for _ in 0..<5 {
            if let ms = await pingHost("1.1.1.1") {
                latencies.append(ms)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard latencies.count >= 3 else { return nil }

        let mean = latencies.reduce(0, +) / Double(latencies.count)
        let variance = latencies.reduce(0) { $0 + pow($1 - mean, 2) } / Double(latencies.count)
        return sqrt(variance)
    }

    // MARK: - Download Speed

    /// FIX (Issue 1): SAME methodology as SpeedTestEngine — 25 MB primary,
    /// 10 MB fallback. Smaller payloads were under-measuring fast connections
    /// (TCP slow-start dominated).
    private nonisolated func measureDownloadSpeed(session: URLSession) async -> Double? {
        for urlString in [primaryDownloadURL, fallbackDownloadURL] {
            guard let url = URL(string: urlString) else { continue }
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let (data, response) = try await session.data(from: url)
                let duration = CFAbsoluteTimeGetCurrent() - start

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      duration > 0,
                      data.count > 1_000_000 else { continue }

                let megabits = Double(data.count) * 8 / 1_000_000
                return megabits / duration
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - Upload Speed

    /// FIX (Issue 1): 10 MB upload to match SpeedTestEngine and provide a
    /// reliable measurement on fast uplinks.
    private nonisolated func measureUploadSpeed(session: URLSession) async -> Double? {
        guard let url = URL(string: uploadTestURL) else { return nil }

        let testData = Data(repeating: 0, count: 10_000_000)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = testData
        request.timeoutInterval = 30

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (_, response) = try await session.data(for: request)
            let duration = CFAbsoluteTimeGetCurrent() - start

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  duration > 0 else { return nil }

            let megabits = Double(testData.count) * 8 / 1_000_000
            return megabits / duration
        } catch {
            return nil
        }
    }

    // MARK: - Generate Comparison

    private func generateComparison(wifi: ConnectionTestResult, cellular: ConnectionTestResult) -> ComparisonResult {
        var winner: ConnectionTestResult.ConnectionType?

        if wifi.isSuccessful && cellular.isSuccessful {
            winner = wifi.overallScore > cellular.overallScore ? .wifi : .cellular
        } else if wifi.isSuccessful {
            winner = .wifi
        } else if cellular.isSuccessful {
            winner = .cellular
        }

        let useCases = generateUseCases(wifi: wifi, cellular: cellular)
        let recommendation = generateRecommendation(wifi: wifi, cellular: cellular, winner: winner)

        return ComparisonResult(
            wifiResult: wifi,
            cellularResult: cellular,
            winner: winner,
            recommendation: recommendation,
            useCases: useCases,
            timestamp: Date()
        )
    }

    private func generateUseCases(wifi: ConnectionTestResult, cellular: ConnectionTestResult) -> [ComparisonResult.UseCase] {
        guard wifi.isSuccessful || cellular.isSuccessful else { return [] }

        return [
            ComparisonResult.UseCase(
                activity: "Video Calls",
                icon: "video.fill",
                recommended: bestFor(activity: "video", wifi: wifi, cellular: cellular),
                reason: "Needs low latency and jitter"
            ),
            ComparisonResult.UseCase(
                activity: "Streaming",
                icon: "play.tv.fill",
                recommended: bestFor(activity: "streaming", wifi: wifi, cellular: cellular),
                reason: "Needs high download speed"
            ),
            ComparisonResult.UseCase(
                activity: "Large Downloads",
                icon: "arrow.down.circle.fill",
                recommended: bestFor(activity: "download", wifi: wifi, cellular: cellular),
                reason: "Speed matters, Wi-Fi saves data"
            ),
            ComparisonResult.UseCase(
                activity: "Web Browsing",
                icon: "safari.fill",
                recommended: bestFor(activity: "browsing", wifi: wifi, cellular: cellular),
                reason: "Latency is most important"
            ),
        ]
    }

    private func bestFor(
        activity: String,
        wifi: ConnectionTestResult,
        cellular: ConnectionTestResult
    ) -> ConnectionTestResult.ConnectionType {
        guard wifi.isSuccessful && cellular.isSuccessful else {
            return wifi.isSuccessful ? .wifi : .cellular
        }

        switch activity {
        case "video":
            let wifiScore = (wifi.latencyMs ?? 100) + (wifi.jitterMs ?? 50) * 2
            let cellScore = (cellular.latencyMs ?? 100) + (cellular.jitterMs ?? 50) * 2
            return wifiScore < cellScore ? .wifi : .cellular

        case "streaming":
            return (wifi.downloadSpeedMbps ?? 0) > (cellular.downloadSpeedMbps ?? 0) ? .wifi : .cellular

        case "download":
            let wifiSpeed = wifi.downloadSpeedMbps ?? 0
            let cellSpeed = cellular.downloadSpeedMbps ?? 0
            return cellSpeed > wifiSpeed * 2 ? .cellular : .wifi

        case "browsing":
            return (wifi.latencyMs ?? 100) < (cellular.latencyMs ?? 100) ? .wifi : .cellular

        default:
            return wifi.overallScore > cellular.overallScore ? .wifi : .cellular
        }
    }

    private func generateRecommendation(
        wifi: ConnectionTestResult,
        cellular: ConnectionTestResult,
        winner: ConnectionTestResult.ConnectionType?
    ) -> ComparisonResult.Recommendation {
        guard let winner = winner else {
            return ComparisonResult.Recommendation(
                title: "No Connection Available",
                description: "Neither Wi-Fi nor Cellular is currently available.",
                suggestedConnection: nil
            )
        }

        let wifiDL = wifi.downloadSpeedMbps ?? 0
        let cellDL = cellular.downloadSpeedMbps ?? 0

        switch winner {
        case .wifi:
            if cellDL > wifiDL {
                return ComparisonResult.Recommendation(
                    title: "Use Wi-Fi (Save Data)",
                    description: "Cellular is faster, but Wi-Fi saves your data plan. Use Wi-Fi for large downloads.",
                    suggestedConnection: .wifi
                )
            }
            return ComparisonResult.Recommendation(
                title: "Use Wi-Fi",
                description: "Your Wi-Fi is performing better than cellular right now.",
                suggestedConnection: .wifi
            )

        case .cellular:
            if wifiDL > 10 {
                return ComparisonResult.Recommendation(
                    title: "Consider Cellular",
                    description: "Your cellular is outperforming Wi-Fi. Consider switching for important tasks.",
                    suggestedConnection: .cellular
                )
            }
            return ComparisonResult.Recommendation(
                title: "Use Cellular",
                description: "Your Wi-Fi is slow. Cellular is your best option right now.",
                suggestedConnection: .cellular
            )
        }
    }

    // MARK: - Cellular Info

    private func updateCellularInfo() {
        // Note: CTCarrier APIs are deprecated in iOS 16+ but still functional.
        // Apple has not provided a replacement.
        let networkInfo = CTTelephonyNetworkInfo()

        if #available(iOS 16.0, *) {
            // On iOS 16+, carrier info may return "--" but we try anyway
            if let carriers = networkInfo.serviceSubscriberCellularProviders,
               let carrier = carriers.values.first {
                let carrierName = carrier.carrierName

                var radioTech: String?
                if let techDict = networkInfo.serviceCurrentRadioAccessTechnology,
                   let tech = techDict.values.first {
                    radioTech = simplifyRadioTech(tech)
                }

                cellularInfo = CellularInfo(
                    carrierName: carrierName != "--" ? carrierName : nil,
                    radioTechnology: radioTech
                )
            }
        } else {
            // Pre-iOS 16
            if let carrier = networkInfo.serviceSubscriberCellularProviders?.values.first {
                let carrierName = carrier.carrierName

                var radioTech: String?
                if let techDict = networkInfo.serviceCurrentRadioAccessTechnology,
                   let tech = techDict.values.first {
                    radioTech = simplifyRadioTech(tech)
                }

                cellularInfo = CellularInfo(
                    carrierName: carrierName,
                    radioTechnology: radioTech
                )
            }
        }
    }

    private func simplifyRadioTech(_ tech: String) -> String {
        if tech.contains("NR") { return "5G" }
        if tech.contains("LTE") { return "4G LTE" }
        if tech.contains("WCDMA") || tech.contains("HSDPA") || tech.contains("HSUPA") { return "3G" }
        if tech.contains("EDGE") { return "EDGE" }
        if tech.contains("GPRS") { return "GPRS" }
        return tech
    }
}
