//
//  NetworkMonitorService.swift
//  NetoSensei
//
//  Production-ready network monitoring service
//  FIXED: Proper isolation, timeouts, iOS-only APIs
//

import Foundation
import Network
import SystemConfiguration.CaptiveNetwork
import NetworkExtension
import Combine


@MainActor
class NetworkMonitorService: ObservableObject {
    static let shared = NetworkMonitorService()

    @Published var currentStatus: NetworkStatus = .empty
    @Published var isMonitoring = false

    // FIXED: Prevent update accumulation when updates take longer than interval
    private var isUpdating = false

    // FIXED: NWPathMonitor cannot be restarted after cancel, so we create new ones as needed
    // Using nonisolated(unsafe) to allow access from nonisolated methods
    nonisolated(unsafe) private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.netosensei.networkmonitor", qos: .utility)
    // Using nonisolated(unsafe) to allow cleanup in deinit
    nonisolated(unsafe) private var updateTimer: Timer?

    // ISSUE 1 FIX: State-diff check — only run full update when something changed
    private var lastPathDescription: String = ""
    private var lastSSID: String?

    // ISSUE 2 FIX: Cache CNCopyCurrentNetworkInfo failure so we skip straight to NEHotspotNetwork
    nonisolated(unsafe) private static var cncopyAvailable: Bool? = nil  // nil = not tested yet

    // Helper to safely get current path from any isolation context
    nonisolated private var currentPath: Network.NWPath? {
        monitor?.currentPath
    }

    private init() {}

    deinit {
        updateTimer?.invalidate()
        monitor?.cancel()
    }

    // MARK: - Location Permission Helper

    /// Safely get WiFi SSID/BSSID - tries CNCopyCurrentNetworkInfo first, then NEHotspotNetwork
    /// ISSUE 2 FIX: Caches CNCopy failure to skip straight to NEHotspotNetwork on subsequent calls
    nonisolated private func getWiFiInfoSafely() -> (ssid: String?, bssid: String?) {
        // Check if location services are enabled at system level
        guard LocationPermissionManager.shared.isLocationEnabled else {
            return (nil, nil)
        }

        // Check location authorization status (cached, no main-thread warning)
        let status = LocationPermissionManager.shared.currentStatus

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            // ISSUE 2 FIX: If CNCopy already known to fail, skip it entirely
            if Self.cncopyAvailable == false {
                return (nil, nil)  // Caller will use NEHotspotNetwork fallback
            }

            // Method 1: CNCopyCurrentNetworkInfo (requires wifi-info entitlement)
            if let interfaces = CNCopySupportedInterfaces() as? [String] {
                for interface in interfaces {
                    if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any] {
                        let ssid = info[kCNNetworkInfoKeySSID as String] as? String
                        let bssid = info[kCNNetworkInfoKeyBSSID as String] as? String
                        if ssid != nil {
                            Self.cncopyAvailable = true
                            return (ssid, bssid)
                        }
                    }
                }
            }

