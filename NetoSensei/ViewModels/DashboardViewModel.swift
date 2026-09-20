//
//  DashboardViewModel.swift
//  NetoSensei
//
//  Dashboard ViewModel - Manages dashboard state and network monitoring
//  STEP 4 EXPANDED IMPLEMENTATION
//

import Foundation
import Combine
import SwiftUI


@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties (STEP 4 Required)

    /// Current network status
    @Published var status: NetworkStatus = .empty

    /// Loading state
    @Published var isLoading: Bool = false

    /// True until NetworkMonitorService completes its first real status update
    @Published var isInitializing: Bool = true

    /// Last update timestamp
    @Published var lastUpdated: Date? = nil

    /// Public IP address
    @Published var publicIP: String = ""

    /// ISP name
    @Published var ispName: String = ""

    /// Connection quality rating
    @Published var connectionQuality: String = ""

    /// Error state
    @Published var errorMessage: String?

    // MARK: - Additional Properties

    @Published var geoIPInfo: GeoIPInfo = .empty
    @Published var isMonitoring = false

    // MARK: - Connection Stability Properties

    /// Connection stability summary text
    @Published var stabilitySummary: String = "Monitoring..."

    /// Connection stability metrics
    @Published var stabilityMetrics: ConnectionStabilityMetrics?

    // MARK: - Data Smoothing (PART 1: Stabilize ratings)

    /// Rolling history for latency smoothing (prevents flip-flopping)
    private var internetLatencyHistory: [Double] = []
    private var gatewayLatencyHistory: [Double] = []
    private var dnsLatencyHistory: [Double] = []
    private let smoothingWindow = 5  // Average of last 5 readings


    /// Identity of the network the smoothing buffers currently describe.
    /// When this changes (SSID / interface / subnet), the buffers are cleared
    /// so old samples can't blend into the new network's averages.
    private var lastNetworkKey: String?

    /// Smoothed values for display
    @Published var smoothedInternetLatency: Double?
    @Published var smoothedGatewayLatency: Double?
    @Published var smoothedDNSLatency: Double?
    /// Diagnosis v2: the ONE verdict every Home surface renders from.
    @Published var verdict: NetworkVerdict?

    // MARK: - Layer 3: Interpretation Engine Output
    @Published var currentDiagnosis: NetworkDiagnosis?

    // MARK: - Services

    private let networkMonitor: NetworkMonitorService
    private let geoIPService: GeoIPService
    private let historyManager: HistoryManager
    private let stabilityMonitor: ConnectionStabilityMonitor

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // FIXED: Re-entry guards to prevent cascading UI updates
    private var isUpdatingUIStatus = false
    private var isSyncingDiagnostic = false

    // FIXED: Debounce refresh calls to prevent excessive refreshing
    // PART 1: Reduce refresh frequency to max once per 60 seconds (except manual pull-to-refresh)
    private var lastRefreshTime: Date?
    private let minRefreshInterval: TimeInterval = 60.0  // Changed from 3.0 to 60.0
    private var hasRefreshedOnLaunch = false

    // MARK: - Initialization

    init() {
        self.networkMonitor = NetworkMonitorService.shared
        self.geoIPService = GeoIPService.shared
        self.historyManager = HistoryManager.shared
        self.stabilityMonitor = ConnectionStabilityMonitor.shared
        setupBindings()
    }

    init(networkMonitor: NetworkMonitorService, geoIPService: GeoIPService, historyManager: HistoryManager, stabilityMonitor: ConnectionStabilityMonitor) {
        self.networkMonitor = networkMonitor
        self.geoIPService = geoIPService
        self.historyManager = historyManager
        self.stabilityMonitor = stabilityMonitor
        setupBindings()
    }

    // MARK: - Setup

    /// Bind to service publishers
    private func setupBindings() {
        // Observe network status changes
        // FIXED: Apply smoothing to prevent flip-flopping ratings
        networkMonitor.$currentStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                // FIX (Phase 2): a network switch is a state change, not noise.
                // Discard latency samples from the previous network BEFORE
                // smoothing so the rolling averages can't blend across networks.
                self?.clearSmoothingIfNetworkChanged(newStatus)
                self?.status = newStatus
                self?.updateSmoothedValues()  // Apply smoothing
                // FIX (Issue 3/6): debounce probe failures so a single timeout
                // can't trigger "DNS Resolution Failed" / "Router Unreachable".
                MeasurementValidityTracker.shared.ingest(newStatus)
                self?.updateUIStatus()
                // Layer 3: Update diagnosis on each status change
                self?.currentDiagnosis = InterpretationEngine.shared.diagnose(
                    status: newStatus,
                    vpnResult: SmartVPNDetector.shared.detectionResult
                )
            }
            .store(in: &cancellables)

        networkMonitor.$isMonitoring
            .receive(on: DispatchQueue.main)
            .assign(to: &$isMonitoring)

        networkMonitor.$isInitializing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isInitializing)

        // Observe GeoIP changes
        geoIPService.$currentGeoIP
            .receive(on: DispatchQueue.main)
            .sink { [weak self] geoIP in
                self?.geoIPInfo = geoIP
                self?.publicIP = geoIP.publicIP
                self?.ispName = geoIP.ispDisplay
            }
            .store(in: &cancellables)


        // Observe connection stability metrics
        stabilityMonitor.$currentMetrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.stabilityMetrics = metrics
                self?.stabilitySummary = self?.stabilityMonitor.stabilitySummary ?? "Monitoring..."
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods (STEP 4 Required)

    // MARK: - Refresh policy (Commit 8: manual refresh must re-read the network)

    /// Why a refresh was requested. The policy differs by trigger:
    ///  - `.automatic` (tab appears): once on launch, then at most every 60 s —
    ///    this limit exists to stop background churn. Dropped silently when one
    ///    is already in flight.
    ///  - `.userInitiated` (pull-to-refresh): never rate-limited, FORCES the
    ///    monitor to re-evaluate the path, and if a refresh is already running
    ///    it WAITS for it and then runs again — the in-flight one may have
    ///    started before the user changed the network (the bug: Wi-Fi turned
    ///    off, pull lands during the path-change update, pull is dropped, the
    ///    pre-change status is re-rendered). Coalescing onto the in-flight run
    ///    would hand the user pre-gesture data; re-running after it guarantees
    ///    post-gesture data.
    ///  - `.foreground` (scene became active): same as user-initiated but
    ///    without the loading overlay.
    enum RefreshTrigger: Equatable { case automatic, userInitiated, foreground }

    enum RefreshDecision: Equatable { case run, waitForInFlightThenRun, skipRateLimited, skipInFlight }

    /// Pure policy (unit-tested).
    nonisolated static func refreshDecision(trigger: RefreshTrigger,
                                            inFlight: Bool,
                                            hasRefreshedOnLaunch: Bool,
                                            lastRefreshTime: Date?,
                                            now: Date,
                                            minInterval: TimeInterval) -> RefreshDecision {
        switch trigger {
        case .userInitiated, .foreground:
            return inFlight ? .waitForInFlightThenRun : .run
        case .automatic:
            if inFlight { return .skipInFlight }
            if hasRefreshedOnLaunch, let last = lastRefreshTime, now.timeIntervalSince(last) < minInterval {
                return .skipRateLimited
            }
            return .run
        }
    }

    /// Whether a trigger must force NetworkMonitorService to re-evaluate the
    /// path (never just re-render `currentStatus`).
    nonisolated static func forcesMonitorUpdate(_ trigger: RefreshTrigger) -> Bool {
        trigger != .automatic
    }

    /// The refresh currently running, if any — awaited by user-initiated refreshes.
    private var inFlightRefresh: Task<Void, Never>?

    /// Backward-compatible entry point. `forceRefresh` = pull-to-refresh.
    func refresh(forceRefresh: Bool = false) async {
        await refresh(trigger: forceRefresh ? .userInitiated : .automatic)
    }

    /// Refresh all network data (see RefreshTrigger for the policy).
    func refresh(trigger: RefreshTrigger) async {
        let decision = Self.refreshDecision(trigger: trigger,
                                            inFlight: inFlightRefresh != nil,
                                            hasRefreshedOnLaunch: hasRefreshedOnLaunch,
                                            lastRefreshTime: lastRefreshTime,
                                            now: Date(),
                                            minInterval: minRefreshInterval)
        switch decision {
        case .skipInFlight:
            debugLog("🔄 Dashboard refresh already in progress, skipping (automatic)")
            return
        case .skipRateLimited:
            debugLog("🔄 Dashboard refresh() skipped — auto-refresh limited to once per 60s")
            return
        case .waitForInFlightThenRun:
            debugLog("🔄 Dashboard refresh (\(trigger)) — waiting for the in-flight refresh, then re-running")
            while let running = inFlightRefresh { await running.value }
        case .run:
            break
        }
        if trigger == .automatic { hasRefreshedOnLaunch = true }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(trigger: trigger)
        }
        inFlightRefresh = task
        await task.value
        if inFlightRefresh == task { inFlightRefresh = nil }
    }

    private func performRefresh(trigger: RefreshTrigger) async {
        lastRefreshTime = Date()
        let forceMonitor = Self.forcesMonitorUpdate(trigger)
        debugLog("🔄 Dashboard refresh() called (\(trigger)\(forceMonitor ? ", forcing a fresh network read" : ""))")
        // The overlay reflects real work for the two explicit triggers; a
        // foreground re-read is quiet.
        isLoading = trigger != .foreground

        // Use a timeout to prevent infinite loading
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Add timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)  // 15 second max
                    throw RefreshError.timeout
                }

                // Add actual refresh task
                group.addTask { [weak self] in
                    guard let self = self else { return }

                    // Step 1: Force VPN re-detection on manual refresh
                    if forceMonitor {
                        await self.networkMonitor.forceRefreshVPN()
                    }

                    // Step 2: Update network status. Forced = re-evaluate the
                    // path even if a periodic update is already running.
                    await self.networkMonitor.updateNetworkStatus(force: forceMonitor)

                    // Step 3: Fetch public IP (don't wait if slow)
                    await self.fetchPublicIPWithTimeout()
                }

                // Wait for first completion (either success or timeout)
                _ = try await group.next()
                group.cancelAll()
            }
        } catch {
            debugLog("⚠️ Dashboard refresh timeout or error: \(error)")
        }

        // Update UI with whatever data we have
        let currentStatus = networkMonitor.currentStatus
        debugLog("📊 Got network status: WiFi connected=\(currentStatus.wifi.isConnected), SSID=\(currentStatus.wifi.ssid ?? "nil")")

        status = currentStatus
        updateUIStatus()

        // Layer 3: Run InterpretationEngine to produce ExplanationCards
        currentDiagnosis = InterpretationEngine.shared.diagnose(
            status: currentStatus,
            vpnResult: SmartVPNDetector.shared.detectionResult
        )

        lastUpdated = Date()
        isLoading = false
        debugLog("✅ Dashboard refresh complete")
    }

    private enum RefreshError: Error {
        case timeout
    }

    /// Fetch public IP with timeout
    private func fetchPublicIPWithTimeout() async {
        do {
            try await withThrowingTaskGroup(of: GeoIPInfo.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 second timeout
                    throw RefreshError.timeout
                }

                group.addTask { [weak self] in
                    guard let self = self else { return .empty }
                    return await self.geoIPService.fetchGeoIPInfo()
                }

                if let result = try await group.next() {
                    await MainActor.run { [weak self] in
                        self?.geoIPInfo = result
                        self?.publicIP = result.publicIP
                        self?.ispName = result.ispDisplay
                    }
                }
                group.cancelAll()
            }
        } catch {
            debugLog("⚠️ GeoIP fetch timeout")
        }
    }

    /// Fetch public IP information
    /// STEP 4 Requirement: Uses GeoIPService
    func fetchPublicIP() async {
        let geoIP = await geoIPService.fetchGeoIPInfo()
        geoIPInfo = geoIP
        publicIP = geoIP.publicIP
        ispName = geoIP.ispDisplay
    }

    // MARK: - Diagnosis v2: the ONE verdict

    /// Compose the verdict from the monitor's status, the probe failure
    /// streaks and the latest same-network speed test, then derive the status
    /// line from it. This replaces the dashboard's own health rubric, the
    /// diagnostic-root-cause string logic and the interpreter summary.
    func updateUIStatus() {
        guard !isUpdatingUIStatus else {
            debugLog("🔄 updateUIStatus skipped - already in progress")
            return
        }
        isUpdatingUIStatus = true
        defer { isUpdatingUIStatus = false }

        if isInitializing {
            connectionQuality = "Detecting..."
            return
        }

        let v = VerdictInputs.currentVerdict(status: status)
        verdict = v
        connectionQuality = v.headline
    }

    struct SimpleSummaryItem: Hashable, Identifiable {
        let id = UUID()
        let emoji: String
        let title: String
        let explanation: String
    }

    /// "What's happening": the verdict headline with its coverage line, then
    /// the top findings — what's wrong, and which action category applies.
    func generateSimpleSummary() -> [SimpleSummaryItem] {
        guard let v = verdict else {
            return [SimpleSummaryItem(emoji: "⏳", title: "Checking your connection…", explanation: "Results appear after the first checks complete.")]
        }
        var items: [SimpleSummaryItem] = []
        let stateEmoji: String
        switch v.state {
        case .working: stateEmoji = "✅"
        case .degraded: stateEmoji = "⚠️"
        case .broken: stateEmoji = "🔴"
        case .unknown: stateEmoji = "❔"
        }
        items.append(SimpleSummaryItem(emoji: stateEmoji, title: v.headline, explanation: v.coverage.line))
        for f in v.findings.prefix(3) {
            let emoji: String
            switch f.action {
            case .userFixable: emoji = "🔧"
            case .fixableElsewhere: emoji = "🏢"
            case .notFixable: emoji = "ℹ️"
            case .none: emoji = "💬"
            }
            items.append(SimpleSummaryItem(emoji: emoji, title: f.headline, explanation: "\(f.action.categoryWord). \(f.cause)"))
        }
        return items
    }


    /// Start monitoring network status
    func startMonitoring() {
        networkMonitor.startMonitoring()
    }

    /// Stop monitoring network status
    func stopMonitoring() {
        networkMonitor.stopMonitoring()
    }

    // MARK: - Computed Properties (STEP 4 Required)

    /// Wi-Fi status text
    /// STEP 4 Requirement: Dashboard Business Rule - "If Wi-Fi is off → show 'Not connected to Wi-Fi'"
    /// FIXED: Provide meaningful message when SSID is nil instead of just "Connected"
    /// FIX (Issue 1): treat "we have a local IPv4 on a private subnet" as
    /// definitive proof of WiFi connectivity, even if status.wifi.isConnected
    /// is momentarily false (timeout fallback path).
    var wifiStatusText: String {
        if isInitializing { return "Detecting..." }

        let hasPrivateIP: Bool = {
            guard let ip = status.localIP else { return false }
            return ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.")
        }()

        if !status.wifi.isConnected && !hasPrivateIP {
            return "Not connected to Wi-Fi"
        }

        if let ssid = status.wifi.ssid, !ssid.isEmpty {
            return "Connected to \(ssid)"
        }

        // Diagnose why SSID is unavailable
        #if targetEnvironment(simulator)
        return "Connected (SSID unavailable on Simulator)"
        #else
        let locStatus = LocationPermissionManager.shared.currentStatus
        switch locStatus {
        case .notDetermined:
            return "Connected (Location permission not yet requested)"
        case .denied, .restricted:
            return "Connected (Location permission denied - SSID unavailable)"
        case .authorizedWhenInUse, .authorizedAlways:
            // Permission granted but SSID still nil - entitlement or iOS issue
            return "Connected (SSID unavailable - check wifi-info entitlement)"
        @unknown default:
            return "Connected"
        }
        #endif
    }

    /// VPN status text
    /// Shows authoritative (NEVPNManager confirmed) vs inferred (ISP/geo) status
    var vpnStatusText: String {
        // FIXED: Use SmartVPNDetector as single source of truth
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        let isAuthoritative = SmartVPNDetector.shared.detectionResult?.isAuthoritative ?? false

        if !vpnActive {
            // Check if detection is in possiblyActive state
            if let result = SmartVPNDetector.shared.detectionResult,
               result.detectionStatus == .possiblyActive {
                return "VPN/Proxy Detected (inferred)"
            }
            return "No VPN"
        }

        if isAuthoritative {
            if let serverIP = status.vpn.serverIP {
                return "VPN Active (\(serverIP))"
            }
            return "VPN Active"
        }

        // Inferred VPN — show reasoning
        if let reason = status.vpn.inferenceReasons.first {
            return "VPN/Proxy (inferred: \(reason))"
        }
        return "VPN/Proxy Detected (inferred)"
    }

    /// Internet status text
    /// FIX (Phase 2): The card previously embedded a RAW latency here
    /// ("Connected (98ms)") while the Latency row below showed the SMOOTHED
    /// value ("Latency 342ms") — two contradictory numbers on one card.
    /// The status now states connectivity only; the single, smoothed,
    /// network-layer latency is shown once in the dedicated "Latency" row.
    var internetStatusText: String {
        if isInitializing { return "Detecting..." }
        return status.internet.isReachable ? "Connected" : "No Internet"
    }

    /// Signal strength description
    /// STEP 4 Requirement: Convert -65 dBm => "Good"
    var signalStrengthDescription: String {
        guard let rssi = status.wifi.rssi else { return "Unknown" }

        if rssi >= -50 {
            return "Excellent"
        } else if rssi >= -60 {
            return "Good"
        } else if rssi >= -70 {
            return "Fair"
        } else if rssi >= -80 {
            return "Weak"
        } else {
            return "Very Weak"
        }
    }

    // MARK: - Additional Computed Properties

    /// Is network connected
    var isConnected: Bool {
        status.internet.isReachable
    }

    /// Current connection type description
    var connectionTypeDescription: String {
        if let type = status.connectionType {
            // If WiFi, check if it's actually a mobile hotspot
            if type == .wifi && status.isHotspot {
                return "Mobile Hotspot"
            }
            return type.displayName
        }
        return "Unknown"
    }

    /// Gateway reachability warning
    /// STEP 4 Requirement: "If gateway unreachable → flag router problem"
    /// FIX (Issue 2/6): a successfully measured gateway latency is proof of
    /// reachability. Don't flag "router problem" just because the gatewayIP
    /// field is momentarily nil (e.g. a timeout cleared it) while the smoothed
    /// latency keeps showing a healthy reading.
    var hasRouterProblem: Bool {
        // If we have a measured (non-sentinel) latency to the gateway — even
        // smoothed from prior polls — the router is reachable.
        if status.router.displayableLatency != nil { return false }
        if smoothedGatewayLatency != nil { return false }
        // Use the hard-failure tracker to require multiple consecutive misses.
        if MeasurementValidityTracker.shared.gatewayHasHardFailure { return true }
        // Otherwise be conservative — only flag if router.health says .poor
        // (don't flag merely because gatewayIP is nil — we may still be probing).
        return status.router.health == .poor
    }

    /// Gateway IP to display. Falls back to:
    ///   1. router.gatewayIP if present
    ///   2. derived gateway from local IP (we know we measured to it)
    /// FIX (Issue 2): never display "Unknown" when we just successfully
    /// measured a latency to the gateway.
    var displayedGatewayIP: String? {
        if let gw = status.router.gatewayIP { return gw }
        // Derive from local IP — same logic NetworkMonitorService uses.
        guard let localIP = status.localIP else { return nil }
        if localIP.hasPrefix("192.168.") {
            let parts = localIP.split(separator: ".")
            guard parts.count == 4 else { return nil }
            return "192.168.\(parts[2]).1"
        }
        if localIP.hasPrefix("10.") {
            return "10.0.0.1"
        }
        if localIP.hasPrefix("172.") {
            let parts = localIP.split(separator: ".")
            guard parts.count >= 2 else { return nil }
            return "172.\(parts[1]).0.1"
        }
        return nil
    }

    /// DNS warning
    /// STEP 4 Requirement: "If DNS slow → show warning"
    var hasDNSWarning: Bool {
        if let latency = status.dns.latency {
            return latency > 100
        }
        return false
    }

    /// True when a local TUN-mode proxy/VPN intercepted the latency probe, so
    /// the dashboard must show "Via VPN/proxy" instead of a fabricated number.
    /// See LatencyInterception / InternetInfo.latencyIntercepted.
    var latencyIntercepted: Bool {
        status.internet.latencyIntercepted
    }

    /// ISP slow warning
    /// STEP 4 Requirement: "If ISP slow → downgrade connection quality"
    var hasISPWarning: Bool {
        if let latency = status.internet.latencyToExternal {
            return latency > 200
        }
        return false
    }

    // MARK: - VPN Health Calculations (FIXED: No more "Unknown")

    /// Calculate VPN overhead from actual measurements
    /// VPN overhead = External latency - Gateway latency
    /// FIXED: Check both NetworkMonitor AND SmartVPNDetector for VPN status
    var vpnOverhead: Double? {
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        guard vpnActive else { return nil }
        guard let externalLatency = status.internet.latencyToExternal,
              let gatewayLatency = status.router.latency else { return nil }

        let overhead = externalLatency - gatewayLatency
        return overhead > 0 ? overhead : nil
    }

    /// VPN health score (0-100) based on overhead, stability, and reachability
    var vpnHealthScore: Int? {
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        guard vpnActive else { return nil }

        var score = 100

        // Factor 1: Latency overhead (biggest impact)
        if let overhead = vpnOverhead {
            if overhead > 200 { score -= 45 }
            else if overhead > 150 { score -= 35 }
            else if overhead > 100 { score -= 25 }
            else if overhead > 50 { score -= 10 }
        } else if let tunnelLatency = status.vpn.tunnelLatency {
            if tunnelLatency > 200 { score -= 45 }
            else if tunnelLatency > 150 { score -= 35 }
            else if tunnelLatency > 100 { score -= 25 }
            else if tunnelLatency > 50 { score -= 10 }
        }

        // Factor 2: Packet loss
        if let loss = status.vpn.packetLoss {
            if loss > 5 { score -= 30 }
            else if loss > 2 { score -= 15 }
            else if loss > 0 { score -= 5 }
        }

        // Factor 3: Tunnel reachability
        if !status.vpn.tunnelReachable && vpnActive {
            score -= 40
        }

        // Factor 4: DNS leak (from NetworkStatus)
        if status.vpn.dnsLeakDetected {
            score -= 15
        }

        // Factor 5: Leak test results (from PrivacyShieldService)
        if let leakResult = PrivacyShieldService.shared.lastLeakTestResult,
           leakResult.overallVerdict != .noVPN {
            if leakResult.dnsLeak.isLeaking {
                score -= (leakResult.dnsLeak.severity == .critical) ? 25 : 15
            }
            if leakResult.ipLeak.isLeaking {
                score -= (leakResult.ipLeak.severity == .critical) ? 30 : 20
            }
            if leakResult.webRTCLeak.isLeaking {
                score -= (leakResult.webRTCLeak.severity == .critical) ? 25 : 15
            }
        }

        return max(0, min(100, score))
    }

    /// VPN health description based on calculated overhead
    /// FIXED: Never returns "Unknown" when VPN is active and internet works
    var vpnHealthDescription: String {
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        guard vpnActive else { return "Inactive" }

        // If we have tunnel latency directly, use it
        if let tunnelLatency = status.vpn.tunnelLatency {
            if tunnelLatency < 30 { return "Excellent" }
            if tunnelLatency < 80 { return "Good" }
            if tunnelLatency < 150 { return "Fair" }
            return "Poor"
        }

        // Calculate from overhead
        if let overhead = vpnOverhead {
            if overhead < 30 { return "Excellent" }
            if overhead < 80 { return "Good" }
            if overhead < 150 { return "Fair" }
            return "Poor"
        }

        // VPN is active but no latency data yet
        if status.internet.isReachable {
            return "Active"
        }

        return "Checking..."
    }

    /// VPN health color based on health score
    var vpnHealthColor: Color {
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        guard vpnActive else { return .gray }

        if let score = vpnHealthScore {
            if score >= 80 { return .green }
            if score >= 60 { return .blue }
            if score >= 40 { return .yellow }
            return .red
        }

        return status.internet.isReachable ? .blue : .gray
    }

    // MARK: - Error Handling (STEP 4 Required)

    func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        isLoading = false
    }

    // MARK: - Data Smoothing Methods (PART 1: Stabilize ratings)

    /// Smooth a latency value using rolling average
    private func smoothLatency(_ rawLatency: Double, history: inout [Double]) -> Double {
        history.append(rawLatency)
        if history.count > smoothingWindow {
            history.removeFirst()
        }
        return history.reduce(0, +) / Double(history.count)
    }

    /// A stable identity for the currently-connected network. A change in
    /// interface type, SSID, or /24 subnet means we are on a different network.
    private func networkIdentityKey(_ status: NetworkStatus) -> String {
        let type = status.connectionType?.displayName ?? "none"
        let ssid = status.wifi.ssid ?? "-"
        let subnet: String = {
            guard let ip = status.localIP else { return "-" }
            let parts = ip.split(separator: ".")
            return parts.count == 4 ? "\(parts[0]).\(parts[1]).\(parts[2])" : ip
        }()
        return "\(type)|\(ssid)|\(subnet)"
    }

    /// Clear the latency/health smoothing buffers when the network changes.
    /// Network switches are state changes, not measurement noise — blending
    /// the old network's samples into the new one produced the contradictory
    /// "Connected (98ms)" / "Latency 342ms" readings the audit flagged.
    private func clearSmoothingIfNetworkChanged(_ status: NetworkStatus) {
        let key = networkIdentityKey(status)
        defer { lastNetworkKey = key }
        guard let previous = lastNetworkKey, previous != key else { return }

        internetLatencyHistory.removeAll()
        gatewayLatencyHistory.removeAll()
        dnsLatencyHistory.removeAll()
        smoothedInternetLatency = nil
        smoothedGatewayLatency = nil
        smoothedDNSLatency = nil

        debugLog("[Smoothing] Network changed (\(previous) → \(key)) — cleared latency buffers")
    }

    /// Update all smoothed values from current status
    func updateSmoothedValues() {
        // Smooth internet latency
        if let rawLatency = status.internet.latencyToExternal {
            smoothedInternetLatency = smoothLatency(rawLatency, history: &internetLatencyHistory)
        }

        // Smooth gateway latency
        if let rawLatency = status.router.latency {
            smoothedGatewayLatency = smoothLatency(rawLatency, history: &gatewayLatencyHistory)
        }

        // Smooth DNS latency
        if let rawLatency = status.dns.latency {
            smoothedDNSLatency = smoothLatency(rawLatency, history: &dnsLatencyHistory)
        }

    }

    // MARK: - Simple Summary Generation (PART 2: Plain-English summary)

    // MARK: - VPN Overhead Helper for Summary

}
