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

    // MARK: - Diagnostic Root Cause Integration

    /// Last diagnostic's root cause (synced from HistoryManager)
    @Published var lastDiagnosticRootCause: String?

    /// Last diagnostic summary text
    @Published var lastDiagnosticSummary: String?

    /// Last diagnostic timestamp
    @Published var lastDiagnosticTimestamp: Date?

    /// Whether to show diagnostic root cause vs calculated status
    /// Show diagnostic root cause if it's less than 10 minutes old
    var shouldShowDiagnosticRootCause: Bool {
        guard let timestamp = lastDiagnosticTimestamp else { return false }
        let tenMinutesAgo = Date().addingTimeInterval(-600)
        return timestamp > tenMinutesAgo && lastDiagnosticRootCause != nil && lastDiagnosticRootCause != "None"
    }

    /// Human-readable time since last diagnostic
    var timeSinceLastDiagnostic: String? {
        guard let timestamp = lastDiagnosticTimestamp else { return nil }
        let interval = Date().timeIntervalSince(timestamp)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

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
    private var healthScoreHistory: [Int] = []
    private let smoothingWindow = 5  // Average of last 5 readings

    /// Hysteresis for health ratings (require 3 consecutive same readings to change)
    private var consecutiveRatingCount = 0
    private var pendingRating: NetworkHealth?
    private var confirmedRating: NetworkHealth = .fair

    /// Smoothed values for display
    @Published var smoothedInternetLatency: Double?
    @Published var smoothedGatewayLatency: Double?
    @Published var smoothedDNSLatency: Double?
    @Published var smoothedHealthScore: Int = 50
    @Published var stableOverallHealth: NetworkHealth = .fair

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

        // Observe GeoIP changes
        geoIPService.$currentGeoIP
            .receive(on: DispatchQueue.main)
            .sink { [weak self] geoIP in
                self?.geoIPInfo = geoIP
                self?.publicIP = geoIP.publicIP
                self?.ispName = geoIP.ispDisplay
            }
            .store(in: &cancellables)

        // Observe diagnostic history changes to sync root cause
        historyManager.$diagnosticHistory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] history in
                self?.syncDiagnosticRootCause(from: history)
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

    /// Sync the last diagnostic's root cause to the dashboard
    private func syncDiagnosticRootCause(from history: [DiagnosticHistoryEntry]) {
        // FIXED: Re-entry guard to prevent cascading updates
        guard !isSyncingDiagnostic else {
            debugLog("🔄 syncDiagnosticRootCause skipped - already in progress")
            return
        }
        isSyncingDiagnostic = true
        defer { isSyncingDiagnostic = false }

        guard let lastDiagnostic = history.first else {
            lastDiagnosticRootCause = nil
            lastDiagnosticSummary = nil
            lastDiagnosticTimestamp = nil
            return
        }

        lastDiagnosticTimestamp = lastDiagnostic.timestamp
        lastDiagnosticRootCause = lastDiagnostic.primaryIssueCategory
        lastDiagnosticSummary = lastDiagnostic.summary

        debugLog("📊 Dashboard synced diagnostic: \(lastDiagnostic.primaryIssueCategory) - \(lastDiagnostic.summary)")

        // Update UI to reflect the diagnostic result
        updateUIStatus()
    }

    // MARK: - Public Methods (STEP 4 Required)

    /// Refresh all network data
    /// STEP 4 Requirement: Runs all basic network checks
    /// PART 1: Only auto-refresh once on launch, then manual pull-to-refresh or every 60s max
    func refresh(forceRefresh: Bool = false) async {
        // Prevent multiple concurrent refreshes
        guard !isLoading else {
            debugLog("🔄 Dashboard refresh already in progress, skipping")
            return
        }

        // FIXED: Only auto-refresh once on launch, or when forced (pull-to-refresh)
        if !forceRefresh {
            if hasRefreshedOnLaunch {
                if let lastTime = lastRefreshTime, Date().timeIntervalSince(lastTime) < minRefreshInterval {
                    debugLog("🔄 Dashboard refresh() skipped — auto-refresh limited to once per 60s")
                    return
                }
            }
            hasRefreshedOnLaunch = true
        }
        lastRefreshTime = Date()

        debugLog("🔄 Dashboard refresh() called")
        isLoading = true

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
                    if forceRefresh {
                        await self.networkMonitor.forceRefreshVPN()
                    }

                    // Step 2: Update network status
                    await self.networkMonitor.updateNetworkStatus()

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

    /// Update UI status labels
    /// FIXED: Based ONLY on measurable metrics - no fake WiFi signal references
    /// ENHANCED: Prefers diagnostic root cause when available (within 10 minutes)
    func updateUIStatus() {
        // FIXED: Re-entry guard to prevent cascading updates
        guard !isUpdatingUIStatus else {
            debugLog("🔄 updateUIStatus skipped - already in progress")
            return
        }
        isUpdatingUIStatus = true
        defer { isUpdatingUIStatus = false }

        // Priority 0: Use diagnostic root cause if recent
        // This ensures the dashboard shows the same diagnosis as the diagnostic view
        if shouldShowDiagnosticRootCause, let rootCause = lastDiagnosticRootCause {
            connectionQuality = formatDiagnosticRootCause(rootCause)
            return
        }

        // Priority 1: No connection
        // FIX (Issue 1/4): a private LAN IP means WiFi IS up — don't fall to
        // "Not Connected", which feeds the score calculation a false signal.
        let hasPrivateIP: Bool = {
            guard let ip = status.localIP else { return false }
            return ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.")
        }()
        if !status.wifi.isConnected && !hasPrivateIP {
            connectionQuality = "Not Connected"
            return
        }

        // FIXED: Use MEASURABLE metrics to determine the primary issue
        // Priority order: VPN overhead > External latency > Gateway latency > DNS

        // FIXED: Check BOTH NetworkMonitor AND SmartVPNDetector for VPN status
        // This prevents false negatives where one detector is slower
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false

        // Check VPN overhead first (if VPN active)
        if vpnActive,
           let externalLatency = status.internet.latencyToExternal,
           let gatewayLatency = status.router.latency {
            let overhead = externalLatency - gatewayLatency
            if overhead > 150 {
                connectionQuality = "High VPN latency (\(Int(overhead))ms overhead)"
                return
            } else if overhead > 50 {
                connectionQuality = "Moderate VPN overhead (\(Int(overhead))ms)"
                return
            }
        }

        // Check external latency
        if let externalLatency = status.internet.latencyToExternal {
            if externalLatency > 200 {
                if vpnActive {
                    connectionQuality = "High latency — VPN routing"
                } else {
                    connectionQuality = "High latency — possible ISP issue"
                }
                return
            } else if externalLatency > 100 {
                connectionQuality = "Elevated latency (\(Int(externalLatency))ms)"
                return
            }
        }

        // Check gateway latency (local network)
        // FIXED: Recalibrated thresholds per Apple HIG
        // < 10ms: Excellent, 10-30ms: Good, 30-50ms: Fair, 50-100ms: Poor, >100ms: Critical
        if let gatewayLatency = status.router.latency {
            if gatewayLatency > 100 {
                connectionQuality = "Critical gateway latency (\(Int(gatewayLatency))ms)"
                return
            } else if gatewayLatency > 50 {
                connectionQuality = "Poor gateway latency (\(Int(gatewayLatency))ms)"
                return
            }
            // 30-50ms is "Fair" - not worth alarming the user about
            // 10-30ms is "Good" - no action needed
            // < 10ms is "Excellent" - no action needed
        }

        // Check packet loss
        if let packetLoss = status.router.packetLoss, packetLoss > 5 {
            connectionQuality = "Packet loss detected (\(Int(packetLoss))%)"
            return
        }

        // Check DNS
        if let dnsLatency = status.dns.latency, dnsLatency > 100 {
            connectionQuality = "Slow DNS (\(Int(dnsLatency))ms)"
            return
        }

        // All good
        if status.internet.isReachable {
            connectionQuality = "Good"
        } else {
            connectionQuality = "No Internet"
        }
    }

    /// Format the diagnostic root cause for dashboard display
    /// ENHANCED: Includes specific metrics when available
    private func formatDiagnosticRootCause(_ category: String) -> String {
        switch category {
        case "VPN":
            // Include VPN overhead if available
            if let overhead = vpnOverhead {
                return "VPN Slow (\(Int(overhead))ms overhead) — Try closer server"
            }
            return "VPN Slow — Try a closer server"
        case "ISP":
            return "ISP Congestion — Not a local network issue"
        case "Router":
            // Include gateway latency if available
            if let gatewayLatency = status.router.latency {
                return "Router Slow (\(Int(gatewayLatency))ms) — Try restarting"
            }
            return "Router Issue — Try restarting"
        case "Wi-Fi":
            return "Wi-Fi Issue — Move closer to router"
        case "DNS":
            // Include DNS latency if available
            if let dnsLatency = status.dns.latency {
                return "DNS Slow (\(Int(dnsLatency))ms) — Switch to 1.1.1.1"
            }
            return "DNS Slow — Switch to 1.1.1.1 or 8.8.8.8"
        case "Streaming":
            return "Streaming Issue — CDN routing problem"
        case "CDN":
            return "CDN Issue — Server distance"
        case "Device":
            return "Device Issue — Check settings"
        case "None":
            return "Good"
        default:
            return "Issue Detected"
        }
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
    var internetStatusText: String {
        if status.internet.isReachable {
            if let latency = status.internet.latencyToExternal {
                return "Connected (\(Int(latency))ms)"
            }
            return "Connected"
        }

        return "No Internet"
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

    /// Overall network health status
    var overallHealth: NetworkHealth {
        status.overallHealth
    }

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

        // Smooth health score
        let rawScore = calculateRawHealthScore()
        healthScoreHistory.append(rawScore)
        if healthScoreHistory.count > smoothingWindow {
            healthScoreHistory.removeFirst()
        }
        smoothedHealthScore = healthScoreHistory.reduce(0, +) / healthScoreHistory.count

        // Apply hysteresis to health rating
        stableOverallHealth = updateHealthRating(from: smoothedHealthScore)
    }

    /// Calculate raw health score (0-100) from current metrics.
    /// FIX (Phase 5): kept in lockstep with RootCauseAnalyzer.calculateHealthScore()
    /// so Quick Check and the Dashboard report the same number for the same inputs.
    /// See RootCauseAnalyzer for the rubric and worked examples.
    private func calculateRawHealthScore() -> Int {
        var score = 100
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false

        // Router latency (-15 max)
        if let latency = status.router.displayableLatency {
            if latency > 100 { score -= 15 }
            else if latency > 60 { score -= 10 }
            else if latency > 30 { score -= 5 }
            else if latency > 10 { score -= 2 }
        }

        // Internet latency — VPN-aware (matches RootCauseAnalyzer).
        if let latency = status.internet.displayableLatency {
            if vpnActive {
                if latency > 800 { score -= 45 }
                else if latency > 600 { score -= 35 }
                else if latency > 400 { score -= 28 }
                else if latency > 250 { score -= 18 }
                else if latency > 100 { score -= 10 }
            } else {
                if latency > 400 { score -= 50 }
                else if latency > 300 { score -= 45 }
                else if latency > 200 { score -= 40 }
                else if latency > 150 { score -= 30 }
                else if latency > 100 { score -= 20 }
                else if latency > 80 { score -= 12 }
                else if latency > 50 { score -= 5 }
            }
        }

        // VPN overhead — counted ONCE. <150ms = normal, no penalty.
        if vpnActive,
           let internetLatency = status.internet.displayableLatency,
           let routerLatency = status.router.displayableLatency {
            let overhead = internetLatency - routerLatency
            if overhead > 450 { score -= 20 }
            else if overhead > 300 { score -= 10 }
            else if overhead > 150 { score -= 5 }
        }

        // Packet loss
        if let loss = status.router.packetLoss, loss > 0 {
            score -= Int(loss * 5)
        }

        // DNS latency (-10 max)
        if let latency = status.dns.displayableLatency {
            if latency > 300 { score -= 10 }
            else if latency > 200 { score -= 7 }
            else if latency > 100 { score -= 5 }
            else if latency > 50 { score -= 3 }
            else if latency > 20 { score -= 1 }
        }

        // Critical failures only count after confirmed hard failures.
        let validity = MeasurementValidityTracker.shared
        if validity.gatewayHasHardFailure { score -= 40 }
        if validity.externalHasHardFailure && !status.internet.isReachable { score -= 40 }
        if validity.dnsHasHardFailure { score -= 20 }

        return max(0, min(100, score))
    }

    /// Apply hysteresis to health rating (require 3 consecutive same readings)
    private func updateHealthRating(from score: Int) -> NetworkHealth {
        let newRating: NetworkHealth
        if score >= 70 {
            newRating = .excellent
        } else if score >= 40 {
            newRating = .fair
        } else {
            newRating = .poor
        }

        // Check if rating is same as pending
        if newRating == pendingRating {
            consecutiveRatingCount += 1
        } else {
            pendingRating = newRating
            consecutiveRatingCount = 1
        }

        // Only change displayed rating after 3 consecutive same readings
        if consecutiveRatingCount >= 3 {
            confirmedRating = newRating
        }

        return confirmedRating
    }

    // MARK: - Simple Summary Generation (PART 2: Plain-English summary)

    struct SimpleSummaryItem: Hashable, Identifiable {
        let id = UUID()
        let emoji: String
        let title: String
        let explanation: String
    }

    /// Generate plain-English summary for the home screen
    /// STEP 3: Prefer NetworkInterpreter's summary when available (single source of truth)
    func generateSimpleSummary() -> [SimpleSummaryItem] {
        // SINGLE SOURCE OF TRUTH: If NetworkInterpreter has recent data, use it
        if let interpretation = NetworkInterpreter.shared.current,
           let lastInterpretedAt = NetworkInterpreter.shared.lastInterpretedAt,
           Date().timeIntervalSince(lastInterpretedAt) < 300 {  // < 5 minutes old
            // Convert interpreter's SummaryItem to our SimpleSummaryItem
            return interpretation.summaryItems.map { item in
                SimpleSummaryItem(
                    emoji: item.emoji,
                    title: item.title,
                    explanation: item.explanation
                )
            }
        }

        // Fallback: Generate our own summary if no interpreter data
        var items: [SimpleSummaryItem] = []

        // 1. Overall status - always show
        let score = smoothedHealthScore
        if score >= 70 {
            items.append(SimpleSummaryItem(
                emoji: "✅",
                title: "Your internet is working well",
                explanation: "Everything looks good. Browsing, streaming, and video calls should work fine."
            ))
        } else if score >= 40 {
            items.append(SimpleSummaryItem(
                emoji: "⚠️",
                title: "Your internet is okay but slow",
                explanation: "Basic browsing works, but videos might buffer and video calls could be choppy."
            ))
        } else {
            items.append(SimpleSummaryItem(
                emoji: "🔴",
                title: "Your internet has problems",
                explanation: "You'll likely notice slow loading, buffering, and dropped connections."
            ))
        }

        // 2. VPN status - explain what it means (authoritative vs inferred)
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        let vpnAuthoritative = SmartVPNDetector.shared.detectionResult?.isAuthoritative ?? false

        if vpnActive {
            let overhead = vpnOverhead ?? 0
            let authLabel = vpnAuthoritative ? "" : " (inferred)"
            if overhead > 200 {
                items.append(SimpleSummaryItem(
                    emoji: "🐢",
                    title: "VPN is slowing you down a lot\(authLabel)",
                    explanation: "Your VPN adds \(Int(overhead))ms delay. Try switching to a closer server in your VPN app."
                ))
            } else if overhead > 100 {
                let location = status.vpn.serverLocation ?? geoIPInfo.displayLocation
                items.append(SimpleSummaryItem(
                    emoji: "🔒",
                    title: vpnAuthoritative ? "VPN is on with some slowdown" : "VPN/Proxy detected (inferred)",
                    explanation: vpnAuthoritative
                        ? "Your VPN adds \(Int(overhead))ms delay. This is normal — your traffic is being routed through \(location)."
                        : "We detected a VPN/proxy based on your IP provider. Adds \(Int(overhead))ms delay."
                ))
            } else {
                items.append(SimpleSummaryItem(
                    emoji: "🔒",
                    title: vpnAuthoritative ? "VPN is working great" : "VPN/Proxy detected (inferred)",
                    explanation: vpnAuthoritative
                        ? "Your VPN is connected with minimal slowdown. Nice setup!"
                        : "We detected a VPN/proxy based on your IP provider (\(status.vpn.ispName ?? "unknown")). Connection looks good."
                ))
            }
        } else if let result = SmartVPNDetector.shared.detectionResult,
                  result.detectionStatus == .possiblyActive {
            // Possibly active but not confirmed
            let reasons = result.inferenceReasons.joined(separator: "; ")
            items.append(SimpleSummaryItem(
                emoji: "🔍",
                title: "Possible VPN/Proxy detected",
                explanation: reasons.isEmpty
                    ? "Some network signals suggest a VPN or proxy may be active."
                    : reasons
            ))
        }

        // 3. WiFi quality (only when VPN is NOT active)
        if !vpnActive {
            if let gatewayLatency = smoothedGatewayLatency ?? status.router.latency {
                if gatewayLatency > 100 {
                    items.append(SimpleSummaryItem(
                        emoji: "📶",
                        title: "Weak WiFi signal",
                        explanation: "Your router responds in \(Int(gatewayLatency))ms (should be under 10ms). Move closer to your router or reduce devices on this network."
                    ))
                } else if gatewayLatency > 30 {
                    items.append(SimpleSummaryItem(
                        emoji: "📶",
                        title: "WiFi could be better",
                        explanation: "Your router responds in \(Int(gatewayLatency))ms. Try moving closer to your router."
                    ))
                }
            } else if !status.router.isReachable {
                items.append(SimpleSummaryItem(
                    emoji: "📶",
                    title: "Can't reach your router",
                    explanation: "Your WiFi connection to the router seems unstable. Try restarting your router."
                ))
            }
        }

        // 4. DNS warning
        if let dnsLatency = smoothedDNSLatency ?? status.dns.latency, dnsLatency > 150 {
            items.append(SimpleSummaryItem(
                emoji: "🔍",
                title: "Slow DNS (website lookup)",
                explanation: "Finding websites takes \(Int(dnsLatency))ms. Changing your DNS to 1.1.1.1 or 8.8.8.8 in your device settings could speed things up."
            ))
        }

        // 5. What you can do about it
        if score < 70 {
            let topAction = getTopAction()
            items.append(SimpleSummaryItem(
                emoji: "💡",
                title: topAction.title,
                explanation: topAction.explanation
            ))
        }

        return items
    }

    struct ActionItem {
        let title: String
        let explanation: String
    }

    private func getTopAction() -> ActionItem {
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false

        // Prioritize the most impactful fix
        if vpnActive {
            let overhead = vpnOverhead ?? 0
            if overhead > 200 {
                return ActionItem(
                    title: "Try a faster VPN server",
                    explanation: "Open your VPN app and switch to a server closer to you. This is the #1 thing that will speed up your internet right now."
                )
            }
        }

        if let gatewayLatency = status.router.latency, gatewayLatency > 50, !vpnActive {
            return ActionItem(
                title: "Move closer to your WiFi router",
                explanation: "Your WiFi signal is weak. Moving closer to the router or removing obstacles between you and the router will help."
            )
        }

        if let dnsLatency = status.dns.latency, dnsLatency > 150 {
            return ActionItem(
                title: "Switch to a faster DNS",
                explanation: "Go to Settings → WiFi → tap your network → Configure DNS → Manual → add 1.1.1.1 as the first server."
            )
        }

        return ActionItem(
            title: "Your internet is a bit slow today",
            explanation: "This might be temporary. Try again in a few minutes, or restart your router if it continues."
        )
    }

    // MARK: - VPN Overhead Helper for Summary

    /// Calculate VPN overhead for simple summary
    func calculateVPNOverhead() -> Double {
        return vpnOverhead ?? 0
    }
}
