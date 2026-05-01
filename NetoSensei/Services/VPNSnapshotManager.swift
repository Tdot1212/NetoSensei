//
//  VPNSnapshotManager.swift
//  NetoSensei
//
//  Manages VPN snapshot storage, retrieval, and lifecycle
//

import Foundation
import SwiftUI

@MainActor
class VPNSnapshotManager: ObservableObject {
    static let shared = VPNSnapshotManager()

    @Published var snapshots: [VPNSnapshot] = []

    private let storageKey = "vpn_snapshots"
    private let maxSnapshots = 100  // Keep last 100 snapshots

    private init() {
        loadSnapshots()
    }

    // MARK: - Persistence

    private func loadSnapshots() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([VPNSnapshot].self, from: data) else {
            print("📸 [VPNSnapshotManager] No saved snapshots found")
            return
        }

        snapshots = decoded.sorted(by: { $0.timestamp > $1.timestamp })
        print("📸 [VPNSnapshotManager] Loaded \(snapshots.count) snapshots")
    }

    private func saveSnapshots() {
        // FIXED: Use safe save to prevent UserDefaults crash from large snapshot data
        // VPN snapshots can be large with all the nested metrics
        UserDefaults.standard.setSafe(snapshots, forKey: storageKey, maxItems: 50)
    }

    // MARK: - Snapshot Management

    func addSnapshot(_ snapshot: VPNSnapshot) {
        snapshots.insert(snapshot, at: 0)  // Insert at beginning (newest first)

        // Trim to max limit
        if snapshots.count > maxSnapshots {
            snapshots = Array(snapshots.prefix(maxSnapshots))
            print("🗑️ [VPNSnapshotManager] Trimmed to \(maxSnapshots) snapshots")
        }

        saveSnapshots()
        print("✅ [VPNSnapshotManager] Added snapshot: \(snapshot.vpnLabel)")
    }

    func deleteSnapshot(_ snapshot: VPNSnapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        saveSnapshots()
        print("🗑️ [VPNSnapshotManager] Deleted snapshot: \(snapshot.vpnLabel)")
    }

    func updateSnapshot(_ snapshot: VPNSnapshot) {
        if let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
            snapshots[index] = snapshot
            saveSnapshots()
            print("✏️ [VPNSnapshotManager] Updated snapshot: \(snapshot.vpnLabel)")
        }
    }

    func deleteAll() {
        snapshots.removeAll()
        saveSnapshots()
        print("🗑️ [VPNSnapshotManager] Deleted all snapshots")
    }

    // MARK: - Queries

    func snapshotsWithVPN(on: Bool) -> [VPNSnapshot] {
        snapshots.filter { $0.vpnState == (on ? .on : .off) }
    }

    func snapshotsForCountry(_ country: String) -> [VPNSnapshot] {
        snapshots.filter { $0.geo.country.lowercased() == country.lowercased() }
    }

    func snapshotsForVPNLabel(_ label: String) -> [VPNSnapshot] {
        snapshots.filter { $0.vpnLabel == label }
    }

    func recentSnapshots(limit: Int = 10) -> [VPNSnapshot] {
        Array(snapshots.prefix(limit))
    }

    // MARK: - Statistics

    var statistics: VPNSnapshotStatistics {
        VPNSnapshotStatistics(snapshots: snapshots)
    }

    var uniqueVPNLabels: [String] {
        Array(Set(snapshots.map { $0.vpnLabel })).sorted()
    }

    var uniqueCountries: [String] {
        Array(Set(snapshots.map { $0.geo.country })).sorted()
    }

    // MARK: - Export/Import

    func exportAsJSON() -> String? {
        guard let data = try? JSONEncoder().encode(snapshots),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    func importFromJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let imported = try? JSONDecoder().decode([VPNSnapshot].self, from: data) else {
            return false
        }

        // Merge with existing snapshots (avoid duplicates by ID)
        let existingIDs = Set(snapshots.map { $0.id })
        let newSnapshots = imported.filter { !existingIDs.contains($0.id) }

        snapshots.append(contentsOf: newSnapshots)
        snapshots.sort(by: { $0.timestamp > $1.timestamp })

        // Trim to max
        if snapshots.count > maxSnapshots {
            snapshots = Array(snapshots.prefix(maxSnapshots))
        }

        saveSnapshots()
        print("📥 [VPNSnapshotManager] Imported \(newSnapshots.count) new snapshots")
        return true
    }

    // MARK: - Snapshot Creation from Current State

    func createSnapshot(
        from networkStatus: NetworkStatus,
        diagnosticSummary: AdvancedDiagnosticSummary?,
        geoInfo: GeoIPInfo?,
        userDeclaredVPNState: VPNSnapshot.VPNState,  // USER DECLARES THIS, not auto-detected
        vpnLabel: String,
        userNotes: String? = nil
    ) -> VPNSnapshot {
        // Use user-declared VPN state (professional diagnostic tool approach)
        let vpnState = userDeclaredVPNState

        // Build GeoLocation
        let geo = VPNSnapshot.GeoLocation(
            country: geoInfo?.country ?? "Unknown",
            countryCode: geoInfo?.countryCode ?? "??",
            city: geoInfo?.city,
            asn: geoInfo?.asn,
            isp: geoInfo?.isp,
            isVPN: geoInfo?.isVPN ?? false,
            isProxy: geoInfo?.isProxy ?? false
        )

        // Build Performance Metrics
        let performance = VPNSnapshot.PerformanceMetrics(
            pingAvg: networkStatus.router.latency ?? 0,
            internetPing: networkStatus.internet.latencyToExternal,
            jitter: networkStatus.router.jitter ?? 0,
            packetLoss: networkStatus.router.packetLoss ?? 0,
            downloadMbps: networkStatus.streamingThroughput ?? networkStatus.performanceThroughput ?? 0,
            uploadMbps: nil  // Not measured yet
        )

        // Build DNS Metrics
        let dnsBehavior: String
        if let summary = diagnosticSummary {
            switch summary.dnsBehaviorType {
            case .normalChinaISP:
                dnsBehavior = "Normal China ISP"
            case .dnsConfigurationIssue:
                dnsBehavior = "DNS Configuration Issue"
            case .abnormalDNSBehavior:
                dnsBehavior = "Abnormal DNS Behavior"
            case .allNormal:
                dnsBehavior = "All Normal"
            }
        } else {
            dnsBehavior = "Unknown"
        }

        let dns = VPNSnapshot.DNSMetrics(
            resolver: networkStatus.dns.resolverIP ?? "Unknown",
            latencyMs: networkStatus.dns.latency ?? 0,
            hijackDetected: diagnosticSummary?.dnsHijackResults.contains { $0.hijacked } ?? false,
            dnsBehavior: dnsBehavior
        )

        // Build Routing Metrics
        let routing: VPNSnapshot.RoutingMetrics
        if let routingInterpretation = diagnosticSummary?.routingInterpretation {
            let avgLatency = routingInterpretation.hops
                .compactMap { $0.latency }
                .reduce(0, +) / max(1, routingInterpretation.hops.count)

            routing = VPNSnapshot.RoutingMetrics(
                hopCount: routingInterpretation.hops.count,
                avgHopLatency: Double(avgLatency),
                routingQuality: routingInterpretation.problemType == .normal ? "Optimal" : "Suboptimal"
            )
        } else {
            routing = VPNSnapshot.RoutingMetrics(
                hopCount: 0,
                avgHopLatency: 0,
                routingQuality: "Unknown"
            )
        }

        // Build Network Metrics
        let connectionTypeString: String
        if let type = networkStatus.connectionType {
            switch type {
            case .wifi:
                connectionTypeString = "Wi-Fi"
            case .cellular:
                connectionTypeString = "Cellular"
            case .wiredEthernet:
                connectionTypeString = "Ethernet"
            case .loopback:
                connectionTypeString = "Loopback"
            case .other:
                connectionTypeString = "Other"
            @unknown default:
                connectionTypeString = "Unknown"
            }
        } else {
            connectionTypeString = "Unknown"
        }

        let network = VPNSnapshot.NetworkMetrics(
            connectionType: connectionTypeString,
            wifiSSID: networkStatus.wifi.ssid,
            wifiBSSID: networkStatus.wifi.bssid,  // Access point MAC address (correlation key)
            wifiRSSI: networkStatus.wifi.rssi,  // Signal strength (VERY IMPORTANT)
            wifiNoise: networkStatus.wifi.noise,  // Noise floor (VERY IMPORTANT for SNR)
            wifiLinkSpeed: networkStatus.wifi.linkSpeed,  // TX rate - actual airtime quality
            wifiChannel: networkStatus.wifi.channel,  // Channel number
            wifiChannelWidth: networkStatus.wifi.channelWidth,  // 20, 40, 80, 160 MHz
            wifiBand: networkStatus.wifi.band,  // "2.4 GHz", "5 GHz", "6 GHz"
            wifiPHYMode: networkStatus.wifi.phyMode,  // "802.11ac", "802.11ax", etc.
            wifiMCSIndex: networkStatus.wifi.mcsIndex,  // Modulation and Coding Scheme
            wifiNSS: networkStatus.wifi.nss,  // Number of Spatial Streams
            localIP: networkStatus.localIP
        )

        // Build Stability Metrics (CRITICAL for video buffering)
        let stabilityMetrics = StabilityMetrics(
            jitter: networkStatus.router.jitter ?? 0,
            latencyStdDev: nil,  // Would need multiple measurements
            txRateStability: "Unknown",  // Would need history tracking
            mcsStability: "Unknown",  // Would need history tracking
            packetDeliveryPredictable: (networkStatus.router.packetLoss ?? 0) < 1.0
        )

        // Run Congestion Analysis
        let congestionAnalysis = CongestionAnalyzer.analyze(
            rssi: networkStatus.wifi.rssi,
            noise: networkStatus.wifi.noise,
            txRate: networkStatus.wifi.linkSpeed,
            mcsIndex: networkStatus.wifi.mcsIndex,
            pingAvg: networkStatus.router.latency ?? 0,
            jitter: networkStatus.router.jitter ?? 0,
            packetLoss: networkStatus.router.packetLoss ?? 0,
            throughput: performance.downloadMbps
        )

        // Build VPN Visibility Test (if VPN is ON)
        let vpnVisibilityTest: VPNVisibilityTestResult?
        if vpnState == .on, let geoInfo = geoInfo {
            vpnVisibilityTest = createVPNVisibilityTest(from: geoInfo, dns: dns, networkStatus: networkStatus)
        } else {
            vpnVisibilityTest = nil
        }

        return VPNSnapshot(
            vpnState: vpnState,
            declaredByUser: true,  // Always true - user explicitly declared the state
            vpnLabel: vpnLabel,
            publicIP: networkStatus.publicIP ?? "Unknown",
            geo: geo,
            performance: performance,
            dns: dns,
            routing: routing,
            network: network,
            stabilityMetrics: stabilityMetrics,
            congestionAnalysis: congestionAnalysis,
            bufferbloatTest: nil,  // Would need dedicated test
            vpnVisibilityTest: vpnVisibilityTest,
            userNotes: userNotes
        )
    }

    // MARK: - VPN Visibility Test Creation

    func createVPNVisibilityTest(
        from geoInfo: GeoIPInfo,
        dns: VPNSnapshot.DNSMetrics,
        networkStatus: NetworkStatus
    ) -> VPNVisibilityTestResult {

        // Determine IP type based on flags, ASN, and known providers
        // FIXED: Comprehensive list of known datacenter/cloud/VPN providers
        let ipType: IPType
        let orgLower = (geoInfo.org ?? "").lowercased()
        let ispLower = (geoInfo.isp ?? "").lowercased()
        let combinedNames = orgLower + " " + ispLower

        // Known datacenter/cloud/VPN provider keywords
        let datacenterKeywords = [
            "zenlayer", "aws", "amazon", "google cloud", "gcp", "azure", "microsoft",
            "digitalocean", "linode", "vultr", "ovh", "hetzner", "oracle cloud",
            "alibaba cloud", "tencent cloud", "cloudflare", "akamai", "fastly",
            "hosting", "datacenter", "data center", "cloud", "server", "vps",
            "colocation", "colo", "infrastructure", "cdn", "edge"
        ]

        let vpnKeywords = [
            "vpn", "express", "nord", "surfshark", "proton", "mullvad", "private",
            "wireguard", "shadowsocks", "v2ray", "trojan", "clash", "surge",
            "cyberghost", "pia", "ipvanish", "tunnelbear", "windscribe"
        ]

        // Check explicit flags first
        if geoInfo.isVPN {
            ipType = .vpn
        } else if geoInfo.isProxy {
            ipType = .proxy
        } else if geoInfo.isHosting {
            ipType = .hosting
        } else if vpnKeywords.contains(where: { combinedNames.contains($0) }) {
            // Known VPN provider detected by name
            ipType = .vpn
        } else if datacenterKeywords.contains(where: { combinedNames.contains($0) }) {
            // Known datacenter/cloud provider detected by name
            ipType = .datacenter
        } else if combinedNames.contains("mobile") || combinedNames.contains("cellular") ||
                  combinedNames.contains("wireless") || combinedNames.contains("lte") {
            ipType = .mobile
        } else {
            ipType = .residential
        }

        // Detection signals
        let detectionSignals = VPNDetectionSignals(
            asnType: ipType == .residential || ipType == .mobile ? "Residential" : "Data Center",
            asnOrganization: geoInfo.org ?? "Unknown",
            ipType: ipType,
            isKnownVPNProvider: geoInfo.isVPN,
            isHostingCompany: geoInfo.isHosting,
            ipCountry: geoInfo.country ?? "Unknown",
            ipCity: geoInfo.city,
            mismatchProbability: 0.0,  // Would need browser locale comparison
            sharedIPLikelihood: geoInfo.isVPN || geoInfo.isProxy ? "High (1000+ users)" : "Low (<10 users)",
            ipAgeDays: nil  // Would need IP age database
        )

        // Security leaks
        // NOTE: WebRTC leak tests are NOT applicable to native iOS apps.
        // WebRTC is a browser technology - iOS apps don't have WebRTC stack
        // unless you specifically import one (like for WebRTC video calls).
        // We set these to false because N/A = no leak.
        let securityLeaks = VPNSecurityLeaks(
            dnsServerIP: dns.resolver,
            dnsServerCountry: nil,  // Would need DNS resolver geolocation
            dnsLeakDetected: dns.hijackDetected,  // Simplified - true leak detection needs comparison
            webRTCLocalIPExposed: false,  // N/A for native iOS apps (WebRTC is browser-only)
            webRTCRealIPExposed: false,   // N/A for native iOS apps
            exposedIPs: [],
            ipv6Tunneled: networkStatus.isIPv6Enabled,
            ipv6LeakDetected: false,  // Would need dedicated test
            mtuFragmentationDetected: false,  // Would need packet size analysis
            optimalMTU: nil  // Would need MTU path discovery test
        )

        // Reputation
        let reputation = IPReputation(
            abuseRiskScore: geoInfo.isVPN || geoInfo.isProxy ? 0.4 : 0.1,  // VPNs have higher risk
            botActivityProbability: geoInfo.isVPN ? 0.3 : 0.1,
            knownAbuseFlags: geoInfo.isHosting ? ["Hosting IP"] : [],
            ipTrustScore: ipType == .residential ? 0.8 : (ipType == .datacenter ? 0.3 : 0.5),
            reverseHostname: geoInfo.hostname,
            isResidentialIP: ipType == .residential || ipType == .mobile
        )

        // AI service detection risk reasons
        var aiRiskReasons: [String] = []
        if ipType == .datacenter || ipType == .vpn {
            aiRiskReasons.append("• Datacenter/VPN IP")
        }
        if geoInfo.isVPN {
            aiRiskReasons.append("• Known VPN provider")
        }
        if detectionSignals.sharedIPLikelihood.contains("High") {
            aiRiskReasons.append("• High IP sharing")
        }

        // Service friendliness
        let serviceFriendliness = ServiceFriendliness(
            aiServiceDetectionRisk: detectionSignals.overallDetectionRisk,
            aiServiceRiskReasons: aiRiskReasons,
            streamingCDNLatency: networkStatus.internet.latencyToExternal,
            packetStability: (networkStatus.router.jitter ?? 0) < 20 ? "Stable" : "Unstable",
            mtuHealth: "Unknown",  // Would need MTU test
            chinaRoutingQuality: nil,  // Would need China-specific tests
            overseasRTTInflation: nil
        )

        return VPNVisibilityTestResult(
            timestamp: Date(),
            detectionSignals: detectionSignals,
            securityLeaks: securityLeaks,
            reputation: reputation,
            serviceFriendliness: serviceFriendliness
        )
    }
}
