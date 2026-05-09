//
//  VPNEngine.swift
//  NetoSensei
//
//  VPN detection and health monitoring engine
//  Uses SmartVPNDetector with multi-method confidence scoring
//

import Foundation

@MainActor
class VPNEngine: ObservableObject {
    static let shared = VPNEngine()

    @Published var isVPNActive = false
    @Published var isMonitoring = false
    @Published var lastHealthCheck: Date?
    @Published var healthCheckResult: VPNHealthResult?

    nonisolated(unsafe) private var healthCheckTimer: Timer?

    struct VPNHealthResult {
        var isHealthy: Bool
        var tunnelActive: Bool
        var tunnelReachable: Bool
        var packetLoss: Double?
        var latency: Double?
        var issues: [String]
        var recommendations: [String]
    }

    private init() {
        Task {
            await refreshVPNStatus()
        }
    }

    // MARK: - VPN Status

    func refreshVPNStatus() async {
        let result = await SmartVPNDetector.shared.detectVPN()
        // FIXED: Only set VPN as active if confidence >= 80% (handled by SmartVPNDetector)
        isVPNActive = result.isVPNActive
    }

    // MARK: - Auto-Recovery Monitoring

    func startAutoRecovery() {
        guard !isMonitoring else { return }
        isMonitoring = true

        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performHealthCheck()
            }
        }

        Task {
            await performHealthCheck()
        }
    }

    func stopAutoRecovery() {
        isMonitoring = false
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    deinit {
        healthCheckTimer?.invalidate()
    }

    // MARK: - Health Check

    func performHealthCheck() async -> VPNHealthResult {
        await refreshVPNStatus()

        var issues: [String] = []
        var recommendations: [String] = []

        guard isVPNActive else {
            let result = VPNHealthResult(
                isHealthy: false,
                tunnelActive: false,
                tunnelReachable: false,
                issues: ["VPN is not active"],
                recommendations: ["Connect to VPN"]
            )
            healthCheckResult = result
            lastHealthCheck = Date()
            return result
        }

        let (tunnelReachable, latency) = await testTunnelReachability()

        if !tunnelReachable {
            issues.append("VPN tunnel is active but not passing traffic")
            recommendations.append("Reconnect VPN or switch servers")
        }

        let packetLoss = await testPacketLoss()

        if let loss = packetLoss, loss > 5 {
            issues.append("High packet loss: \(String(format: "%.1f", loss))%")
            recommendations.append("Switch to a different VPN server")
        }

        if let lat = latency, lat > 150 {
            issues.append("High VPN latency: \(String(format: "%.0f", lat))ms")
            recommendations.append("Connect to a closer server")
        }

        let result = VPNHealthResult(
            isHealthy: issues.isEmpty,
            tunnelActive: true,
            tunnelReachable: tunnelReachable,
            packetLoss: packetLoss,
            latency: latency,
            issues: issues,
            recommendations: recommendations
        )

        healthCheckResult = result
        lastHealthCheck = Date()
        return result
    }

    private func testTunnelReachability() async -> (Bool, Double?) {
        // CLEANUP 4: apple.com instead of cloudflare-dns.com (China reliability)
        return await NetworkMonitorService.shared.pingHost("apple.com", timeout: 5.0)
    }

    private func testPacketLoss() async -> Double? {
        // Race 3 probe targets per iteration so one VPN-blocked host doesn't poison the metric.
        // Real packet loss affects ALL targets simultaneously; only count loss when all 3 fail.
        let targets = ["apple.com", "1.1.1.1", "www.baidu.com"]
        var successCount = 0
        let totalPings = 3

        for _ in 0..<totalPings {
            async let r1 = NetworkMonitorService.shared.pingHost(targets[0], timeout: 2.0)
            async let r2 = NetworkMonitorService.shared.pingHost(targets[1], timeout: 2.0)
            async let r3 = NetworkMonitorService.shared.pingHost(targets[2], timeout: 2.0)
            let results = await [r1, r2, r3]
            if results.contains(where: { $0.0 == true }) {
                successCount += 1
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        return Double(totalPings - successCount) / Double(totalPings) * 100
    }

    // MARK: - VPN Information

    private var cachedVPNInfo: VPNInfo?
    private var lastVPNInfoFetch: Date?

    func getVPNInfo() async -> VPNInfo {
        // Return cache if fresh (within 5 seconds for real-time accuracy)
        if let cached = cachedVPNInfo,
           let lastFetch = lastVPNInfoFetch,
           Date().timeIntervalSince(lastFetch) < 5 {
            return cached
        }

        // Check SmartVPNDetector's cached result
        if let cached = SmartVPNDetector.shared.detectionResult {
            let resultAge = Date().timeIntervalSince(cached.timestamp)
            if resultAge < 5 {
                let result = buildVPNInfo(from: cached)
                cachedVPNInfo = result
                lastVPNInfoFetch = Date()
                return result
            }
        }

        // Run fresh detection
        let smartResult = await SmartVPNDetector.shared.detectVPN()
        let result = buildVPNInfo(from: smartResult)
        cachedVPNInfo = result
        lastVPNInfoFetch = Date()
        return result
    }

    /// Force-clear cache so next call runs fresh detection
    func invalidateCache() {
        cachedVPNInfo = nil
        lastVPNInfoFetch = nil
    }

    private func buildVPNInfo(from detection: SmartVPNDetector.VPNDetectionResult) -> VPNInfo {
        let serverLocation: String?
        if detection.isVPNActive {
            let city = detection.publicCity ?? ""
            let country = detection.publicCountry ?? ""
            if !city.isEmpty && !country.isEmpty {
                serverLocation = "\(city), \(country)"
            } else if !country.isEmpty {
                serverLocation = country
            } else {
                serverLocation = nil
            }
        } else {
            serverLocation = nil
        }

        return VPNInfo(
            isActive: detection.isVPNActive,
            tunnelType: detection.vpnProtocol ?? (detection.isVPNActive ? "VPN" : nil),
            vpnProtocol: detection.vpnProtocol,
            serverLocation: serverLocation,
            serverIP: detection.publicIP,
            tunnelReachable: detection.isVPNActive,
            detectionConfidence: detection.confidence,
            detectionMethods: detection.methodResults.filter { $0.detected }.map { $0.method },
            ipType: detection.ipType,
            ispName: detection.publicISP,
            displayLabel: detection.displayLabel,
            isAuthoritative: detection.isAuthoritative,
            inferenceReasons: detection.inferenceReasons,
            vpnState: detection.vpnState
        )
    }

    // MARK: - VPN Control (Stub Methods)

    func disconnectVPN() {
        debugLog("VPN disconnect not available - use your VPN app to disconnect")
    }

    func reconnectVPN() async {
        debugLog("VPN reconnect not available - use your VPN app to reconnect")
        await refreshVPNStatus()
    }

    func connectVPN() async {
        debugLog("VPN connect not available - use your VPN app to connect")
    }

    // MARK: - Recovery Guidance

    func getRecoveryGuidance() -> [String] {
        guard let result = healthCheckResult, !result.isHealthy else {
            return ["VPN is working normally"]
        }

        var guidance: [String] = []

        if !result.tunnelActive {
            guidance.append("1. Open your VPN app")
            guidance.append("2. Connect to a VPN server")
            guidance.append("3. Wait for connection to establish")
        } else if !result.tunnelReachable {
            guidance.append("1. Disconnect from VPN")
            guidance.append("2. Wait 5 seconds")
            guidance.append("3. Reconnect to VPN")
            guidance.append("4. Try a different server if issue persists")
        } else if let loss = result.packetLoss, loss > 5 {
            guidance.append("1. Open your VPN app")
            guidance.append("2. Switch to a different server")
            guidance.append("3. Prefer servers geographically closer to you")
        } else if let lat = result.latency, lat > 150 {
            guidance.append("1. Open your VPN app")
            guidance.append("2. Connect to a server closer to your location")
            guidance.append("3. Avoid servers with high load indicators")
        }

        return guidance
    }
}
