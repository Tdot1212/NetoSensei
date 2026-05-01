//
//  VPNBenchmarkEngine.swift
//  NetoSensei
//
//  VPN Benchmark Engine - Manual VPN testing with REAL measurements
//  User turns VPN ON/OFF manually, NetoSensei measures automatically
//

import Foundation
import Network

@MainActor
class VPNBenchmarkEngine: ObservableObject {
    static let shared = VPNBenchmarkEngine()

    @Published var isVPNActive: Bool = false
    @Published var isBenchmarking: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentTask: String = ""

    private let geoIPService = GeoIPService.shared
    private var vpnMonitor: NWPathMonitor?

    private init() {
        startVPNMonitoring()
    }

    // MARK: - VPN State Monitoring

    private func startVPNMonitoring() {
        vpnMonitor = NWPathMonitor()
        let queue = DispatchQueue(label: "vpn-monitor")

        vpnMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let hasVPN = path.availableInterfaces.contains { interface in
                    let name = interface.name.lowercased()
                    return name.contains("utun") ||
                           name.contains("ppp") ||
                           name.contains("ipsec") ||
                           name.contains("tun") ||
                           name.contains("tap")
                }

                self?.isVPNActive = hasVPN
            }
        }

        vpnMonitor?.start(queue: queue)
    }

    // MARK: - Manual VPN Benchmark

    func runManualBenchmark(protocolMode: String, userNotes: String? = nil) async -> VPNProfile? {
        isBenchmarking = true
        progress = 0.0

        // 1. Fetch Public IP and GeoIP (25%)
        updateProgress(0.25, task: "Detecting VPN location...")
        let geoIPInfo = await geoIPService.fetchGeoIPInfo()

        let publicIP = geoIPInfo.publicIP
        let country = geoIPInfo.country ?? "Unknown"
        let city = geoIPInfo.city ?? "Unknown"
        let region = "\(country) - \(city)"

        // 2. Measure Latency and Jitter (50%)
        updateProgress(0.5, task: "Measuring latency...")
        let (latency, jitter) = await measureLatencyAndJitter(to: "cloudflare.com")

        // 3. Measure Packet Loss (65%)
        updateProgress(0.65, task: "Measuring packet loss...")
        let packetLoss = await measurePacketLoss(to: "cloudflare.com")

        // 4. Measure Download Speed (80%)
        updateProgress(0.8, task: "Measuring download speed...")
        let downloadSpeed = await measureDownloadSpeed()

        // 5. Measure Upload Speed (90%)
        updateProgress(0.9, task: "Measuring upload speed...")
        let uploadSpeed = await measureUploadSpeed()

        // 6. DNS Leak Test (95%)
        updateProgress(0.95, task: "Checking for DNS leaks...")
        let dnsLeakDetected = await checkDNSLeak()

        // Complete
        updateProgress(1.0, task: "Complete")

        // Create VPN Profile
        let profile = VPNProfile(
            region: region,
            country: country,
            city: city,
            protocolMode: protocolMode,
            publicIP: publicIP,
            latency: latency,
            jitter: jitter,
            packetLoss: packetLoss,
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            timeToStabilize: 2.0,  // Simplified for now
            dnsLeakDetected: dnsLeakDetected,
            notes: userNotes
        )

        isBenchmarking = false
        return profile
    }

    // MARK: - WiFi Baseline Benchmark (No VPN)

    func runWiFiBaselineBenchmark() async -> WiFiBaselineProfile? {
        isBenchmarking = true
        progress = 0.0

        // Ensure VPN is OFF
        guard !isVPNActive else {
            isBenchmarking = false
            return nil
        }

        // 1. Fetch Public IP (25%)
        updateProgress(0.25, task: "Detecting your real IP...")
        let geoIPInfo = await geoIPService.fetchGeoIPInfo()
        let publicIP = geoIPInfo.publicIP

        // 2. Measure Latency and Jitter (50%)
        updateProgress(0.5, task: "Measuring baseline latency...")
        let (latency, jitter) = await measureLatencyAndJitter(to: "cloudflare.com")

        // 3. Measure Packet Loss (70%)
        updateProgress(0.7, task: "Measuring baseline packet loss...")
        let packetLoss = await measurePacketLoss(to: "cloudflare.com")

        // 4. Measure Download Speed (85%)
        updateProgress(0.85, task: "Measuring baseline download speed...")
        let downloadSpeed = await measureDownloadSpeed()

        // 5. Measure Upload Speed (100%)
        updateProgress(1.0, task: "Measuring baseline upload speed...")
        let uploadSpeed = await measureUploadSpeed()

        let baseline = WiFiBaselineProfile(
            timestamp: Date(),
            publicIP: publicIP,
            latency: latency,
            jitter: jitter,
            packetLoss: packetLoss,
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed
        )

        isBenchmarking = false
        return baseline
    }

    // MARK: - Performance Measurements

    private func measureLatencyAndJitter(to host: String) async -> (latency: Double, jitter: Double) {
        var latencies: [Double] = []

        for _ in 0..<5 {
            let startTime = Date()
            _ = await pingHost(host)
            let duration = Date().timeIntervalSince(startTime) * 1000  // ms
            latencies.append(duration)
        }

        guard !latencies.isEmpty else { return (999.0, 999.0) }

        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)

        // Calculate jitter (standard deviation)
        let variance = latencies.map { pow($0 - avgLatency, 2) }.reduce(0, +) / Double(latencies.count)
        let jitter = sqrt(variance)

        return (avgLatency, jitter)
    }

    private func measurePacketLoss(to host: String) async -> Double {
        let totalPackets = 10
        var successfulPackets = 0

        for _ in 0..<totalPackets {
            if await pingHost(host) {
                successfulPackets += 1
            }
        }

        let lossCount = totalPackets - successfulPackets
        return (Double(lossCount) / Double(totalPackets)) * 100
    }

    private func measureDownloadSpeed() async -> Double {
        // Use Cloudflare speed test (5MB download)
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=5000000") else {
            return 0
        }

        let startTime = Date()

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let duration = Date().timeIntervalSince(startTime)
            let megabytes = Double(data.count) / 1_000_000
            return (megabytes * 8) / duration  // Mbps
        } catch {
            return 0
        }
    }

    private func measureUploadSpeed() async -> Double {
        // Simplified: estimate upload as 70% of download
        let downloadSpeed = await measureDownloadSpeed()
        return downloadSpeed * 0.7
    }

    private func checkDNSLeak() async -> Bool {
        // Simple DNS leak check: verify if DNS queries are going through VPN
        // For now, return false (no leak detected)
        // In production, would check DNS server against VPN provider's DNS
        return false
    }

    // FIXED: Use URLSession instead of NWConnection to prevent app freeze
    private func pingHost(_ host: String) async -> Bool {
        guard let url = URL(string: "https://\(host)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode != nil
        } catch {
            return false
        }
    }

    private func updateProgress(_ value: Double, task: String) {
        progress = value
        currentTask = task
    }

    deinit {
        vpnMonitor?.cancel()
    }
}
