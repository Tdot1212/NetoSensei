//
//  AIPreflightCollector.swift
//  NetoSensei
//
//  Runs every diagnostic, security, and performance test BEFORE any AI
//  response is generated. The goal: the AI never analyzes partial data.
//
//  Usage:
//      let snapshot = await AIPreflightCollector.shared.collectAllData()
//      // snapshot is also cached in `lastSnapshot` for the 2-minute window.
//

import Foundation

@MainActor
final class AIPreflightCollector: ObservableObject {
    static let shared = AIPreflightCollector()

    // MARK: - Published state

    @Published var isCollecting = false
    @Published var progress: Double = 0
    @Published var currentStep: String = ""
    @Published var steps: [StepState] = AIPreflightCollector.initialSteps
    @Published var lastSnapshot: AINetworkSnapshot?
    @Published var lastCollectedAt: Date?

    // MARK: - Config

    /// Reuse snapshot if collected within this window (seconds).
    static let freshWindow: TimeInterval = 120

    /// Hard timeout for the entire collection.
    private let totalTimeoutSeconds: TimeInterval = 90

    // MARK: - Step tracking

    enum StepStatus: String {
        case pending, inProgress, completed, failed
    }

    struct StepState: Identifiable, Equatable {
        let id: Int
        let title: String
        var status: StepStatus
    }

    private static let initialSteps: [StepState] = [
        StepState(id: 0,  title: "Network status",       status: .pending),
        StepState(id: 1,  title: "WiFi signal",          status: .pending),
        StepState(id: 2,  title: "VPN detection",        status: .pending),
        StepState(id: 3,  title: "Geolocation",          status: .pending),
        StepState(id: 4,  title: "Diagnostics",          status: .pending),
        StepState(id: 5,  title: "Speed test",           status: .pending),
        StepState(id: 6,  title: "DNS security",         status: .pending),
        StepState(id: 7,  title: "TLS security",         status: .pending),
        StepState(id: 8,  title: "VPN leak test",        status: .pending),
        StepState(id: 9,  title: "Stability check",      status: .pending),
        StepState(id: 10, title: "Device discovery",     status: .pending),
        StepState(id: 11, title: "Router port scan",     status: .pending),
        StepState(id: 12, title: "VPN site reachability", status: .pending),
    ]

    private var completedCount = 0
    private var featureFlags: [String: Bool] = [:]
    private var featureSkipReasons: [String: String] = [:]

    /// Reuse a recent speed test result instead of re-running (5-minute window).
    static let speedTestCacheWindow: TimeInterval = 300

    private init() {}

    // MARK: - Snapshot Model

    struct AINetworkSnapshot: Codable {
        // Metadata
        var collectedAt: Date
        var collectionDurationMs: Double
        var featuresTested: [String: Bool]
        /// Features deliberately skipped (e.g. VPN leak test when VPN inactive).
        /// Maps feature key to reason so the AI can distinguish "skipped" from "failed".
        var featuresSkipped: [String: String]? = nil
        var isOffline: Bool

        // Network status
        var connectionType: String?
        var ssid: String?
        var bssid: String?
        var localIP: String?
        var publicIP: String?
        var ipv6Address: String?
        var isConnected: Bool
        var gatewayIP: String?
        var gatewayReachable: Bool?
        var gatewayLatencyMs: Double?
        var routerAdminURL: String?
        var internetReachable: Bool?
        var externalLatencyMs: Double?
        var dnsResolverIP: String?
        var dnsLatencyMs: Double?
        var isCGNAT: Bool?
        var overallHealth: String?

        // WiFi signal strength
        var signalStrength: Double?
        var signalQuality: String?

        // VPN detection (fresh)
        var vpnActive: Bool?
        var vpnConfidence: Double?
        var vpnDetectionMethod: String?
        var vpnInference: String?
        var vpnState: String?
        var vpnTunnelType: String?
        var vpnProtocol: String?
        var ipCountry: String?
        var ipCity: String?
        var ipISP: String?
        var ipASN: String?
        var ipType: String?
        var deviceCountry: String?
        var chinaMode: Bool?
        var isAuthoritative: Bool?

        // Geolocation
        var geoCountry: String?
        var geoRegion: String?
        var geoCity: String?
        var geoISP: String?
        var geoOrg: String?
        var geoASN: String?

