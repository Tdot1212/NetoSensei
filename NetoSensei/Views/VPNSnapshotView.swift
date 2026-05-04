//
//  VPNSnapshotView.swift
//  NetoSensei
//
//  VPN Snapshot Logging & Comparison Interface
//

import SwiftUI

struct VPNSnapshotView: View {
    @StateObject private var vm = DashboardViewModel()
    @ObservedObject private var snapshotManager = VPNSnapshotManager.shared
    @State private var showingCaptureSheet = false
    @State private var showingComparison = false
    @State private var selectedSnapshots: Set<UUID> = []

    // USER-DECLARED VPN STATE (not auto-detected)
    @State private var userDeclaredVPNState: VPNSnapshot.VPNState = .off
    @State private var userNotes: String = ""
    @State private var isCapturing: Bool = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header explanation
                    headerCard

                    // Capture button
                    captureSnapshotButton

                    // Snapshot list
                    if snapshotManager.snapshots.isEmpty {
                        emptyStateView
                    } else {
                        snapshotListView
                    }

                    // Comparison section
                    if selectedSnapshots.count >= 2 {
                        comparisonButton
                    }
                }
                .padding()
            }
            .navigationTitle("VPN Snapshots")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { selectedSnapshots.removeAll() }) {
                            Label("Clear Selection", systemImage: "xmark.circle")
                        }
                        .disabled(selectedSnapshots.isEmpty)

                        Button(role: .destructive, action: {
                            snapshotManager.deleteAll()
                            selectedSnapshots.removeAll()
                        }) {
                            Label("Delete All", systemImage: "trash")
                        }
                        .disabled(snapshotManager.snapshots.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingCaptureSheet) {
                captureSheet
            }
            .sheet(isPresented: $showingComparison) {
                snapshotComparisonSheet
            }
            .onAppear {
                vm.startMonitoring()
                Task {
                    await vm.refresh()
                }
            }
            .onDisappear {
                vm.stopMonitoring()
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                        .foregroundColor(AppColors.accent)
                    Text("Network State Logger")
                        .font(.headline)
                }

                Text("Declare your network state (VPN ON/OFF), then record diagnostics. Compare snapshots to find the best VPN config or track performance changes over time.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "1.circle.fill")
                            .foregroundColor(.blue)
                        Text("You declare: VPN ON or VPN OFF")
                            .font(.caption)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "2.circle.fill")
                            .foregroundColor(.green)
                        Text("App measures: Speed, latency, DNS, routing")
                            .font(.caption)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "3.circle.fill")
                            .foregroundColor(.orange)
                        Text("Compare: Find what works best for you")
                            .font(.caption)
                    }
                }
                .foregroundColor(AppColors.textSecondary)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    comparisonExample("VPN ON (Japan) vs VPN OFF", "+40ms latency, -15% throughput")
                    comparisonExample("VPN US vs VPN JP", "US faster for YouTube, JP faster for Bilibili")
                    comparisonExample("Morning vs Evening", "ISP congestion detected at peak hours")
                }
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    private func comparisonExample(_ title: String, _ result: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(result)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Capture Button

    private var captureSnapshotButton: some View {
        Button(action: {
            showingCaptureSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                Text("Record Network State")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [AppColors.accent, AppColors.accent.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No network states recorded yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap 'Record Network State' to log your first snapshot. Declare if VPN is ON or OFF, then the app measures everything else.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 60)
    }

    // MARK: - Snapshot List

    private var snapshotListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(snapshotManager.snapshots.count) Snapshots")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(snapshotManager.snapshots) { snapshot in
                SnapshotRow(
                    snapshot: snapshot,
                    isSelected: selectedSnapshots.contains(snapshot.id)
                )
                .onTapGesture {
                    toggleSelection(snapshot.id)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        snapshotManager.deleteSnapshot(snapshot)
                        selectedSnapshots.remove(snapshot.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedSnapshots.contains(id) {
            selectedSnapshots.remove(id)
        } else {
            // Limit to 4 selections max
            if selectedSnapshots.count < 4 {
                selectedSnapshots.insert(id)
            }
        }
    }

    // MARK: - Comparison Button

    private var comparisonButton: some View {
        Button(action: {
            showingComparison = true
        }) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 18))
                Text("Compare Selected (\(selectedSnapshots.count))")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Capture Sheet (Simplified)

    private var captureSheet: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // VPN State Toggle (USER DECLARES)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Declare VPN State")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("Tell us if your VPN is ON or OFF.\nWe'll measure everything else.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        // ON/OFF Toggle
                        Picker("VPN State", selection: $userDeclaredVPNState) {
                            Text("VPN OFF")
                                .tag(VPNSnapshot.VPNState.off)

                            Text("VPN ON")
                                .tag(VPNSnapshot.VPNState.on)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)

                    // Notes Field
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes (Optional)")
                            .font(.headline)

                        Text("Example: \"YouTube buffering stopped after switching to JP node\"")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: $userNotes)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }

                    // Capture Button
                    Button {
                        captureSnapshotWithDiagnostics()
                    } label: {
                        HStack {
                            if isCapturing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Measuring Network...")
                                    .font(.headline)
                            } else {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 20))
                                Text("Record Current Network State")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [AppColors.accent, AppColors.accent.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCapturing)
                }
                .padding()
            }
            .navigationTitle("Record Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingCaptureSheet = false
                        userNotes = ""
                    }
                    .disabled(isCapturing)
                }
            }
        }
    }

    private func captureSnapshotWithDiagnostics() {
        isCapturing = true

        // Capture user input
        let capturedVPNState = userDeclaredVPNState
        let capturedNotes = userNotes

        // Auto-generate label
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, h:mm a"
        let timestamp = dateFormatter.string(from: Date())
        let autoLabel = "\(capturedVPNState.rawValue) - \(timestamp)"

        Task {
            // Step 1: Run full diagnostics to collect all data
            debugLog("🔵 SNAPSHOT: Running full diagnostics...")

            // Refresh network status
            await vm.refresh()

            // Get current state after refresh
            let currentStatus = vm.status
            let geoInfo = vm.geoIPInfo
            let publicIP = vm.publicIP

            debugLog("🔵 SNAPSHOT: GeoIP = \(geoInfo.country ?? "Unknown"), \(geoInfo.city ?? "Unknown")")
            debugLog("🔵 SNAPSHOT: Public IP = \(publicIP)")

            // Step 2: Run speed test to get download/upload (using simple HTTP test)
            let (downloadSpeed, uploadSpeed) = await measureSpeed()

            debugLog("🔵 SNAPSHOT: Speed test = \(downloadSpeed) Mbps down, \(uploadSpeed ?? 0) Mbps up")

            // Step 2.5: Run detailed router measurement for jitter & packet loss (Option B)
            let networkMonitor = NetworkMonitorService.shared
            let detailedRouterInfo = await networkMonitor.measureRouterDetailed()

            debugLog("🔵 SNAPSHOT: Detailed router metrics = jitter: \(detailedRouterInfo.jitter ?? 0)ms, loss: \(detailedRouterInfo.packetLoss ?? 0)%")

            // Step 2.6: Run VPN security tests (Option A)
            let vpnSecurityTest = await performSecurityTests(
                geoInfo: geoInfo,
                publicIP: publicIP,
                currentStatus: currentStatus
            )

            debugLog("🔵 SNAPSHOT: Security analysis complete")

            // Step 3: Create snapshot with all collected data
            var snapshot = VPNSnapshot(
                vpnState: capturedVPNState,
                declaredByUser: true,
                vpnLabel: autoLabel,
                publicIP: publicIP.isEmpty || publicIP == "0.0.0.0" ? "Unknown" : publicIP,
                geo: VPNSnapshot.GeoLocation(
                    country: geoInfo.country ?? "Unknown",
                    countryCode: geoInfo.countryCode ?? "XX",
                    city: geoInfo.city,
                    asn: geoInfo.asn,
                    isp: geoInfo.isp,
                    isVPN: geoInfo.isVPN,
                    isProxy: geoInfo.isProxy
                ),
                performance: VPNSnapshot.PerformanceMetrics(
                    pingAvg: detailedRouterInfo.latency ?? 0,  // ✅ Using detailed measurement
                    internetPing: currentStatus.internet.latencyToExternal,
                    jitter: detailedRouterInfo.jitter ?? 0,  // ✅ Option B: Real jitter measurement
                    packetLoss: detailedRouterInfo.packetLoss ?? 0,  // ✅ Option B: Real packet loss
                    downloadMbps: downloadSpeed,
                    uploadMbps: uploadSpeed
                ),
                dns: VPNSnapshot.DNSMetrics(
                    resolver: currentStatus.dns.resolverIP ?? "Unknown",
                    latencyMs: currentStatus.dns.latency ?? 0,
                    hijackDetected: false,
                    dnsBehavior: currentStatus.dns.lookupSuccess ? "Normal" : "Failed"
                ),
                routing: VPNSnapshot.RoutingMetrics(
                    hopCount: 0,
                    avgHopLatency: 0,
                    routingQuality: "Unknown"
                ),
                network: VPNSnapshot.NetworkMetrics(
                    connectionType: currentStatus.connectionType.map { "\($0)" } ?? "Unknown",
                    wifiSSID: currentStatus.wifi.ssid,
                    wifiBSSID: currentStatus.wifi.bssid,
                    wifiRSSI: currentStatus.wifi.rssi,
                    wifiNoise: currentStatus.wifi.noise,
                    wifiLinkSpeed: currentStatus.wifi.linkSpeed,
                    wifiChannel: currentStatus.wifi.channel,
                    wifiChannelWidth: currentStatus.wifi.channelWidth,
                    wifiBand: currentStatus.wifi.band,
                    wifiPHYMode: currentStatus.wifi.phyMode,
                    wifiMCSIndex: currentStatus.wifi.mcsIndex,
                    wifiNSS: currentStatus.wifi.nss,
                    localIP: currentStatus.localIP
                ),
                vpnVisibilityTest: vpnSecurityTest  // ✅ Option A: VPN Security Data
            )

            // Add user notes if provided
            if !capturedNotes.isEmpty {
                snapshot.userNotes = capturedNotes
            }

            // Step 4: Save snapshot
            await MainActor.run {
                snapshotManager.snapshots.insert(snapshot, at: 0)

                // Trim to max limit (50 snapshots)
                if snapshotManager.snapshots.count > 50 {
                    snapshotManager.snapshots = Array(snapshotManager.snapshots.prefix(50))
                }
            }

            // FIXED: Use safe save to prevent UserDefaults crash from large snapshot data
            Task.detached { [snapshots = snapshotManager.snapshots, notes = capturedNotes] in
                UserDefaults.standard.setSafe(snapshots, forKey: "vpn_snapshots", maxItems: 50)
                debugLog("✅ SNAPSHOT: Saved to disk with notes: \(notes.isEmpty ? "none" : notes)")
            }

            // Close sheet and reset
            await MainActor.run {
                isCapturing = false
                showingCaptureSheet = false
                userNotes = ""
            }
        }
    }

    // Simple speed test using HTTP download and upload
    // FIXED: Now measures BOTH download AND upload using same endpoints as SpeedTestEngine
    private func measureSpeed() async -> (Double, Double?) {
        var downloadSpeed: Double = 0
        var uploadSpeed: Double? = nil

        // Download test - fetch a 5MB file for better accuracy
        let downloadURL = "https://speed.cloudflare.com/__down?bytes=5000000"  // 5MB

        do {
            guard let url = URL(string: downloadURL) else {
                return (0, nil)
            }

            let startDownload = Date()
            let (data, _) = try await URLSession.shared.data(from: url)
            let downloadDuration = Date().timeIntervalSince(startDownload)

            // Calculate download speed in Mbps
            let downloadBytes = Double(data.count)
            let downloadMegabits = (downloadBytes * 8) / 1_000_000
            downloadSpeed = downloadMegabits / downloadDuration

            debugLog("🔵 SNAPSHOT: Downloaded \(Int(downloadBytes)) bytes in \(String(format: "%.1f", downloadDuration))s = \(String(format: "%.1f", downloadSpeed)) Mbps")

        } catch {
            debugLog("❌ SNAPSHOT: Download test failed: \(error)")
        }

        // Upload test - POST 2MB to Cloudflare (same endpoint as SpeedTestEngine)
        // FIXED: This was previously skipped, causing 0.0 Mbps upload
        do {
            let uploadURL = "https://speed.cloudflare.com/__up"
            guard let url = URL(string: uploadURL) else {
                return (downloadSpeed, nil)
            }

            // Generate 2MB of test data (smaller than main test for quick snapshot)
            let testData = Data(repeating: 0, count: 2_000_000)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = testData
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30  // 30 second timeout for upload

            let startUpload = Date()
            let (_, _) = try await URLSession.shared.data(for: request)
            let uploadDuration = Date().timeIntervalSince(startUpload)

            // Calculate upload speed in Mbps
            let uploadBytes = Double(testData.count)
            let uploadMegabits = (uploadBytes * 8) / 1_000_000
            uploadSpeed = uploadMegabits / uploadDuration

            debugLog("🔵 SNAPSHOT: Uploaded \(Int(uploadBytes)) bytes in \(String(format: "%.1f", uploadDuration))s = \(String(format: "%.1f", uploadSpeed ?? 0)) Mbps")

        } catch {
            debugLog("❌ SNAPSHOT: Upload test failed: \(error)")
            // Return download speed even if upload fails
        }

        return (downloadSpeed, uploadSpeed)
    }

    // VPN Security Testing (Option A: DNS leaks, IP reputation, detection risk)
    private func performSecurityTests(
        geoInfo: GeoIPInfo,
        publicIP: String,
        currentStatus: NetworkStatus
    ) async -> VPNVisibilityTestResult {
        debugLog("🔐 SECURITY TEST: Starting VPN visibility analysis...")

        // 1. VPN Detection Signals
        let detectionSignals = analyzeDetectionSignals(geoInfo: geoInfo)
        debugLog("🔐 SECURITY TEST: Detection risk = \(detectionSignals.overallDetectionRisk.rawValue)")

        // 2. Security Leaks (DNS, WebRTC, IPv6)
        let securityLeaks = await analyzeSecurityLeaks(
            geoInfo: geoInfo,
            publicIP: publicIP,
            currentStatus: currentStatus
        )
        debugLog("🔐 SECURITY TEST: Security rating = \(securityLeaks.securityRating)")

        // 3. IP Reputation
        let reputation = analyzeIPReputation(geoInfo: geoInfo)
        debugLog("🔐 SECURITY TEST: Trust rating = \(reputation.trustRating)")

        // 4. Service Friendliness
        let serviceFriendliness = analyzeServiceFriendliness(
            detectionSignals: detectionSignals,
            currentStatus: currentStatus
        )
        debugLog("🔐 SECURITY TEST: AI service risk = \(serviceFriendliness.aiServiceDetectionRisk.rawValue)")

        return VPNVisibilityTestResult(
            timestamp: Date(),
            detectionSignals: detectionSignals,
            securityLeaks: securityLeaks,
            reputation: reputation,
            serviceFriendliness: serviceFriendliness
        )
    }

    // Analyze VPN Detection Signals (IP type, ASN, detection risk)
    // FIXED: Use same comprehensive keyword matching as VPNSnapshotManager
    // This ensures snapshot and live analysis return consistent results
    private func analyzeDetectionSignals(geoInfo: GeoIPInfo) -> VPNDetectionSignals {
        // Determine IP type based on flags, ASN, and known providers
        let ipType: IPType
        let orgLower = (geoInfo.org ?? "").lowercased()
        let ispLower = (geoInfo.isp ?? "").lowercased()
        let combinedNames = orgLower + " " + ispLower

        // FIXED: Comprehensive list of known datacenter/cloud/VPN providers
        // Same list as VPNSnapshotManager.createVPNVisibilityTest
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

        // Estimate IP sharing likelihood based on IP type
        var sharedIPLikelihood = "Low (<10 users)"
        if geoInfo.isVPN || geoInfo.isProxy || ipType == .vpn || ipType == .proxy {
            sharedIPLikelihood = "High (1000+ users)"
        } else if ipType == .datacenter || ipType == .hosting {
            sharedIPLikelihood = "Medium (100-1000 users)"
        }

        return VPNDetectionSignals(
            asnType: ipType == .residential || ipType == .mobile ? "Residential" : "Data Center",
            asnOrganization: geoInfo.asnOrg ?? geoInfo.isp ?? "Unknown",
            ipType: ipType,
            isKnownVPNProvider: geoInfo.isVPN || ipType == .vpn,
            isHostingCompany: geoInfo.isHosting || ipType == .hosting || ipType == .datacenter,
            ipCountry: geoInfo.country ?? "Unknown",
            ipCity: geoInfo.city,
            mismatchProbability: 0.0,  // Would require user location comparison
            sharedIPLikelihood: sharedIPLikelihood,
            ipAgeDays: nil  // Not available from current GeoIP
        )
    }

    // Analyze Security Leaks (DNS, WebRTC, IPv6)
    private func analyzeSecurityLeaks(
        geoInfo: GeoIPInfo,
        publicIP: String,
        currentStatus: NetworkStatus
    ) async -> VPNSecurityLeaks {
        // 1. DNS Leak Detection
        let dnsServerIP = currentStatus.dns.resolverIP ?? "Unknown"
        var dnsLeakDetected = false
        var dnsServerCountry: String? = nil

        // If VPN is detected but DNS resolver is different, might be a leak
        // Simplified: Check if DNS resolver IP matches public IP prefix
        if geoInfo.isVPN {
            let publicIPPrefix = String(publicIP.prefix(upTo: publicIP.firstIndex(of: ".") ?? publicIP.endIndex))
            let dnsIPPrefix = String(dnsServerIP.prefix(upTo: dnsServerIP.firstIndex(of: ".") ?? dnsServerIP.endIndex))

            // If prefixes don't match, potential DNS leak
            if publicIPPrefix != dnsIPPrefix && dnsServerIP != "Unknown" {
                dnsLeakDetected = true
                dnsServerCountry = "Different from VPN"
            }
        }

        // 2. WebRTC Leak Detection (simplified for iOS)
        // iOS doesn't expose WebRTC APIs easily, so we'll check if local IP is exposed
        let webRTCLocalIPExposed = currentStatus.localIP != nil
        let webRTCRealIPExposed = false  // Can't easily test on iOS
        var exposedIPs: [String] = []
        if let localIP = currentStatus.localIP {
            exposedIPs.append(localIP)
        }

        // 3. IPv6 Leak Detection
        let ipv6Tunneled = currentStatus.isIPv6Enabled && geoInfo.isVPN
        let ipv6LeakDetected = currentStatus.isIPv6Enabled && !geoInfo.isVPN && geoInfo.ipVersion == "IPv6"

        // 4. MTU Fragmentation Detection (simplified)
        // Check if connection quality suggests MTU issues
        let mtuFragmentationDetected = (currentStatus.router.packetLoss ?? 0) > 2.0
        let optimalMTU = mtuFragmentationDetected ? 1280 : 1500

        return VPNSecurityLeaks(
            dnsServerIP: dnsServerIP,
            dnsServerCountry: dnsServerCountry,
            dnsLeakDetected: dnsLeakDetected,
            webRTCLocalIPExposed: webRTCLocalIPExposed,
            webRTCRealIPExposed: webRTCRealIPExposed,
            exposedIPs: exposedIPs,
            ipv6Tunneled: ipv6Tunneled,
            ipv6LeakDetected: ipv6LeakDetected,
            mtuFragmentationDetected: mtuFragmentationDetected,
            optimalMTU: optimalMTU
        )
    }

    // Analyze IP Reputation (abuse score, trust score)
    private func analyzeIPReputation(geoInfo: GeoIPInfo) -> IPReputation {
        // Calculate abuse risk based on GeoIP flags
        var abuseRiskScore = 0.0
        var knownAbuseFlags: [String] = []

        if geoInfo.isVPN {
            abuseRiskScore += 0.3
        }
        if geoInfo.isProxy {
            abuseRiskScore += 0.4
            knownAbuseFlags.append("Proxy")
        }
        if geoInfo.isTor {
            abuseRiskScore += 0.5
            knownAbuseFlags.append("Tor Exit Node")
        }
        if geoInfo.isHosting {
            abuseRiskScore += 0.2
        }

        // Calculate trust score (inverse of abuse risk)
        let ipTrustScore = 1.0 - min(abuseRiskScore, 1.0)

        // Bot activity probability (higher for proxies/VPNs)
        let botActivityProbability = geoInfo.isProxy || geoInfo.isTor ? 0.6 : 0.1

        // Residential IP determination
        let isResidentialIP = !geoInfo.isVPN && !geoInfo.isProxy && !geoInfo.isHosting && !geoInfo.isTor

        return IPReputation(
            abuseRiskScore: abuseRiskScore,
            botActivityProbability: botActivityProbability,
            knownAbuseFlags: knownAbuseFlags,
            ipTrustScore: ipTrustScore,
            reverseHostname: geoInfo.hostname,
            isResidentialIP: isResidentialIP
        )
    }

    // Analyze Service Friendliness (AI services, streaming, China routing)
    private func analyzeServiceFriendliness(
        detectionSignals: VPNDetectionSignals,
        currentStatus: NetworkStatus
    ) -> ServiceFriendliness {
        // AI Service Detection Risk
        var aiServiceDetectionRisk: DetectionRisk = .low
        var aiServiceRiskReasons: [String] = []

        if detectionSignals.ipType == .datacenter || detectionSignals.ipType == .vpn {
            aiServiceDetectionRisk = .high
            aiServiceRiskReasons.append("Datacenter/VPN IP type")
        } else if detectionSignals.ipType == .hosting {
            aiServiceDetectionRisk = .medium
            aiServiceRiskReasons.append("Hosting provider IP")
        }

        if detectionSignals.isKnownVPNProvider {
            aiServiceDetectionRisk = .high
            aiServiceRiskReasons.append("Known VPN provider")
        }

        if detectionSignals.sharedIPLikelihood.contains("High") {
            if aiServiceDetectionRisk == .low {
                aiServiceDetectionRisk = .medium
            }
            aiServiceRiskReasons.append("High IP sharing detected")
        }

        if aiServiceRiskReasons.isEmpty {
            aiServiceRiskReasons.append("No obvious detection indicators")
        }

        // Streaming compatibility
        let streamingCDNLatency = currentStatus.internet.latencyToExternal ?? 100.0
        let packetStability = (currentStatus.router.packetLoss ?? 0) < 1.0 ? "Stable" : "Unstable"
        let mtuHealth = (currentStatus.router.packetLoss ?? 0) > 2.0 ? "Fragmentation Detected" : "Optimal"

        return ServiceFriendliness(
            aiServiceDetectionRisk: aiServiceDetectionRisk,
            aiServiceRiskReasons: aiServiceRiskReasons,
            streamingCDNLatency: streamingCDNLatency,
            packetStability: packetStability,
            mtuHealth: mtuHealth,
            chinaRoutingQuality: nil,  // Would require GFW-specific tests
            overseasRTTInflation: nil
        )
    }


    // MARK: - Comparison Sheet

    private var snapshotComparisonSheet: some View {
        NavigationView {
            let selected = snapshotManager.snapshots.filter { selectedSnapshots.contains($0.id) }
            SnapshotComparisonView(snapshots: selected)
                .navigationTitle("Comparison")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingComparison = false
                        }
                    }
                }
        }
    }
}

