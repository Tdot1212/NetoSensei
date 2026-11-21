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
import Combine

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
    var serverUsed: String? = nil

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

    var overallScore: Double? {
        guard let download = downloadSpeedMbps,
              let latency = latencyMs, let upload = uploadSpeedMbps,
              [download, latency, upload].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }

        let downloadScore = min(download / 100.0 * 100, 100)
        let uploadScore = min(upload / 50.0 * 100, 100)
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
        let recommended: ConnectionTestResult.ConnectionType?
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
        CellularRadioInfo.shared.$generation
            .map { CellularInfo(carrierName: nil, radioTechnology: $0) }
            .assign(to: &$cellularInfo)
    }

    // MARK: - Run Comparison

    func runComparison(currentSpeed: SpeedTestResult? = nil, reuseCurrentSpeed: Bool = false) async -> ComparisonResult? {
        return await BackgroundTaskManager.shared.runInBackground(
            id: "speedComparison",
            name: "Speed Test",
            operation: {
                return await self.performComparison(currentSpeed: currentSpeed, reuseCurrentSpeed: reuseCurrentSpeed)
            },
            resultFormatter: { result in
                guard let r = result else { return "Failed" }
                return r.wifiResult.downloadSpeedMbps.map { String(format: "Download: %.1f Mbps", $0) } ?? "Wi-Fi not measured"
            }
        )
    }

    private func performComparison(currentSpeed: SpeedTestResult?, reuseCurrentSpeed: Bool) async -> ComparisonResult? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false; currentTest = nil }
        progress = 0
        error = nil
        if let previous = wifiResult, previous.timestamp.timeIntervalSinceNow < -600 { wifiResult = nil }
        if let previous = cellularResult, previous.timestamp.timeIntervalSinceNow < -600 { cellularResult = nil }
        comparisonResult = nil

        // FIX (Issue 1/6): Detect both interfaces AND which is primary so we
        // can decide whether cellular forcing is feasible.
        let interfaces = await detectInterfaces()

        // Test Wi-Fi
        if interfaces.wifiIsPrimary {
            currentTest = .wifi
            progress = 0.1
            if reuseCurrentSpeed {
                wifiResult = currentSpeed.map { Self.connectionResult($0, type: .wifi) } ?? unavailableResult(type: .wifi)
            } else {
                wifiResult = await testWiFiConnection()
            }
            progress = 0.45
        } else {
            if wifiResult == nil { wifiResult = unavailableResult(type: .wifi) }
        }

        // Test Cellular
        if interfaces.cellular && !interfaces.wifiIsPrimary {
            currentTest = .cellular
            progress = 0.5
            if reuseCurrentSpeed {
                cellularResult = currentSpeed.map { Self.connectionResult($0, type: .cellular) } ?? unavailableResult(type: .cellular)
            } else {
                cellularResult = await testCellularConnection(wifiIsPrimary: interfaces.wifiIsPrimary)
            }
            progress = 0.9
        } else {
            if cellularResult == nil { cellularResult = unavailableResult(type: .cellular, reason: interfaces.wifiIsPrimary ? Self.manualToggleError : nil) }
        }

        guard let wifi = wifiResult, let cellular = cellularResult else {
            isRunning = false
            return nil
        }

        let comparison = Self.generateComparison(wifi: wifi, cellular: cellular)
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

    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return false }
            done = true; return true
        }
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

    private func unavailableResult(type: ConnectionTestResult.ConnectionType, reason: String? = nil) -> ConnectionTestResult {
        ConnectionTestResult(
            connectionType: type,
            downloadSpeedMbps: nil,
            uploadSpeedMbps: nil,
            latencyMs: nil,
            jitterMs: nil,
            packetLoss: nil,
            timestamp: Date(),
            error: reason ?? "\(type.rawValue) not available"
        )
    }

    // All throughput, latency and jitter use the primary engine in separate
    // phases. Simultaneous transfers must not contaminate the idle latency.
    private nonisolated func testWiFiConnection() async -> ConnectionTestResult {
        await measure(type: .wifi)
    }

    private nonisolated func testCellularConnection(wifiIsPrimary: Bool) async -> ConnectionTestResult {
        await measure(type: .cellular)
    }

    private nonisolated func measure(type: ConnectionTestResult.ConnectionType) async -> ConnectionTestResult {
        let result = await SpeedTestEngine.shared.runSpeedTest()
        return Self.connectionResult(result, type: type)
    }

    nonisolated private static func connectionResult(_ result: SpeedTestResult, type: ConnectionTestResult.ConnectionType) -> ConnectionTestResult {
        let expected = type == .wifi ? "WiFi" : "Cellular"
        guard result.testUnavailableReason == nil, result.connectionType == expected, result.downloadSpeed > 0 else {
            return ConnectionTestResult(connectionType: type, downloadSpeedMbps: nil, uploadSpeedMbps: nil,
                latencyMs: nil, jitterMs: nil, packetLoss: nil, timestamp: Date(),
                error: result.testUnavailableReason ?? "Select the intended connection in Settings and repeat.")
        }
        var value = ConnectionTestResult(connectionType: type, downloadSpeedMbps: result.downloadSpeed,
            uploadSpeedMbps: result.measuredUploadSpeed, latencyMs: result.ping, jitterMs: result.jitter,
            packetLoss: result.packetLoss, timestamp: result.timestamp, error: nil)
        value.serverUsed = result.serverUsed
        return value
    }

    // MARK: - Generate Comparison

    nonisolated static func generateComparison(wifi: ConnectionTestResult, cellular: ConnectionTestResult) -> ComparisonResult {
        var winner: ConnectionTestResult.ConnectionType?

        let comparable = wifi.isSuccessful && cellular.isSuccessful && wifi.serverUsed != nil && wifi.serverUsed == cellular.serverUsed
            && abs(wifi.timestamp.timeIntervalSince(cellular.timestamp)) < 600
        if comparable, let wifiScore = wifi.overallScore, let cellularScore = cellular.overallScore, wifiScore != cellularScore {
            winner = wifiScore > cellularScore ? .wifi : .cellular
        }

        let useCases = comparable ? generateUseCases(wifi: wifi, cellular: cellular) : []
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

    nonisolated private static func generateUseCases(wifi: ConnectionTestResult, cellular: ConnectionTestResult) -> [ComparisonResult.UseCase] {
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

    nonisolated private static func bestFor(activity: String, wifi: ConnectionTestResult,
                        cellular: ConnectionTestResult) -> ConnectionTestResult.ConnectionType? {
        let w: Double?, c: Double?
        switch activity {
        case "video":
            guard let wl = wifi.latencyMs, let wj = wifi.jitterMs,
                  let cl = cellular.latencyMs, let cj = cellular.jitterMs else { return nil }
            w = wl + 2 * wj; c = cl + 2 * cj
        case "streaming", "download": w = wifi.downloadSpeedMbps; c = cellular.downloadSpeedMbps
        case "browsing": w = wifi.latencyMs; c = cellular.latencyMs
        default: w = wifi.overallScore; c = cellular.overallScore
        }
        guard let w, let c, w.isFinite, c.isFinite, w != c else { return nil }
        let higherBetter = activity == "streaming" || activity == "download"
        return (higherBetter ? w > c : w < c) ? .wifi : .cellular
    }

    nonisolated private static func generateRecommendation(
        wifi: ConnectionTestResult,
        cellular: ConnectionTestResult,
        winner: ConnectionTestResult.ConnectionType?
    ) -> ComparisonResult.Recommendation {
        guard let winner else {
            let title: String, detail: String
            if !wifi.isSuccessful || !cellular.isSuccessful {
                title = "Measure the missing path"
                detail = "A separate measurement is needed for each connection. Wi-Fi must be switched off to test the cellular path."
            } else if wifi.serverUsed == nil || wifi.serverUsed != cellular.serverUsed {
                title = "Different test servers"
                detail = "Both throughput samples were measured, but different endpoints prevent a fair overall comparison. Repeat against the same server."
            } else if abs(wifi.timestamp.timeIntervalSince(cellular.timestamp)) >= 600 {
                title = "Samples too far apart"
                detail = "Both paths were measured. Repeat within ten minutes for a current comparison."
            } else if wifi.overallScore == nil || cellular.overallScore == nil {
                title = "Overall rating unavailable"
                detail = "The throughput measurements remain valid. Missing latency or upload measurements prevent an overall winner."
            } else {
                title = "No unique overall winner"
                detail = "The measured overall ratings are tied. Review the individual measurements below."
            }
            return ComparisonResult.Recommendation(title: title, description: detail, suggestedConnection: nil)
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
}