        // Diagnostic engine
        var diagnosticTests: [DiagTest]?
        var diagnosticSummary: String?
        var diagnosticStatus: String?
        var diagnosticIssueCount: Int?
        var diagnosticPrimaryIssue: String?
        var diagnosticRecommendations: [String]?

        // Speed test
        var downloadMbps: Double?
        var uploadMbps: Double?
        var pingMs: Double?
        var jitterMs: Double?
        var packetLossPercent: Double?
        var speedTestServer: String?
        var speedTestQuality: String?

        // DNS security
        var dnsSystemServers: [String]?
        var dnsIsEncrypted: Bool?
        var dnsEncryptionType: String?
        var dnsHasLeak: Bool?
        var dnsSecurityRating: String?
        var dnsAverageLatencyMs: Double?

        // TLS security
        var tlsResults: [TLSSite]?
        var tlsCriticalIssues: Int?

        // VPN leak test
        var vpnLeakVerdict: String?
        var vpnLeakDnsLeaking: Bool?
        var vpnLeakIpLeaking: Bool?
        var vpnLeakWebRTCLeaking: Bool?
        var vpnServerIP: String?
        var vpnDetectedDNSServers: [String]?

        // Connection stability
        var stabilityQuality: String?
        var stabilityUptimePercent: Double?
        var stabilityDisconnectCount: Int?
        var stabilityLatencySpikeCount: Int?
        var stabilityAverageLatencyMs: Double?
        var recentStabilityEvents: [String]?

        // Device discovery
        var devicesFoundCount: Int?
        var devicesConnectedNow: Int?
        var deviceList: [String]?

        // Router port scan
        var gatewayOpenPorts: [String]?
        var gatewayPortRisk: String?

        // VPN site reachability benchmark (only populated when VPN active)
        var vpnSiteBenchmark: [VPNSiteResult]?
        var vpnSitesReachable: Int?
        var vpnSitesTotal: Int?

        // History (trends)
        var speedHistory: [SpeedHistoryEntry]?
        var diagnosticHistory: [DiagnosticHistoryItem]?

        // Nested
        struct DiagTest: Codable {
            let name: String
            let result: String
            let latencyMs: Double?
            let details: String
        }

        struct TLSSite: Codable {
            let host: String
            let tlsVersion: String
            let securityRating: String
            let issueCount: Int
            let firstIssue: String?
            let firstIssueSeverity: String?
        }

        struct SpeedHistoryEntry: Codable {
            let date: String
            let downloadMbps: Double
            let uploadMbps: Double
            let pingMs: Double
            let vpnActive: Bool
        }

        struct DiagnosticHistoryItem: Codable {
            let date: String
            let summary: String
            let issueCount: Int
            let overallStatus: String
        }

        struct VPNSiteResult: Codable {
            let name: String
            let responseTimeMs: Double?
            let reachable: Bool
            let qualityRating: String
            let error: String?
        }
    }

    // MARK: - Public API

    /// Collect every diagnostic/security signal available, honoring cache window.
    /// Pass `forceRefresh: true` to ignore the 2-minute cache.
    /// Pass `skipSpeedTest: true` for a Quick Scan that skips the speed test step.
    func collectAllData(forceRefresh: Bool = false, skipSpeedTest: Bool = false) async -> AINetworkSnapshot {
        if !forceRefresh, let cached = lastSnapshot, isSnapshotFresh() {
            return cached
        }

        isCollecting = true
        completedCount = 0
        featureFlags = [:]
        featureSkipReasons = [:]
        progress = 0
        steps = Self.initialSteps

        let startTime = CFAbsoluteTimeGetCurrent()

        // Run the entire collection under a 90-second budget.
        let snapshot: AINetworkSnapshot = await withTaskGroup(of: AINetworkSnapshot.self) { group in
            group.addTask { @MainActor in
                await self.performCollection(startTime: startTime, skipSpeedTest: skipSpeedTest)
            }
            group.addTask { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(self.totalTimeoutSeconds * 1_000_000_000))
                // Return a partial snapshot built from whatever we have so far
                return self.buildPartialTimeoutSnapshot(startTime: startTime)
            }
            let first = await group.next() ?? self.buildPartialTimeoutSnapshot(startTime: startTime)
            group.cancelAll()
            return first
        }