// MARK: - Snapshot Row

struct SnapshotRow: View {
    let snapshot: VPNSnapshot
    let isSelected: Bool

    var body: some View {
        CardView {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .green : .gray)

                VStack(alignment: .leading, spacing: 6) {
                    // Label & VPN state
                    HStack {
                        Text(snapshot.vpnLabel)
                            .font(.headline)
                        Spacer()
                        Text(snapshot.vpnState.rawValue)
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(snapshot.vpnState == .on ? Color.green : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }

                    // Location & Timestamp
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.geo.displayLocation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if let isp = snapshot.geo.isp {
                                Text("ISP: \(isp)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(snapshot.qualityRating)
                            .font(.caption)
                            .foregroundColor(qualityColor)
                    }

                    Divider()

                    // Key metrics
                    HStack(spacing: 16) {
                        metricView("Speed", "\(String(format: "%.0f", snapshot.performance.downloadMbps)) Mbps")
                        metricView("Ping", "\(String(format: "%.0f", snapshot.performance.pingAvg))ms")
                        metricView("Jitter", "\(String(format: "%.0f", snapshot.performance.jitter))ms")
                        metricView("Loss", "\(String(format: "%.1f", snapshot.performance.packetLoss))%")
                    }
                    .font(.caption)

                    // Stability & Congestion Analysis
                    if let stability = snapshot.stabilityMetrics {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: stability.isDeliveryStable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(stability.isDeliveryStable ? .green : .orange)
                                    .font(.caption2)
                                Text("Delivery: \(stability.stabilityQuality)")
                                    .font(.caption2.bold())
                            }
                        }
                    }

                    // Congestion Type
                    if let congestion = snapshot.congestionAnalysis,
                       congestion.type != .noCongestion {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: congestionIcon(congestion.type))
                                    .foregroundColor(congestionColor(congestion.type))
                                    .font(.caption2)
                                Text("\(congestion.type.rawValue)")
                                    .font(.caption2.bold())
                                    .foregroundColor(congestionColor(congestion.type))
                            }
                        }
                    }

                    // User notes if available
                    if let notes = snapshot.userNotes, !notes.isEmpty {
                        Divider()
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "note.text")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    // WiFi Radio State (comprehensive)
                    if let ssid = snapshot.network.wifiSSID {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            // SSID + BSSID
                            HStack(spacing: 4) {
                                Image(systemName: "wifi")
                                    .font(.caption2)
                                Text("SSID: \(ssid)")
                                    .font(.caption2.bold())
                                if let bssid = snapshot.network.wifiBSSID {
                                    Text("• \(bssid)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .foregroundColor(.primary)

                            // SNR (VERY IMPORTANT)
                            if let snr = snapshot.network.snr {
                                HStack(spacing: 4) {
                                    Text("SNR: \(snr)dB")
                                        .font(.caption2.bold())
                                        .foregroundColor(snrColor(snr))
                                    Text("(\(snapshot.network.snrQuality))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // RSSI + Noise
                            HStack(spacing: 8) {
                                if let rssi = snapshot.network.wifiRSSI {
                                    Text("RSSI: \(rssi)dBm")
                                        .font(.caption2)
                                }
                                if let noise = snapshot.network.wifiNoise {
                                    Text("Noise: \(noise)dBm")
                                        .font(.caption2)
                                }
                            }
                            .foregroundColor(.secondary)

                            // Channel + Width + Band
                            HStack(spacing: 8) {
                                if let channel = snapshot.network.wifiChannel {
                                    Text("Ch: \(channel)")
                                        .font(.caption2)
                                }
                                if let width = snapshot.network.wifiChannelWidth {
                                    Text("\(width)MHz")
                                        .font(.caption2)
                                }
                                if let band = snapshot.network.wifiBand {
                                    Text("\(band)")
                                        .font(.caption2)
                                }
                            }
                            .foregroundColor(.secondary)

                            // TX Rate + PHY Mode
                            HStack(spacing: 8) {
                                if let txRate = snapshot.network.wifiLinkSpeed {
                                    Text("TX: \(txRate)Mbps")
                                        .font(.caption2)
                                }
                                if let phy = snapshot.network.wifiPHYMode {
                                    Text("\(phy)")
                                        .font(.caption2)
                                }
                            }
                            .foregroundColor(.secondary)

                            // Advanced: MCS Index + NSS
                            if let mcs = snapshot.network.wifiMCSIndex,
                               let nss = snapshot.network.wifiNSS {
                                HStack(spacing: 4) {
                                    Text("MCS: \(mcs)")
                                        .font(.caption2)
                                    Text("NSS: \(nss)")
                                        .font(.caption2)
                                    Text("(\(snapshot.network.modulationQuality))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // VPN Visibility & Detection Risk (when VPN is ON)
                    if let vpnTest = snapshot.vpnVisibilityTest {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            // Header
                            HStack(spacing: 4) {
                                Image(systemName: "eye.trianglebadge.exclamationmark")
                                    .font(.caption)
                                    .foregroundColor(detectionRiskColor(vpnTest.detectionSignals.overallDetectionRisk))
                                Text("VPN Detection Risk")
                                    .font(.caption.bold())
                                    .foregroundColor(.primary)
                            }

                            // Overall assessment
                            HStack(spacing: 4) {
                                Text(vpnTest.overallAssessment)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            // Detection signals
                            HStack(spacing: 8) {
                                Text("IP Type: \(vpnTest.detectionSignals.ipType.rawValue)")
                                    .font(.caption2)
                                    .foregroundColor(detectionRiskColor(vpnTest.detectionSignals.overallDetectionRisk))
                            }

                            // Security rating
                            HStack(spacing: 8) {
                                Text("Security: \(vpnTest.securityLeaks.securityRating)")
                                    .font(.caption2)
                                    .foregroundColor(vpnTest.securityLeaks.hasLeaks ? .red : .green)
                                Text("Trust: \(vpnTest.reputation.trustRating)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            // AI service detection risk
                            HStack(spacing: 4) {
                                Image(systemName: "brain")
                                    .font(.caption2)
                                Text("AI Service Risk: \(vpnTest.serviceFriendliness.aiServiceDetectionRisk.rawValue)")
                                    .font(.caption2)
                                    .foregroundColor(detectionRiskColor(vpnTest.serviceFriendliness.aiServiceDetectionRisk))
                            }

                            // Block reason if any
                            if let blockReason = vpnTest.likelyBlockReason {
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    Text(blockReason)
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func metricView(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .foregroundColor(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var qualityColor: Color {
        switch snapshot.qualityRating {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        default: return .red
        }
    }

    private func snrColor(_ snr: Int) -> Color {
        // SNR (Signal-to-Noise Ratio) thresholds
        // > 30 dB = Excellent
        // 20-30 dB = OK
        // < 20 dB = Poor (congestion/interference)
        if snr > 30 { return .green }
        if snr >= 20 { return .orange }
        return .red
    }

    private func congestionIcon(_ type: CongestionType) -> String {
        switch type {
        case .channelCongestion: return "antenna.radiowaves.left.and.right"
        case .routerCongestion: return "server.rack"
        case .compoundCongestion: return "exclamationmark.triangle"
        case .noCongestion: return "checkmark.circle"
        }
    }

    private func congestionColor(_ type: CongestionType) -> Color {
        switch type {
        case .channelCongestion: return .orange
        case .routerCongestion: return .red
        case .compoundCongestion: return .purple
        case .noCongestion: return .green
        }
    }

    private func detectionRiskColor(_ risk: DetectionRisk) -> Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Comparison View

struct SnapshotComparisonView: View {
    let snapshots: [VPNSnapshot]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if snapshots.count == 2 {
                    twoWayComparison
                } else {
                    multiWayComparison
                }
            }
            .padding()
        }
    }

    // MARK: - Two-Way Comparison

    private var twoWayComparison: some View {
        let comparison = VPNSnapshotComparison(baseline: snapshots[0], comparison: snapshots[1])

        return VStack(spacing: 20) {
            // Winner card
            CardView {
                VStack(spacing: 12) {
                    Text("🏆 Winner")
                        .font(.headline)
                    Text(comparison.winner.vpnLabel)
                        .font(.title2.bold())
                    Text(comparison.summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Detailed comparison
            CardView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Detailed Comparison")
                        .font(.headline)

                    comparisonRow("Throughput",
                                  snapshots[0].performance.downloadMbps,
                                  snapshots[1].performance.downloadMbps,
                                  "Mbps",
                                  higherIsBetter: true)

                    comparisonRow("Latency",
                                  snapshots[0].performance.pingAvg,
                                  snapshots[1].performance.pingAvg,
                                  "ms",
                                  higherIsBetter: false)

                    comparisonRow("Jitter",
                                  snapshots[0].performance.jitter,
                                  snapshots[1].performance.jitter,
                                  "ms",
                                  higherIsBetter: false)

                    comparisonRow("Packet Loss",
                                  snapshots[0].performance.packetLoss,
                                  snapshots[1].performance.packetLoss,
                                  "%",
                                  higherIsBetter: false)

                    comparisonRow("DNS",
                                  snapshots[0].dns.latencyMs,
                                  snapshots[1].dns.latencyMs,
                                  "ms",
                                  higherIsBetter: false)
                }
            }
        }
    }

    private func comparisonRow(_ label: String, _ value1: Double, _ value2: Double, _ unit: String, higherIsBetter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.bold())

            HStack {
                valueCell(snapshots[0].vpnLabel, value1, unit, isWinner: higherIsBetter ? value1 > value2 : value1 < value2)
                Text("vs")
                    .foregroundColor(.secondary)
                valueCell(snapshots[1].vpnLabel, value2, unit, isWinner: higherIsBetter ? value2 > value1 : value2 < value1)
            }

            let delta = value2 - value1
            let deltaPercent = (delta / value1) * 100

            Text("\(delta > 0 ? "+" : "")\(String(format: "%.1f", delta)) \(unit) (\(delta > 0 ? "+" : "")\(String(format: "%.0f", deltaPercent))%)")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()
        }
    }

    private func valueCell(_ label: String, _ value: Double, _ unit: String, isWinner: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Text(String(format: "%.1f", value))
                    .font(.body.bold())
                    .foregroundColor(isWinner ? .green : .primary)
                Text(unit)
                    .font(.caption)
                if isWinner {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(isWinner ? Color.green.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }

    // MARK: - Multi-Way Comparison

    private var multiWayComparison: some View {
        VStack(spacing: 16) {
            Text("Comparing \(snapshots.count) snapshots")
                .font(.headline)

            ForEach(snapshots.sorted(by: { $0.qualityScore > $1.qualityScore })) { snapshot in
                CardView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(snapshot.vpnLabel)
                                .font(.headline)
                            Spacer()
                            Text("Score: \(Int(snapshot.qualityScore))")
                                .font(.subheadline.bold())
                                .foregroundColor(.green)
                        }

                        Text("\(snapshot.geo.country) • \(snapshot.shortTimestamp)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Throughput")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(String(format: "%.0f", snapshot.performance.downloadMbps)) Mbps")
                                    .font(.body.bold())
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Latency")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(String(format: "%.0f", snapshot.performance.pingAvg))ms")
                                    .font(.body.bold())
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    VPNSnapshotView()
}