            // CNCopy failed — mark unavailable so we never retry
            if Self.cncopyAvailable == nil {
                Self.cncopyAvailable = false
                debugLog("[WiFi] CNCopyCurrentNetworkInfo unavailable (missing wifi-info entitlement) — using NEHotspotNetwork only")
            }
            return (nil, nil)
        case .notDetermined, .restricted, .denied:
            return (nil, nil)
        @unknown default:
            return (nil, nil)
        }
    }

    /// Async alternative: Use NEHotspotNetwork for SSID and signal strength when CNCopy fails
    nonisolated func getSSIDViaHotspotNetwork() async -> (ssid: String?, signalStrength: Double?) {
        await withCheckedContinuation { continuation in
            if #available(iOS 14.0, *) {
                NEHotspotNetwork.fetchCurrent { network in
                    continuation.resume(returning: (network?.ssid, network?.signalStrength))
                }
            } else {
                continuation.resume(returning: (nil, nil))
            }
        }
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // FIXED: Create a new monitor each time since cancelled monitors cannot be restarted
        let newMonitor = NWPathMonitor()
        self.monitor = newMonitor

        // NWPathMonitor fires on actual network changes — triggers immediate full update
        newMonitor.pathUpdateHandler = { [weak self] path in
            let desc = path.debugDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Only run full update if the path actually changed
                if desc != self.lastPathDescription {
                    self.lastPathDescription = desc
                    debugLog("[Network] Path changed — running full update")
                    await self.performUpdate()
                }
            }
        }
        newMonitor.start(queue: monitorQueue)

        // ISSUE 1 FIX: Reduced from 2s → 30s. NWPathMonitor handles instant changes;
        // this timer is only for periodic refresh of latency/quality metrics.
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performUpdate()
            }
        }

        Task {
            await performUpdate()
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        monitor?.cancel()
        monitor = nil
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Status Update (Non-blocking)

    private func performUpdate() async {
        // FIXED: Prevent update accumulation - skip if previous update still running
        guard !isUpdating else {
            // ISSUE 10 FIX: Only log this once per burst, not every skip
            return
        }
        isUpdating = true
        defer { isUpdating = false }

        // Run all checks in parallel with individual timeouts
        let status = await buildStatus()
        self.currentStatus = status
    }

    nonisolated private func buildStatus() async -> NetworkStatus {
        // FIXED: Enforce actual timeout with Task.withTimeout pattern
        // Use shorter timeout on cellular for faster response
        guard let currentMonitor = monitor else {
            return NetworkStatus.empty
        }
        let path = currentMonitor.currentPath
        let isCellular = path.usesInterfaceType(.cellular)
        let maxTimeout: UInt64 = isCellular ? 5_000_000_000 : 8_000_000_000 // 5s cellular, 8s WiFi

        // Run with enforced timeout
        do {
            return try await withThrowingTaskGroup(of: NetworkStatus.self) { group in
                // Main task
                group.addTask {
                    async let wifi = self.getWiFi()
                    async let router = self.getRouter()
                    async let internet = self.getInternet()
                    async let dns = self.getDNS()
                    async let vpn = self.getVPN()

                    let results = await (wifi, router, internet, dns, vpn)

                    return NetworkStatus(
                        timestamp: Date(),
                        wifi: results.0,
                        router: results.1,
                        internet: results.2,
                        dns: results.3,
                        vpn: results.4,
                        publicIP: nil,
                        localIP: self.getLocalIP(),
                        ipv6Address: nil,
                        isCGNAT: false,
                        isProxyDetected: false,
                        isIPv4Enabled: true,
                        isIPv6Enabled: self.currentPath?.supportsIPv6 ?? false,
                        connectionType: self.getCurrentInterface(),
                        isHotspot: self.isConnectedToHotspot()
                    )
                }

                // Timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: maxTimeout)
                    throw TimeoutError.timedOut
                }

                // Return first result (either success or timeout)
                // FIXED: Safe unwrap instead of force unwrap
                guard let result = try await group.next() else {
                    group.cancelAll()
                    throw TimeoutError.timedOut
                }
                group.cancelAll()
                return result
            }
        } catch {
            // Timeout/error: return best-effort status using SYNCHRONOUS checks.
            // Do NOT clobber WiFi/router with sentinel "disconnected" values when we can
            // verify connectivity locally — that's what cascaded into the false-negative
            // dashboard ("Not connected to Wi-Fi", "Gateway: Unknown", etc.).
            let localIP = getLocalIP()
            let nwPathSaysWiFi = currentPath?.usesInterfaceType(NWInterface.InterfaceType.wifi) ?? false
            let en0HasIP = hasIPOnInterface(named: "en0")
            let wifiConnected = nwPathSaysWiFi || en0HasIP
            let estimatedGateway = estimateGateway()

            return NetworkStatus(
                timestamp: Date(),
                wifi: WiFiInfo(isConnected: wifiConnected),
                router: RouterInfo(gatewayIP: estimatedGateway, isReachable: estimatedGateway != nil),
                internet: InternetInfo(
                    isReachable: wifiConnected,
                    externalPingSuccess: false,
                    latencyToExternal: nil,
                    httpTestSuccess: false,
                    cdnReachable: false
                ),
                // FIX: nil latency, NOT 999 sentinel. The UI must distinguish
                // "test failed/not run" from "999ms result".
                dns: DNSInfo(resolverIP: nil, latency: nil, lookupSuccess: false),
                vpn: VPNInfo(),
                publicIP: nil,
                localIP: localIP,
                ipv6Address: nil,
                isCGNAT: false,
                isProxyDetected: false,
                isIPv4Enabled: true,
                isIPv6Enabled: currentPath?.supportsIPv6 ?? false,
                connectionType: getCurrentInterface(),
                isHotspot: false
            )
        }
    }

    enum TimeoutError: Error {
        case timedOut
    }

    // MARK: - WiFi Check (iOS-safe)
    // FIXED: NO FAKE DATA - iOS has NO public API for RSSI, channel, linkSpeed, etc.
    // Only return what we can actually measure: SSID, BSSID, and connection state

    nonisolated private func getWiFi() async -> WiFiInfo {
        // Check connection type first
        guard let path = currentPath else {
            return WiFiInfo(isConnected: false)
        }
        let nwPathSaysWiFi = path.status == .satisfied && path.usesInterfaceType(NWInterface.InterfaceType.wifi)
        let en0HasIPEarly = hasIPOnInterface(named: "en0")

        // FIX (Issue 1): Don't short-circuit to "WiFi disconnected" just because the
        // primary path is cellular. iPhones can be on cellular AND associated with WiFi
        // at the same time. Only short-circuit when we're SURE there is no WiFi —
        // i.e. NWPath doesn't list WiFi AND en0 has no IP.
        if !nwPathSaysWiFi && !en0HasIPEarly {
            return WiFiInfo(isConnected: false)
        }

        // Method 1: CNCopyCurrentNetworkInfo
        var (ssid, bssid) = getWiFiInfoSafely()

        // Always call NEHotspotNetwork to get signal strength (and SSID as fallback)
        let hotspotResult = await getSSIDViaHotspotNetwork()
        let signalStrength = hotspotResult.signalStrength

        // Method 2: If SSID is nil despite permission, use NEHotspotNetwork SSID
        if ssid == nil {
            if let hs = hotspotResult.ssid {
                ssid = hs
            }
        }

        // ISSUE 2 FIX: Only log when SSID changes
        let previousSSID = await MainActor.run { self.lastSSID }
        if ssid != previousSSID {
            let source = Self.cncopyAvailable == true ? "CNCopy" : "NEHotspotNetwork"
            debugLog("[WiFi] SSID: \(ssid ?? "none") (via \(source))")
            await MainActor.run { self.lastSSID = ssid }
        }

        // FIX (Issue 1): WiFi is connected if ANY of these is true:
        //   - NWPath reports WiFi as the active interface
        //   - The en0 interface has an IPv4 address assigned
        //   - We were able to read the SSID
        // Reusing en0HasIPEarly from above (recomputing would just re-walk getifaddrs).
        let isConnected = nwPathSaysWiFi || en0HasIPEarly || ssid != nil

        // Record signal strength sample for tracking
        if let strength = signalStrength {
            await SignalStrengthTracker.shared.recordSample(strength: strength, ssid: ssid)
        }

        return WiFiInfo(
            ssid: ssid,
            bssid: bssid,
            rssi: nil,
            noise: nil,
            linkSpeed: nil,
            channel: nil,
            channelWidth: nil,
            band: nil,
            phyMode: nil,
            mcsIndex: nil,
            nss: nil,
            isConnected: isConnected,
            signalStrength: signalStrength
        )
    }

    /// Check if a named interface has an IPv4 address assigned
    nonisolated private func hasIPOnInterface(named targetName: String) -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee,
                  let addr = interface.ifa_addr else { continue }

            let family = addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)

            if name == targetName && family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                        &hostname, socklen_t(hostname.count),
                                        nil, 0, NI_NUMERICHOST)
                if result == 0 {
                    let ip = String(cString: hostname)
                    if !ip.isEmpty && ip != "0.0.0.0" {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - Router Check (iOS-safe, median of 5 pings, outlier rejection)

    nonisolated private func getRouter() async -> RouterInfo {
        guard let path = currentPath else {
            return RouterInfo(gatewayIP: nil, isReachable: false)
        }
        if path.usesInterfaceType(NWInterface.InterfaceType.cellular) {
            return RouterInfo(gatewayIP: nil, isReachable: false)
        }

        let gatewayIP = estimateGateway()
        guard let gateway = gatewayIP else {
            return RouterInfo(gatewayIP: nil, isReachable: false)
        }

        // FIXED: Measure 5 times, take median, discard outliers (>3x median)
        var latencies: [Double] = []
        var successCount = 0
        let pingCount = 5

        for _ in 0..<pingCount {
            let (ok, lat) = await safePing(host: gateway, timeout: 1.0)
            if ok, let l = lat {
                latencies.append(l)
                successCount += 1
            }
        }

        guard !latencies.isEmpty else {
            return RouterInfo(gatewayIP: gateway, isReachable: false)
        }

        // Sort and take median
        latencies.sort()
        let median = latencies[latencies.count / 2]

        // Discard outliers (>3x median) and recalculate
        let filtered = latencies.filter { $0 <= median * 3.0 }
        let finalLatency = filtered.isEmpty ? median : filtered[filtered.count / 2]

        // Compute jitter from filtered samples
        var jitter: Double? = nil
        if filtered.count >= 2 {
            let avg = filtered.reduce(0, +) / Double(filtered.count)
            let variance = filtered.map { pow($0 - avg, 2) }.reduce(0, +) / Double(filtered.count)
            jitter = sqrt(variance)
        }

        // Detect router admin panel availability
        let adminURL = await detectRouterAdminURL(gateway: gateway)

        return RouterInfo(
            gatewayIP: gateway,
            isReachable: true,
            latency: finalLatency,
            packetLoss: Double(pingCount - successCount) / Double(pingCount) * 100.0,
            jitter: jitter,
            adminURL: adminURL
        )
    }

    /// Check if the gateway has a web admin panel on port 80 or 443
    nonisolated private func detectRouterAdminURL(gateway: String) async -> String? {
        // Try HTTPS first (port 443), then HTTP (port 80)
        for (port, scheme) in [(UInt16(443), "https"), (UInt16(80), "http")] {
            let reachable = await checkTCPPort(host: gateway, port: port, timeout: 1.0)
            if reachable {
                return "\(scheme)://\(gateway)"
            }
        }
        return nil
    }

    /// Quick TCP port check
    nonisolated private func checkTCPPort(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let socketFD = socket(AF_INET, SOCK_STREAM, 0)
                guard socketFD >= 0 else {
                    continuation.resume(returning: false)
                    return
                }

                var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
                setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                inet_pton(AF_INET, host, &addr.sin_addr)

                let connectResult = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                close(socketFD)
                continuation.resume(returning: connectResult == 0)
            }
        }
    }

    // MARK: - Detailed Router Measurement (for snapshots)

    nonisolated func measureRouterDetailed() async -> RouterInfo {
        let gatewayIP = estimateGateway()

        guard let gateway = gatewayIP else {
            return RouterInfo(gatewayIP: nil, isReachable: false)
        }

        // Perform multiple pings to measure jitter and packet loss
        let pingCount = 10
        var latencies: [Double] = []
        var successfulPings = 0

        for _ in 0..<pingCount {
            let (reachable, latency) = await safePing(host: gateway, timeout: 0.5)
            if reachable, let lat = latency {
                latencies.append(lat)
                successfulPings += 1
            }
        }

        // Calculate statistics
        let avgLatency: Double? = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)
        let packetLoss: Double? = Double(pingCount - successfulPings) / Double(pingCount) * 100.0

        // Calculate jitter (standard deviation of latency)
        var jitter: Double? = nil
        if latencies.count >= 2, let avg = avgLatency {
            let variance = latencies.map { pow($0 - avg, 2) }.reduce(0, +) / Double(latencies.count)
            jitter = sqrt(variance)
        }

        return RouterInfo(
            gatewayIP: gateway,
            isReachable: successfulPings > 0,
            latency: avgLatency,
            packetLoss: packetLoss,
            jitter: jitter
        )
    }

    // MARK: - Internet Check (iOS-safe, China-aware)

    nonisolated private func getInternet() async -> InternetInfo {
        let path = currentPath
        let isCellular = path?.usesInterfaceType(NWInterface.InterfaceType.cellular) ?? false
        let timeout: TimeInterval = isCellular ? 2.0 : 3.0

        // FIXED: China-aware latency target
        // If user is in China without VPN, ping domestic servers for meaningful latency
        // Otherwise use Cloudflare (works globally, including through VPN)
        let isInChina = await MainActor.run {
            SmartVPNDetector.shared.detectionResult?.isLikelyInChina ?? false
        }
        let vpnActive = await MainActor.run {
            SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        }

        let pingHost: String
        if isInChina && !vpnActive {
            // China without VPN: use domestic server for accurate latency
            pingHost = "www.baidu.com"
        } else {
            // Outside China or VPN active: use Cloudflare
            pingHost = "cloudflare-dns.com"
        }

        // HTTP connectivity check with Apple (works in China)
        async let test1 = safeHTTPCheck(url: "https://www.apple.com/library/test/success.html", timeout: timeout)
        async let test2 = safePing(host: pingHost, timeout: timeout)

        let (httpOk, pingResult) = await (test1, test2)

        return InternetInfo(
            isReachable: httpOk || pingResult.0,
            externalPingSuccess: pingResult.0,
            latencyToExternal: pingResult.1,
            httpTestSuccess: httpOk,
            cdnReachable: httpOk
        )
    }

    // MARK: - DNS Check (iOS-safe)

    nonisolated private func getDNS() async -> DNSInfo {
        // FIXED: Use shorter timeout on cellular
        let path = currentPath
        let isCellular = path?.usesInterfaceType(NWInterface.InterfaceType.cellular) ?? false
        let timeout: TimeInterval = isCellular ? 1.5 : 2.0

        let start = Date()
        let success = await safeDNSLookup(hostname: "www.apple.com", timeout: timeout)
        let latency = Date().timeIntervalSince(start) * 1000

        return DNSInfo(
            resolverIP: nil,
            latency: latency,
            lookupSuccess: success,
            recommendedDNS: latency > 150 ? "1.1.1.1" : nil
        )
    }

    // MARK: - VPN Check (iOS-safe)
    // FIXED: VPN detection should NOT run on every 3-second timer tick
    // Instead, use cached result and only refresh on significant network changes

    // Cache to prevent VPN detection spam
    // ISSUE 1 FIX: Increased from 5s → 30s to match polling interval
    nonisolated(unsafe) private static var cachedVPNInfo: VPNInfo?
    nonisolated(unsafe) private static var lastVPNCheck: Date = .distantPast
    nonisolated private static let vpnCacheDuration: TimeInterval = 30.0

    nonisolated private func getVPN() async -> VPNInfo {
        // Return cached VPN info if recent (within 5 seconds)
        let now = Date()
        if let cached = Self.cachedVPNInfo,
           now.timeIntervalSince(Self.lastVPNCheck) < Self.vpnCacheDuration {
            return cached
        }

        // Only fetch fresh VPN info if cache expired
        let vpnEngine = await MainActor.run { VPNEngine.shared }
        let result = await vpnEngine.getVPNInfo()

        // Update cache
        Self.cachedVPNInfo = result
        Self.lastVPNCheck = now

        return result
    }

    /// Force refresh VPN status (call on significant network changes or manual refresh)
    func forceRefreshVPN() async {
        Self.cachedVPNInfo = nil
        Self.lastVPNCheck = .distantPast
        let vpnEngine = await MainActor.run { VPNEngine.shared }
        vpnEngine.invalidateCache()
        let result = await vpnEngine.getVPNInfo()
        Self.cachedVPNInfo = result
        Self.lastVPNCheck = Date()
    }

    // MARK: - Safe Helpers (All with timeouts)

    nonisolated private func safePing(host: String, timeout: TimeInterval) async -> (Bool, Double?) {
        do {
            return try await withThrowingTaskGroup(of: (Bool, Double?).self) { group in
                group.addTask {
                    await self.performPing(host: host)
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    return (false, nil)
                }

                let result = try await group.next() ?? (false, nil)
                group.cancelAll()
                return result
            }
        } catch {
            return (false, nil)
        }
    }

    // FIXED: Use URLSession for external hosts, TCP connect for local gateway
    nonisolated private func performPing(host: String) async -> (Bool, Double?) {
        let start = Date()

        // FIXED: For local gateway IPs, use direct TCP connection to port 80
        // Previously this was redirecting to apple.com, measuring INTERNET latency
        // instead of LOCAL gateway latency. This caused 60-70ms readings for what
        // should be <10ms on a local network.
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") || host.hasPrefix("172.") {
            return await performLocalPing(host: host)
        }

        // For external hosts, use HTTPS
        let urlString: String
        if host == "1.1.1.1" || host == "1.0.0.1" || host == "cloudflare-dns.com" {
            urlString = "https://cloudflare-dns.com/dns-query?name=apple.com&type=A"
        } else if host == "8.8.8.8" || host == "8.8.4.4" {
            urlString = "https://dns.google/resolve?name=apple.com&type=A"
        } else {
            urlString = "https://\(host)"
        }

        guard let url = URL(string: urlString) else {
            return (false, nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let latency = Date().timeIntervalSince(start) * 1000
            let success = (response as? HTTPURLResponse)?.statusCode != nil
            return (success, latency)
        } catch {
            return (false, nil)
        }
    }

    /// FIXED: Ping local gateway using TCP connect to measure ACTUAL local network latency
    /// This replaces the old approach that was hitting apple.com for gateway pings
    nonisolated private func performLocalPing(host: String) async -> (Bool, Double?) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let start = Date()

                // Try TCP connect to common gateway ports: 80, 443, 53
                let ports: [UInt16] = [80, 443, 53]

                for port in ports {
                    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
                    guard socketFD >= 0 else { continue }

                    // Set non-blocking with short timeout
                    var tv = timeval(tv_sec: 1, tv_usec: 0)
                    setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                    setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                    var addr = sockaddr_in()
                    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                    addr.sin_family = sa_family_t(AF_INET)
                    addr.sin_port = port.bigEndian
                    inet_pton(AF_INET, host, &addr.sin_addr)

                    let connectResult = withUnsafePointer(to: &addr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }

                    close(socketFD)

                    if connectResult == 0 || errno == EISCONN {
                        let latency = Date().timeIntervalSince(start) * 1000
                        continuation.resume(returning: (true, latency))
                        return
                    }
                }

                // All ports failed, try ICMP-like approach with UDP
                let socketFD = socket(AF_INET, SOCK_DGRAM, 0)
                guard socketFD >= 0 else {
                    continuation.resume(returning: (false, nil))
                    return
                }

                var tv = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = UInt16(7).bigEndian  // echo port
                inet_pton(AF_INET, host, &addr.sin_addr)

                let connectResult = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                close(socketFD)

                let latency = Date().timeIntervalSince(start) * 1000

                // UDP connect to gateway usually succeeds even without a response
                if connectResult == 0 {
                    continuation.resume(returning: (true, latency))
                } else {
                    continuation.resume(returning: (false, nil))
                }
            }
        }
    }

    nonisolated private func safeHTTPCheck(url: String, timeout: TimeInterval) async -> Bool {
        do {
            return try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    guard let url = URL(string: url) else { return false }
                    let (_, response) = try await URLSession.shared.data(from: url)
                    return (response as? HTTPURLResponse)?.statusCode == 200
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    return false
                }

                let result = try await group.next() ?? false
                group.cancelAll()
                return result
            }
        } catch {
            return false
        }
    }

    nonisolated private func safeDNSLookup(hostname: String, timeout: TimeInterval) async -> Bool {
        do {
            return try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await withCheckedContinuation { continuation in
                        var hints = addrinfo(
                            ai_flags: AI_DEFAULT,
                            ai_family: AF_UNSPEC,
                            ai_socktype: SOCK_STREAM,
                            ai_protocol: 0,
                            ai_addrlen: 0,
                            ai_canonname: nil,
                            ai_addr: nil,
                            ai_next: nil
                        )

                        var result: UnsafeMutablePointer<addrinfo>?
                        let status = getaddrinfo(hostname, nil, &hints, &result)
                        if result != nil {
                            freeaddrinfo(result)
                        }
                        continuation.resume(returning: status == 0)
                    }
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    return false
                }

                let result = try await group.next() ?? false
                group.cancelAll()
                return result
            }
        } catch {
            return false
        }
    }

    // MARK: - Local Info Helpers

    nonisolated private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee,
                  let addr = interface.ifa_addr else { continue }

            let family = addr.pointee.sa_family

            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }

        return address
    }

    nonisolated private func estimateGateway() -> String? {
        guard let localIP = getLocalIP() else { return nil }

        if localIP.hasPrefix("192.168.") {
            let parts = localIP.split(separator: ".")
            guard parts.count == 4 else { return nil }
            return "192.168.\(parts[2]).1"
        } else if localIP.hasPrefix("10.") {
            return "10.0.0.1"
        } else if localIP.hasPrefix("172.") {
            let parts = localIP.split(separator: ".")
            guard parts.count >= 2 else { return nil }
            return "172.\(parts[1]).0.1"
        }

        return nil
    }

    nonisolated private func getCurrentInterface() -> NWInterface.InterfaceType? {
        guard let path = currentPath else { return nil }
        if path.usesInterfaceType(NWInterface.InterfaceType.wifi) { return .wifi }
        if path.usesInterfaceType(NWInterface.InterfaceType.cellular) { return .cellular }
        if path.usesInterfaceType(NWInterface.InterfaceType.wiredEthernet) { return .wiredEthernet }
        return nil
    }

    // MARK: - Hotspot Detection

    /// Detects if connected WiFi is actually a mobile hotspot/tethering
    nonisolated private func isConnectedToHotspot() -> Bool {
        // Check if on WiFi first
        guard let path = currentPath, path.usesInterfaceType(NWInterface.InterfaceType.wifi) else {
            return false
        }

        // FIXED: Use safe wrapper that checks location permission
        let (ssid, _) = getWiFiInfoSafely()

        guard let ssidValue = ssid else {
            return false
        }

        // Check for common hotspot SSID patterns
        let hotspotKeywords = [
            "iPhone", "iPad", "iPod",  // Apple devices
            "Android", "Galaxy",        // Android devices
            "Pixel",                   // Google Pixel
            "OnePlus", "Xiaomi",       // Other Android brands
            "Hotspot", "Tether",       // Generic terms
            "Personal"                 // "Personal Hotspot"
        ]

        let ssidLower = ssidValue.lowercased()
        for keyword in hotspotKeywords {
            if ssidLower.contains(keyword.lowercased()) {
                return true
            }
        }

        return false
    }

    // MARK: - Public API (for ViewModels)

    nonisolated func updateNetworkStatus() async {
        await performUpdate()
    }

    nonisolated func pingHost(_ host: String, timeout: TimeInterval) async -> (Bool, Double?) {
        await safePing(host: host, timeout: timeout)
    }
}