        lastSnapshot = snapshot
        lastCollectedAt = Date()
        isCollecting = false
        progress = 1.0
        currentStep = "Complete"

        let payload = (try? JSONEncoder().encode(snapshot))?.count ?? 0
        let succeeded = snapshot.featuresTested.filter { $0.value }.count
        let total = snapshot.featuresTested.count
        debugLog("[AI] Sending \(payload) bytes of diagnostic data to AI (\(succeeded)/\(total) features collected in \(Int(snapshot.collectionDurationMs))ms)")

        return snapshot
    }

    /// True when we have a cached snapshot that's still within the fresh window.
    func isSnapshotFresh() -> Bool {
        guard let collectedAt = lastCollectedAt else { return false }
        return Date().timeIntervalSince(collectedAt) < Self.freshWindow
    }

    /// Drop the cached snapshot so the next `collectAllData` call runs fresh.
    /// Called when starting a new chat session to prevent cross-session bleed.
    func invalidateCache() {
        lastSnapshot = nil
        lastCollectedAt = nil
    }

    /// Convenience JSON serializer for injecting into AI prompts.
    func snapshotJSON(_ snapshot: AINetworkSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{\"error\": \"Failed to serialize diagnostic snapshot\"}"
    }

    // MARK: - Collection orchestration

    private func performCollection(startTime: CFAbsoluteTime, skipSpeedTest: Bool = false) async -> AINetworkSnapshot {
        var snapshot = AINetworkSnapshot(
            collectedAt: Date(),
            collectionDurationMs: 0,
            featuresTested: [:],
            isOffline: false,
            isConnected: false
        )

        // ---- Step 0: Network status (instant) ----
        await beginStep(0, label: "Checking network status...")
        let status = NetworkMonitorService.shared.currentStatus
        snapshot.connectionType = status.connectionType?.displayName ?? (status.wifi.isConnected ? "WiFi" : "Unknown")
        snapshot.ssid = status.wifi.ssid
        snapshot.bssid = status.wifi.bssid
        snapshot.localIP = status.localIP
        snapshot.publicIP = status.publicIP
        snapshot.ipv6Address = status.ipv6Address
        snapshot.isConnected = status.internet.isReachable || status.wifi.isConnected
        snapshot.gatewayIP = status.router.gatewayIP
        snapshot.gatewayReachable = status.router.isReachable
        snapshot.gatewayLatencyMs = status.router.latency
        snapshot.routerAdminURL = status.router.adminURL
        snapshot.internetReachable = status.internet.isReachable
        snapshot.externalLatencyMs = status.internet.latencyToExternal
        snapshot.dnsResolverIP = status.dns.resolverIP
        snapshot.dnsLatencyMs = status.dns.latency
        snapshot.isCGNAT = status.isCGNAT
        snapshot.overallHealth = Self.healthString(status.overallHealth)
        snapshot.isOffline = !(status.internet.isReachable || status.wifi.isConnected)
        setFeature("network_status", true)
        await completeStep(0, status: .completed)

        // If offline, mark remaining network-dependent steps as failed up front
        // but still capture whatever local data exists.
        let offline = snapshot.isOffline

        // ---- Step 1: WiFi signal ----
        await beginStep(1, label: "Measuring WiFi signal...")
        let strength = SignalStrengthTracker.shared.currentStrength ?? status.wifi.signalStrength
        snapshot.signalStrength = strength
        snapshot.signalQuality = strength.flatMap(Self.signalQualityString)
        let signalCollected = strength != nil
        setFeature("signal_strength", signalCollected)
        await completeStep(1, status: signalCollected ? .completed : .failed)

        // ---- Step 2: VPN detection (fresh) ----
        await beginStep(2, label: "Detecting VPN status...")
        if offline {
            setFeature("vpn_detection", false)
            await completeStep(2, status: .failed)
        } else {
            let vpn = await SmartVPNDetector.shared.detectVPN(forceRefresh: true)
            snapshot.vpnActive = vpn.isVPNActive
            snapshot.vpnConfidence = vpn.confidence
            snapshot.vpnDetectionMethod = vpn.detectionMethod
            snapshot.vpnInference = vpn.inferenceReasons.joined(separator: "; ")
            snapshot.vpnState = vpn.vpnState.rawValue
            snapshot.vpnProtocol = vpn.vpnProtocol
            snapshot.ipCountry = vpn.publicCountry
            snapshot.ipCity = vpn.publicCity
            snapshot.ipISP = vpn.publicISP
            snapshot.ipASN = vpn.publicASN
            snapshot.ipType = vpn.ipType
            snapshot.deviceCountry = vpn.expectedCountry
            snapshot.chinaMode = vpn.isLikelyInChina
            snapshot.isAuthoritative = vpn.isAuthoritative
            snapshot.vpnTunnelType = status.vpn.tunnelType
            setFeature("vpn_detection", true)
            await completeStep(2, status: .completed)
        }

        // ---- Step 3: Geolocation ----
        await beginStep(3, label: "Looking up IP geolocation...")
        if offline {
            setFeature("geoip", false)
            await completeStep(3, status: .failed)
        } else {
            let geo = await GeoIPService.shared.fetchGeoIPInfo(forceRefresh: false)
            snapshot.geoCountry = geo.country
            snapshot.geoRegion = geo.region
            snapshot.geoCity = geo.city
            snapshot.geoISP = geo.isp
            snapshot.geoOrg = geo.org
            snapshot.geoASN = geo.asn
            let ok = geo.country != nil
            setFeature("geoip", ok)
            await completeStep(3, status: ok ? .completed : .failed)
        }

        // ---- Step 4: Full diagnostic ----
        await beginStep(4, label: "Running network diagnostics...")
        if offline {
            setFeature("diagnostic", false)
            await completeStep(4, status: .failed)
        } else {
            let diag = await DiagnosticEngine.shared.runDiagnostic()
            snapshot.diagnosticTests = diag.testsPerformed.map { test in
                AINetworkSnapshot.DiagTest(
                    name: test.name,
                    result: Self.testResultString(test.result),
                    latencyMs: test.latency,
                    details: test.details
                )
            }
            snapshot.diagnosticSummary = diag.summary
            snapshot.diagnosticStatus = Self.healthString(diag.overallStatus)
            snapshot.diagnosticIssueCount = diag.issues.count
            snapshot.diagnosticPrimaryIssue = diag.primaryIssue?.title
            snapshot.diagnosticRecommendations = diag.recommendations
            setFeature("diagnostic", true)
            await completeStep(4, status: .completed)
        }

        // ---- Step 5: Speed test ----
        await beginStep(5, label: "Running speed test...")
        if offline {
            setFeature("speed_test", false)
            await completeStep(5, status: .failed)
        } else if skipSpeedTest {
            markSkipped("speed_test", reason: "user_requested_quick_scan")
            await completeStep(5, status: .failed)
        } else if let cached = recentCachedSpeedTest() {
            let age = Int(Date().timeIntervalSince(cached.timestamp) / 60)
            debugLog("[AI Preflight] Using cached speed test from \(age)m ago")
            applySpeedTestResult(cached, to: &snapshot)
            setFeature("speed_test", cached.downloadSpeed > 0)
            await completeStep(5, status: cached.downloadSpeed > 0 ? .completed : .failed)
        } else {
            let speed = await SpeedTestEngine.shared.runSpeedTest()
            applySpeedTestResult(speed, to: &snapshot)
            HistoryManager.shared.addSpeedTest(speed)
            // Only mark feature tested when we actually got a download measurement.
            // A zero download means the test failed — don't feed "0 Mbps" to the AI as real data.
            let ok = speed.downloadSpeed > 0
            setFeature("speed_test", ok)
            await completeStep(5, status: ok ? .completed : .failed)
        }

        // ---- Step 6: DNS security ----
        await beginStep(6, label: "Analyzing DNS security...")
        if offline {
            setFeature("dns_security", false)
            await completeStep(6, status: .failed)
        } else {
            let dns = await DNSAnalyzer.shared.runFullAnalysis()
            snapshot.dnsSystemServers = dns.systemDNS.map { $0.ipAddress }
            snapshot.dnsIsEncrypted = dns.isEncryptedDNS
            snapshot.dnsEncryptionType = dns.encryptedDNSType?.rawValue
            snapshot.dnsHasLeak = dns.hasLeak
            snapshot.dnsSecurityRating = dns.securityRating.rawValue
            // FIX (Phase 6.1): DNSAnalyzer no longer reports an "average latency"
            // — the previous one was bogus (system-resolver short-circuit). Use
            // the network monitor's real DNS RTT instead.
            snapshot.dnsAverageLatencyMs = NetworkMonitorService.shared.currentStatus.dns.latency
            setFeature("dns_security", true)
            await completeStep(6, status: .completed)
        }

        // ---- Step 7: TLS security ----
        await beginStep(7, label: "Testing TLS/SSL security...")
        if offline {
            setFeature("tls_security", false)
            await completeStep(7, status: .failed)
        } else {
            let hosts = ["google.com", "apple.com", "cloudflare.com"]
            var results: [AINetworkSnapshot.TLSSite] = []
            for host in hosts {
                let tls = await TLSAnalyzer.shared.analyzeHost(host)
                results.append(AINetworkSnapshot.TLSSite(
                    host: host,
                    tlsVersion: tls.tlsVersion.version,
                    securityRating: tls.securityRating.rawValue,
                    issueCount: tls.issues.count,
                    firstIssue: tls.issues.first?.title,
                    firstIssueSeverity: tls.issues.first?.severity.rawValue
                ))
            }
            snapshot.tlsResults = results
            snapshot.tlsCriticalIssues = results.filter { $0.firstIssueSeverity == "Critical" }.count
            setFeature("tls_security", !results.isEmpty)
            await completeStep(7, status: .completed)
        }

        // ---- Step 8: VPN leak test ----
        await beginStep(8, label: "Testing for VPN leaks...")
        if offline {
            setFeature("vpn_leak", false)
            await completeStep(8, status: .failed)
        } else if snapshot.vpnActive == true {
            let leak = await PrivacyShieldService.shared.runVPNLeakTest()
            snapshot.vpnLeakVerdict = Self.verdictString(leak.overallVerdict)
            snapshot.vpnLeakDnsLeaking = leak.dnsLeak.isLeaking
            snapshot.vpnLeakIpLeaking = leak.ipLeak.isLeaking
            snapshot.vpnLeakWebRTCLeaking = leak.webRTCLeak.isLeaking
            snapshot.vpnServerIP = leak.vpnServerIP
            snapshot.vpnDetectedDNSServers = leak.detectedDNSServers
            setFeature("vpn_leak", true)
            await completeStep(8, status: .completed)
        } else {
            // Not applicable — VPN inactive, so a leak test has no meaning.
            markSkipped("vpn_leak", reason: "vpn_inactive")
            await completeStep(8, status: .failed)
        }

        // ---- Step 9: Connection stability ----
        await beginStep(9, label: "Checking connection stability...")
        let stability = ConnectionStabilityMonitor.shared
        if let metrics = stability.currentMetrics {
            snapshot.stabilityQuality = metrics.connectionQuality.rawValue
            snapshot.stabilityUptimePercent = metrics.uptimePercentage
            snapshot.stabilityDisconnectCount = metrics.disconnectCount
            snapshot.stabilityLatencySpikeCount = metrics.latencySpikeCount
            snapshot.stabilityAverageLatencyMs = metrics.averageLatency
        }
        let recent = stability.events.suffix(20)
        if !recent.isEmpty {
            snapshot.recentStabilityEvents = recent.map { event in
                let latencyPart = event.latency.map { " (\(Int($0))ms)" } ?? ""
                return "\(event.type.rawValue): \(event.details)\(latencyPart)"
            }
        }
        let stabilityOK = stability.currentMetrics != nil || !recent.isEmpty
        setFeature("stability", stabilityOK)
        await completeStep(9, status: stabilityOK ? .completed : .failed)

        // ---- Step 10: Device discovery ----
        await beginStep(10, label: "Scanning for devices...")
        if offline {
            setFeature("device_discovery", false)
            await completeStep(10, status: .failed)
        } else {
            let discovered = await NetworkDeviceDiscovery.shared.scanNetwork()
            snapshot.devicesFoundCount = discovered.count
            snapshot.devicesConnectedNow = discovered.count
            snapshot.deviceList = discovered.prefix(20).map { device in
                let label = device.hostname ?? device.ipAddress
                return "\(label) - \(device.ipAddress)"
            }
            setFeature("device_discovery", !discovered.isEmpty)
            await completeStep(10, status: discovered.isEmpty ? .failed : .completed)
        }

        // ---- Step 11: Gateway port scan ----
        await beginStep(11, label: "Scanning router ports...")
        if offline {
            setFeature("gateway_scan", false)
            await completeStep(11, status: .failed)
        } else if let gateway = snapshot.gatewayIP {
            let ports: [UInt16] = [80, 443, 22, 23, 53, 445, 8080, 8443, 5000]
            let scan = await PortScanner.shared.scanDevice(ip: gateway, hostname: "Router", ports: ports)
            let openPorts = scan.openPorts
            let portDescriptions: [String] = openPorts.map { port in
                "\(port.port) (\(port.service)) [\(port.risk.rawValue)]"
            }
            snapshot.gatewayOpenPorts = portDescriptions
            let hasDanger = openPorts.contains { $0.risk == .danger }
            let hasCaution = openPorts.contains { $0.risk == .caution }
            let riskLabel: String
            if hasDanger {
                riskLabel = "Danger"
            } else if hasCaution {
                riskLabel = "Caution"
            } else if openPorts.isEmpty {
                riskLabel = "none"
            } else {
                riskLabel = openPorts.first?.risk.rawValue ?? "none"
            }
            snapshot.gatewayPortRisk = riskLabel
            setFeature("gateway_scan", true)
            await completeStep(11, status: .completed)
        } else {
            setFeature("gateway_scan", false)
            await completeStep(11, status: .failed)
        }

        // ---- Step 12: VPN site reachability benchmark ----
        await beginStep(12, label: "Testing VPN site reachability...")
        if offline {
            markSkipped("vpn_site_benchmark", reason: "offline")
            await completeStep(12, status: .failed)
        } else if snapshot.vpnActive == true {
            // Race the benchmark against a 15s timeout. Whichever finishes first wins;
            // if the timeout wins we still read whatever partial results landed.
            let bench = VPNBenchmark()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    await bench.runBenchmark()
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                }
                _ = await group.next()
                group.cancelAll()
            }
            let results = bench.results
            let mapped: [AINetworkSnapshot.VPNSiteResult] = results.map { r in
                AINetworkSnapshot.VPNSiteResult(
                    name: r.destination.rawValue,
                    responseTimeMs: r.responseTimeMs,
                    reachable: r.reachable,
                    qualityRating: r.qualityRating,
                    error: r.error
                )
            }
            snapshot.vpnSiteBenchmark = mapped.isEmpty ? nil : mapped
            snapshot.vpnSitesTotal = mapped.isEmpty ? nil : mapped.count
            snapshot.vpnSitesReachable = mapped.isEmpty ? nil : mapped.filter { $0.reachable }.count
            let ok = !mapped.isEmpty
            setFeature("vpn_site_benchmark", ok)
            await completeStep(12, status: ok ? .completed : .failed)
        } else {
            // VPN not active — this benchmark is about VPN-dependent reachability.
            markSkipped("vpn_site_benchmark", reason: "vpn_inactive")
            await completeStep(12, status: .failed)
        }

        // ---- History enrichment (trends) ----
        let speedHistory = HistoryManager.shared.speedTestHistory
        if !speedHistory.isEmpty {
            let isoFormatter = ISO8601DateFormatter()
            snapshot.speedHistory = speedHistory.prefix(5).map { entry in
                AINetworkSnapshot.SpeedHistoryEntry(
                    date: isoFormatter.string(from: entry.timestamp),
                    downloadMbps: entry.downloadSpeed,
                    uploadMbps: entry.uploadSpeed,
                    pingMs: entry.ping,
                    vpnActive: entry.vpnActive
                )
            }
        }

        let diagHistory = HistoryManager.shared.diagnosticHistory
        if !diagHistory.isEmpty {
            let isoFormatter = ISO8601DateFormatter()
            snapshot.diagnosticHistory = diagHistory.prefix(5).map { entry in
                AINetworkSnapshot.DiagnosticHistoryItem(
                    date: isoFormatter.string(from: entry.timestamp),
                    summary: entry.summary,
                    issueCount: entry.issueCount,
                    overallStatus: entry.overallStatus
                )
            }
        }

        // Finalize
        snapshot.featuresTested = featureFlags
        snapshot.featuresSkipped = featureSkipReasons.isEmpty ? nil : featureSkipReasons
        snapshot.collectionDurationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return snapshot
    }

    private func buildPartialTimeoutSnapshot(startTime: CFAbsoluteTime) -> AINetworkSnapshot {
        // Called if we hit the 90s timeout. Return whatever we've collected so far.
        var snapshot = lastSnapshot ?? AINetworkSnapshot(
            collectedAt: Date(),
            collectionDurationMs: 0,
            featuresTested: [:],
            isOffline: false,
            isConnected: false
        )
        snapshot.featuresTested = featureFlags
        snapshot.collectionDurationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return snapshot
    }

    // MARK: - Helpers

    private func beginStep(_ id: Int, label: String) async {
        currentStep = label
        if id < steps.count {
            steps[id].status = .inProgress
        }
    }

    private func completeStep(_ id: Int, status: StepStatus) async {
        if id < steps.count {
            steps[id].status = status
        }
        completedCount += 1
        progress = Double(completedCount) / Double(Self.initialSteps.count)
    }

    private func setFeature(_ key: String, _ value: Bool) {
        featureFlags[key] = value
    }

    /// Mark a feature as intentionally skipped (not failed). Sets featureFlags to false
    /// and records a reason the AI can read from `featuresSkipped`.
    private func markSkipped(_ key: String, reason: String) {
        featureFlags[key] = false
        featureSkipReasons[key] = reason
    }

    /// Returns the most recent speed test from history if it's within the 5-minute cache window.
    private func recentCachedSpeedTest() -> SpeedTestResult? {
        guard let latest = HistoryManager.shared.speedTestHistory.first else { return nil }
        let age = Date().timeIntervalSince(latest.timestamp)
        guard age < Self.speedTestCacheWindow else { return nil }
        return latest
    }

    /// Copy speed test numbers into the snapshot, filtering out zero/sentinel values
    /// so the AI never sees "0 Mbps" or "999 ms" as if they were real measurements.
    private func applySpeedTestResult(_ speed: SpeedTestResult, to snapshot: inout AINetworkSnapshot) {
        snapshot.downloadMbps        = speed.downloadSpeed > 0 ? speed.downloadSpeed : nil
        snapshot.uploadMbps          = speed.uploadSpeed   > 0 ? speed.uploadSpeed   : nil
        snapshot.pingMs              = speed.ping   < 999 ? speed.ping   : nil
        snapshot.jitterMs            = speed.jitter > 0   ? speed.jitter : nil
        snapshot.packetLossPercent   = speed.packetLoss >= 0 && speed.packetLoss < 100 ? speed.packetLoss : nil
        snapshot.speedTestServer     = speed.serverUsed
        snapshot.speedTestQuality    = speed.downloadSpeed > 0 ? speed.quality.rawValue : nil
    }

    // MARK: - Enum stringifiers

    private static func healthString(_ h: NetworkHealth) -> String {
        switch h {
        case .excellent: return "Excellent"
        case .fair:      return "Fair"
        case .poor:      return "Poor"
        case .unknown:   return "Unknown"
        }
    }

    private static func testResultString(_ r: DiagnosticTest.TestResult) -> String {
        switch r {
        case .pass:    return "pass"
        case .fail:    return "fail"
        case .warning: return "warning"
        case .skipped: return "skipped"
        }
    }

    private static func verdictString(_ v: VPNLeakTestResult.Verdict) -> String {
        switch v {
        case .noLeaks:    return "noLeaks"
        case .minorLeaks: return "minorLeaks"
        case .majorLeaks: return "majorLeaks"
        case .noVPN:      return "noVPN"
        }
    }

    private static func signalQualityString(_ strength: Double) -> String {
        switch strength {
        case 0.75...:         return "Excellent"
        case 0.5..<0.75:      return "Good"
        case 0.25..<0.5:      return "Fair"
        default:              return "Poor"
        }
    }
}
