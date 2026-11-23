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
    @Published var isInitializing = true

    // FIXED: NWPathMonitor cannot be restarted after cancel, so we create new ones as needed
    // Using nonisolated(unsafe) to allow access from nonisolated methods
    nonisolated(unsafe) private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.netosensei.networkmonitor", qos: .utility)
    // Using nonisolated(unsafe) to allow cleanup in deinit
    nonisolated(unsafe) private var updateTimer: Timer?

    // Commit 10: rebuild only when the path IDENTITY changes (see PathIdentity).
    // The previous gate compared NWPath.debugDescription, which changes on every
    // radio handover and tunnel negotiation step.
    private var lastPathIdentity: PathIdentity?
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

    /// fetchCurrent populates SSID/BSSID/security type only (Apple documentation).
    nonisolated func getSSIDViaHotspotNetwork() async -> (ssid: String?, signalStrength: Double?) {
        await withCheckedContinuation { continuation in
            let completion = TimeoutContinuation(continuation)
            NEHotspotNetwork.fetchCurrent { network in
                completion.resume(returning: (network?.ssid, nil))
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                completion.resume(returning: (nil, nil))
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

        newMonitor.pathUpdateHandler = { [weak self, weak newMonitor] path in
            guard let self, let newMonitor else { return }
            let identity = self.pathIdentity(for: path)
            Task { @MainActor [weak self] in
                guard let self, self.monitor === newMonitor,
                      PathIdentity.rebuildReason(from: self.lastPathIdentity, to: identity) != nil else { return }
                self.lastPathIdentity = identity
                self.pathGeneration += 1
                ExitPath.pathIdentityChanged()
                self.invalidateVPNCache()
                self.currentStatus = self.localSnapshot(path: path)
                self.isInitializing = false
                await self.performUpdate(force: true)
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

    }

    func stopMonitoring() {
        isMonitoring = false
        lastPathIdentity = nil
        pathGeneration += 1
        inFlightUpdate?.cancel()
        monitor?.cancel()
        monitor = nil
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Status Update (Non-blocking)

    private var pathGeneration = 0
    private var inFlightUpdate: Task<Void, Never>?

    private func localSnapshot(path: Network.NWPath) -> NetworkStatus {
        var status = NetworkStatus.empty
        guard path.status == .satisfied else { return status }
        let interface = getCurrentInterface()
        status.connectionType = interface ?? .other
        status.localIP = getLocalIP()
        status.isIPv4Enabled = path.supportsIPv4
        status.isIPv6Enabled = path.supportsIPv6
        status.wifi = WiFiInfo(isConnected: interface == .wifi || pathHasWiFiAvailable(path) || hasIPOnInterface(named: "en0"))
        if ConnectionCards.showsRouterCard(status) { status.router.gatewayIP = estimateGateway() }
        status.measurementsPending = true
        return status
    }

    private func performUpdate(force: Bool = false) async {
        guard isMonitoring, lastPathIdentity?.status == .satisfied else { return }
        if let active = inFlightUpdate {
            if force { await active.value }
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.inFlightUpdate = nil }
            while self.isMonitoring, self.lastPathIdentity?.status == .satisfied, !Task.isCancelled {
                let generation = self.pathGeneration
                await self.readStatus(generation: generation)
                guard self.isMonitoring, !Task.isCancelled else { return }
                if generation == self.pathGeneration { return }
            }
        }
        inFlightUpdate = task
        await task.value
    }

    private enum Reading {
        case wifi(WiFiInfo), router(RouterInfo), internet(InternetInfo), web(Bool), dns(DNSInfo), vpn(VPNInfo)
        case deadline
    }

    private func readStatus(generation: Int) async {
        guard let path = currentPath else { return }
        let onCellular = path.usesInterfaceType(.cellular)
        let timeout: Duration = onCellular ? .seconds(5) : .seconds(8)
        let probeTimeout: TimeInterval = onCellular ? 2 : 3
        var snapshot = localSnapshot(path: path)
        await withTaskGroup(of: Reading.self) { group in
            group.addTask { .wifi(await self.getWiFi()) }
            group.addTask { .router(await self.getRouter()) }
            group.addTask { .internet(await self.getInternet(timeout: probeTimeout)) }
            group.addTask {
                .web(await self.safeHTTPCheck(url: "https://www.apple.com/library/test/success.html", timeout: probeTimeout))
            }
            group.addTask { .dns(await self.getDNS()) }
            group.addTask { .vpn(await VPNEngine.shared.getVPNInfo()) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .deadline
            }

            let expectedReadings = 6
            var completed = 0
            for await reading in group {
                guard generation == pathGeneration, !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                switch reading {
                case .wifi(let value): snapshot.wifi = value
                case .router(let value): snapshot.router = value
                case .internet(var value):
                    if snapshot.internet.httpTestSuccess { value.recordWebSuccess() }
                    snapshot.internet = value
                case .web(let succeeded):
                    if succeeded { snapshot.internet.recordWebSuccess() }
                case .dns(let value): snapshot.dns = value
                case .vpn(let value): snapshot.vpn = value
                case .deadline:
                    completed = expectedReadings - 1
                    snapshot.measurementsIncomplete = true
                }
                completed += 1
                snapshot.timestamp = Date()
                let finished = completed == expectedReadings
                snapshot.measurementsPending = !finished
                // On a same-path refresh, keep the prior readings visible
                // until the replacement is ready.
                if finished || currentStatus.measurementsPending { currentStatus = snapshot }
                if finished {
                    group.cancelAll()
                    return
                }
            }
        }
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
        let wifiAvailable = pathHasWiFiAvailable(path)

        // FIX (Issue 1): Don't short-circuit to "WiFi disconnected" just because the
        // primary path is cellular. iPhones can be on cellular AND associated with WiFi
        // at the same time. Only short-circuit when we're SURE there is no WiFi —
        // i.e. NWPath doesn't list WiFi AND en0 has no IP.
        if !nwPathSaysWiFi && !wifiAvailable && !en0HasIPEarly {
            return WiFiInfo(isConnected: false)
        }

        // Method 1: CNCopyCurrentNetworkInfo
        var (ssid, bssid) = getWiFiInfoSafely()

        // Fetch the current SSID as fallback; this API does not populate signal strength.
        let hotspotResult = ssid == nil ? await getSSIDViaHotspotNetwork() : (ssid: nil, signalStrength: nil)
        let signalStrength = hotspotResult.signalStrength

        // Method 2: If SSID is nil despite permission, use NEHotspotNetwork SSID
        if ssid == nil {
            if let hs = hotspotResult.ssid {
                ssid = hs
            }
        }

        // ISSUE 2 FIX: Only log when SSID changes.
        // CLEANUP 3: Snapshot the mutable `var ssid` into an immutable `let`
        // before any concurrent closure captures it — Swift 6 will reject
        // direct capture of a mutable local in a sendable closure.
        let resolvedSSID = ssid
        let previousSSID = await MainActor.run { self.lastSSID }
        if resolvedSSID != previousSSID {
            let source = Self.cncopyAvailable == true ? "CNCopy" : "NEHotspotNetwork"
            debugLog("[WiFi] SSID: \(resolvedSSID ?? "none") (via \(source))")
            await MainActor.run { self.lastSSID = resolvedSSID }
        }

        // FIX (Issue 1): WiFi is connected if ANY of these is true:
        //   - NWPath reports WiFi as the active interface
        //   - The en0 interface has an IPv4 address assigned
        //   - We were able to read the SSID
        // Reusing en0HasIPEarly from above (recomputing would just re-walk getifaddrs).
        let isConnected = nwPathSaysWiFi || wifiAvailable || en0HasIPEarly || ssid != nil

        // Record signal strength sample for tracking
        if let strength = signalStrength {
            await SignalStrengthTracker.shared.recordSample(strength: strength, ssid: ssid)
        } else {
            await SignalStrengthTracker.shared.clearCurrent()
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

    /// Check if a named interface has a routable IP (IPv4 or IPv6, excluding link-local)
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

            if name == targetName && (family == UInt8(AF_INET) || family == UInt8(AF_INET6)) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                        &hostname, socklen_t(hostname.count),
                                        nil, 0, NI_NUMERICHOST)
                if result == 0 {
                    let ip = String(cString: hostname)
                    if ip.isEmpty || ip == "0.0.0.0" || ip == "::" || ip.hasPrefix("fe80:") {
                        continue
                    }
                    return true
                }
            }
        }
        return false
    }

    /// WiFi listed in path's available interfaces — true even when VPN is active
    nonisolated private func pathHasWiFiAvailable(_ path: Network.NWPath?) -> Bool {
        guard let path else { return false }
        return path.availableInterfaces.contains { $0.type == .wifi }
    }

    // MARK: - Router Check (iOS-safe, median of 5 pings, outlier rejection)

    nonisolated private func getRouter() async -> RouterInfo {
        guard let path = currentPath else {
            return RouterInfo(gatewayIP: nil, isReachable: false)
        }
        if path.usesInterfaceType(NWInterface.InterfaceType.cellular)
            && !path.usesInterfaceType(NWInterface.InterfaceType.wifi)
            && !pathHasWiFiAvailable(path)
            && !hasIPOnInterface(named: "en0") {
            return RouterInfo(gatewayIP: nil, isReachable: false)
        }

        let gatewayIP = estimateGateway()
        guard let gateway = gatewayIP else {
            return RouterInfo(gatewayIP: nil, isReachable: false)
        }

        // FIXED: Measure 5 times, take median, discard outliers (>3x median).
        // Gateway latency is measured with the SAME network-layer TCP-handshake
        // probe as the internet latency (NetworkLatencyProbe) — a non-blocking
        // poll()-bounded BSD connect. A gateway with no responding TCP port
        // has unknown latency. UDP connect alone proves no response.
        var latencies: [Double] = []
        var successCount = 0
        let pingCount = 5

        for _ in 0..<pingCount {
            if let rttSeconds = await NetworkLatencyProbe.shared.measureHandshake(
                host: gateway,
                ports: [80, 443, 53],
                allowUDPFallback: false,
                timeout: 1.0
            ) {
                latencies.append(rttSeconds * 1000.0)
                successCount += 1
            }
        }

        guard !latencies.isEmpty else {
            return RouterInfo(gatewayIP: gateway, isReachable: false)
        }

        // Sort and take median
        latencies.sort()
        guard let median = MeasurementStatistics.median(latencies) else {
            return RouterInfo(gatewayIP: gateway, isReachable: true)
        }

        // Discard outliers (>3x median) and recalculate
        let filtered = latencies.filter { $0 <= median * 3.0 }
        let finalLatency = MeasurementStatistics.median(filtered) ?? median

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
            packetLoss: nil, // TCP probe failure is not IP packet loss.
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
        await getRouter() // Same successful TCP timing; no probe-failure ratio labelled packet loss.
    }

    // MARK: - Internet Check (iOS-safe, China-aware)

    nonisolated private func getInternet(timeout: TimeInterval) async -> InternetInfo {
        // FIXED: China-aware latency target
        // If user is in China without VPN, ping domestic servers for meaningful latency
        // Otherwise use Cloudflare (works globally, including through VPN)
        let isInChina = await MainActor.run {
            SmartVPNDetector.shared.detectionResult?.isLikelyInChina ?? false
        }
        let vpnActive = await MainActor.run {
            SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        }

        // China-aware: Cloudflare/Google/Quad9 are throttled/blocked in mainland
        // China, so when in-China-without-VPN we prefer domestic targets for both
        // the network-layer probe and the HTTP reachability ping.
        let preferDomestic = isInChina && !vpnActive
        let pingHost = Self.externalPingHost(preferDomestic: preferDomestic)

        // PRIMARY latency: network-layer TCP-handshake RTT (no HTTP/TLS/DNS),
        // measured by NetworkLatencyProbe. This is the dashboard "Latency".
        async let primary = NetworkLatencyProbe.shared.measureExternalLatency(preferDomestic: preferDomestic)
        // INTERCEPTION REFERENCE: a fresh, honest gateway handshake RTT measured
        // alongside the external probe. TUN-mode proxies fake the external RTT
        // but leave LAN gateway traffic untouched, so the gateway is our
        // physical floor (see LatencyInterception). Measured here (not borrowed
        // from getRouter) so the interception logic stays self-contained and
        // reusable by the speed-test phase.
        async let gatewayRef = measureGatewayReferenceRTT()
        // SECONDARY: full HTTPS round-trip — kept as "App response time" + used
        // for the reachability verdict.
        async let httpsResponse = safePing(host: pingHost, timeout: timeout)

        let (primaryLatencySec, gatewayRefMs, pingResult) = await (primary, gatewayRef, httpsResponse)
        let measuredExternalMs = primaryLatencySec.map { $0 * 1000.0 }
        let httpRTTms = pingResult.1

        // INTERCEPTION VERDICT. When a local proxy faked the handshake we store
        // latencyToExternal = nil (never the fake number) and raise the flag —
        // every numeric consumer already excludes nil, so the fabricated value
        // enters no smoothing buffer, health score, quality verdict or trend.
        // A local handshake cannot establish remote reachability. Preserve
        // independent HTTPS evidence even when the TCP timing is discarded.
        var intercepted = false
        var honestLatencyMs = measuredExternalMs
        if let ext = measuredExternalMs {
            let verdict = LatencyInterception.evaluate(
                externalRTTms: ext,
                gatewayRTTms: gatewayRefMs,
                vpnActive: vpnActive
            )
            intercepted = verdict.intercepted
            if intercepted {
                honestLatencyMs = nil
                debugLog("[Latency] Probe intercepted by local proxy — \(verdict.reason)")
            }
        }

        return InternetInfo(
            isReachable: pingResult.0 || honestLatencyMs != nil,
            externalPingSuccess: pingResult.0 || honestLatencyMs != nil,
            // PRIMARY only — never fall back to HTTP RTT here (no silent mixing).
            latencyToExternal: honestLatencyMs,
            httpTestSuccess: false,
            cdnReachable: false,
            httpRTT: httpRTTms,
            httpsProbeWasDomestic: preferDomestic,
            latencyIntercepted: intercepted
        )
    }

    /// Fresh gateway handshake RTT (ms) used as the physical reference for
    /// latency-interception detection (see LatencyInterception). The gateway is
    /// on the LAN (private IP) and is NOT routed through TUN-mode proxies, so
    /// this handshake stays honest even when a proxy intercepts external
    /// connections. Median of 3 keeps a single jittery sample from falsely
    /// flagging a real external reading. UDP fallback is intentionally OFF: a
    /// UDP association "succeeds" in ~0ms and would poison the reference toward
    /// zero, masking real interception — when no TCP port answers we return nil
    /// and let the absolute-floor authority take over. Returns nil when no
    /// gateway is estimable (e.g. cellular).
    /// Phase 3: promoted from private to internal so SpeedTestEngine reuses the
    /// same honest gateway reference for its ping-interception check.
    // MARK: - China-aware external target (single source of the rule)

    /// The ONE rule for the external reachability ping host. Cloudflare /
    /// Google / Quad9 are throttled or blocked in mainland China without a
    /// VPN, so in-China-without-VPN prefers a domestic target. Used by
    /// getInternet() and the Quick Check's external test (Commit 6) so both
    /// judge the same path; SpeedTestEngine applies the same preferDomestic
    /// rule to NetworkLatencyProbe's target list.
    nonisolated static func externalPingHost(preferDomestic: Bool) -> String {
        preferDomestic ? "www.baidu.com" : "apple.com"
    }

    /// `isLikelyInChina && !isVPNActive` from the VPN detector — the condition
    /// getInternet() evaluates before choosing the external target.
    static func preferDomesticTargets() -> Bool {
        let r = SmartVPNDetector.shared.detectionResult
        return (r?.isLikelyInChina ?? false) && !(r?.isVPNActive ?? false)
    }

    nonisolated func measureGatewayReferenceRTT() async -> Double? {
        guard let gateway = estimateGateway() else { return nil }
        var samples: [Double] = []
        for _ in 0..<3 {
            if let rttSeconds = await NetworkLatencyProbe.shared.measureHandshake(
                host: gateway,
                ports: [80, 443, 53],
                allowUDPFallback: false,
                timeout: 1.0
            ) {
                samples.append(rttSeconds * 1000.0)
            }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return MeasurementStatistics.median(samples)
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
            latency: success ? latency : nil,
            lookupSuccess: success,
            recommendedDNS: success && latency > 150 ? "1.1.1.1" : nil
        )
    }

    // MARK: - VPN Check (iOS-safe)
    // FIXED: VPN detection should NOT run on every 3-second timer tick
    // Instead, use cached result and only refresh on significant network changes

    // Cache to prevent VPN detection spam
    // ISSUE 1 FIX: Increased from 5s → 30s to match polling interval
    func invalidateVPNCache() {
        VPNEngine.shared.invalidateCache()
        SmartVPNDetector.shared.invalidate()
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
        let seconds = await NetworkLatencyProbe.shared.measureHandshake(
            host: host, ports: [80, 443, 53], allowUDPFallback: false, timeout: 1.0
        )
        return (seconds != nil, seconds.map { $0 * 1000 })
    }

    nonisolated private func safeHTTPCheck(url: String, timeout: TimeInterval) async -> Bool {
        do {
            return try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    guard let url = URL(string: url) else { return false }
                    let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
                    let (_, response) = try await URLSession.shared.data(for: request)
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
        await SystemDNSResolver.resolve(hostname, timeout: timeout) != nil
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

    /// The LAN router address and where it came from.
    struct GatewayAddress: Equatable {
        let ip: String
        /// false = read from the kernel routing table (real); true = inferred
        /// from the local IP by the legacy heuristic (a guess, labelled as such).
        let isAssumed: Bool
    }

    /// Diagnosis v2 (Commit 1): the real default gateway from the routing table
    /// when available; the legacy heuristic only as a labelled fallback.
    /// Returns nil on cellular-only paths and whenever nothing can be read or
    /// inferred — callers must treat nil as "not applicable", never as a failure.
    nonisolated func detectedGateway() -> GatewayAddress? {
        if let route = DefaultRouteResolver.lanGateway() {
            return GatewayAddress(ip: route.gateway, isAssumed: false)
        }
        return nil
    }

    nonisolated private func estimateGateway() -> String? {
        detectedGateway()?.ip
    }

    // MARK: - Path identity (Commit 10)

    /// Synchronous, kernel-level identity of the active path. Conservative:
    /// anything not proven stable across a handover/tunnel flap is included.
    nonisolated private func pathIdentity(for path: Network.NWPath) -> PathIdentity {
        let status: PathIdentity.Status
        switch path.status {
        case .satisfied: status = .satisfied
        case .unsatisfied: status = .unsatisfied
        case .requiresConnection: status = .requiresConnection
        @unknown default: status = .unsatisfied
        }

        // The physical carrier. With a TUN VPN the path's own interface is the
        // tunnel (type .other); the carrier is then found in availableInterfaces.
        func physical(in interfaces: [NWInterface]) -> NWInterface? {
            interfaces.first { $0.type == .wifi } ?? interfaces.first { $0.type == .cellular } ?? interfaces.first { $0.type == .wiredEthernet }
        }
        let direct = physical(in: path.usesInterfaceType(.wifi) || path.usesInterfaceType(.cellular) || path.usesInterfaceType(.wiredEthernet)
                              ? path.availableInterfaces.filter { path.usesInterfaceType($0.type) } : [])
        let carrier = direct ?? physical(in: path.availableInterfaces)
        let physicalType: PathIdentity.Physical
        switch carrier?.type {
        case .wifi?: physicalType = .wifi
        case .cellular?: physicalType = .cellular
        case .wiredEthernet?: physicalType = .wired
        default: physicalType = .none
        }
        // Routed through a tunnel = the path's PRIMARY interface (first in
        // availableInterfaces, the one debugDescription prints) is .other
        // (utun/ipsec). Commit 13: the Commit 10 form — "uses .other and not a
        // physical type" — was never true with a VPN up, because the path also
        // "uses" the cellular/Wi-Fi interface under the tunnel (device log:
        // identity "…/direct" while the path's interface was utun4[lte]). A VPN
        // toggle was therefore invisible to the identity gate.
        let viaTunnel = path.availableInterfaces.first?.type == .other
        let subnet: String? = (physicalType == .wifi || physicalType == .wired) ? NetworkSegment.subnet(of: getLocalIP()) : nil

        return PathIdentity(status: status, physical: physicalType, physicalName: carrier?.name, subnet: subnet, viaTunnel: viaTunnel)
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

    /// - Parameter force: see performUpdate(force:). Pull-to-refresh and
    ///   foregrounding pass true; a forced call never silently no-ops.
    nonisolated func updateNetworkStatus(force: Bool = false) async {
        await performUpdate(force: force)
    }

    nonisolated func pingHost(_ host: String, timeout: TimeInterval) async -> (Bool, Double?) {
        await safePing(host: host, timeout: timeout)
    }
}
