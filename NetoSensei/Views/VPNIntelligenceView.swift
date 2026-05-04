//
//  VPNIntelligenceView.swift
//  NetoSensei
//
//  Unified VPN Intelligence View
//  Combines: VPN Reliability, Mode Benchmark, Failure Prediction, Auto-Scoring
//

import SwiftUI

struct VPNIntelligenceView: View {
    @StateObject private var vm = VPNIntelligenceViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header - Best Setup Recommendation or "No Data" card
                    if let recommendation = vm.bestSetup {
                        bestSetupCard(recommendation)
                    } else {
                        noVPNDataCard
                    }

                    // COMPREHENSIVE VPN INTELLIGENCE - ALL IN ONE PAGE

                    // 1. LIVE SECURITY ANALYSIS
                    liveSecuritySection()

                    // 2. CURRENT VPN STATUS & PREDICTION
                    if let prediction = vm.failurePrediction {
                        currentStatusCard(prediction)
                    }

                    // 3. RELIABILITY STATS
                    if let reliability = vm.reliabilityReport {
                        quickStatsCard(reliability)
                    }

                    // 4. VPN MODE COMPARISON (Benchmarks)
                    if let comparison = vm.modeComparison {
                        modeComparisonCard(comparison)
                    }
                }
                .padding()
            }
            .navigationTitle("VPN Intelligence")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await vm.refreshAll()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isLoading)
                }
            }
            .onAppear {
                // FIXED: Only load if not already loaded to prevent freeze
                Task {
                    await vm.loadIfNeeded()
                }
            }
            .onDisappear {
                vm.cancel()
            }
        }
    }

    // MARK: - Best Setup Card

    private func bestSetupCard(_ setup: VPNSetupScore) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "star.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR BEST VPN SETUP")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(setup.setupDescription)
                            .font(.title3.bold())

                        Text("Score: \(setup.overallScore)/100 (\(setup.grade))")
                            .font(.subheadline)
                            .foregroundColor(scoreColor(setup.overallScore))
                    }

                    Spacer()
                }

                Divider()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricBox(
                        title: "Speed",
                        value: String(format: "%.1f Mbps", setup.downloadSpeed),
                        color: .blue
                    )

                    MetricBox(
                        title: "Latency",
                        value: String(format: "%.0f ms", setup.averageLatency),
                        color: .green
                    )

                    MetricBox(
                        title: "Stability",
                        value: "\(setup.stabilityScore)/100",
                        color: .orange
                    )

                    MetricBox(
                        title: "Privacy",
                        value: "\(setup.privacyScore)/100",
                        color: .purple
                    )
                }
            }
        }
    }

    // MARK: - No VPN Data Card

    private var noVPNDataCard: some View {
        CardView {
            VStack(spacing: 16) {
                Image(systemName: "shield.slash")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)

                VStack(spacing: 8) {
                    Text("No VPN Data Yet")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("To see your best VPN setup, connect to a VPN and run a speed test. The app will track your VPN performance over time and recommend your optimal configuration.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Connect to your VPN", systemImage: "1.circle.fill")
                        .font(.caption)
                    Label("Go to Speed tab and run a test", systemImage: "2.circle.fill")
                        .font(.caption)
                    Label("Come back here for recommendations", systemImage: "3.circle.fill")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Live Security Section

    @ViewBuilder
    private func liveSecuritySection() -> some View {
        VStack(spacing: 16) {
            // Live Security Analysis Button
            Button(action: {
                Task {
                    await vm.runLiveSecurityAnalysis()
                }
            }) {
                HStack {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 18))
                    Text(vm.isAnalyzingSecurity ? "Analyzing..." : "Run Live Security Analysis")
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
            .disabled(vm.isAnalyzingSecurity)

            // Display security data
            if let vpnTest = vm.liveSecurityTest {
                // Overall Assessment Card
                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .font(.title2)
                                .foregroundColor(AppColors.accent)
                            Text("VPN Security Analysis")
                                .font(.headline)
                        }

                        Text(vpnTest.overallAssessment)
                            .font(.subheadline.bold())
                            .foregroundColor(vpnTest.securityLeaks.hasLeaks ? .red : .green)

                        Text("Live Analysis • \(vpnTest.timestamp.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Plain-English Summary Card
                plainEnglishSummaryCard(vpnTest: vpnTest)

                // Detection Risk Card
                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("VPN Detection Risk")
                            .font(.headline)

                        HStack {
                            Text("Risk Level:")
                                .font(.subheadline)
                            Spacer()
                            Text(vpnTest.detectionSignals.overallDetectionRisk.rawValue)
                                .font(.subheadline.bold())
                                .foregroundColor(detectionRiskColor(vpnTest.detectionSignals.overallDetectionRisk))
                        }

                        HStack {
                            Text("IP Type:")
                                .font(.subheadline)
                            Spacer()
                            Text(vpnTest.detectionSignals.ipType.rawValue)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Known VPN Provider:")
                                .font(.subheadline)
                            Spacer()
                            Text(vpnTest.detectionSignals.isKnownVPNProvider ? "Yes" : "No")
                                .font(.subheadline.bold())
                                .foregroundColor(vpnTest.detectionSignals.isKnownVPNProvider ? .red : .green)
                        }

                        HStack {
                            Text("IP Sharing:")
                                .font(.subheadline)
                            Spacer()
                            Text(vpnTest.detectionSignals.sharedIPLikelihood)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let blockReason = vpnTest.likelyBlockReason {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Likely Block Reason:")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                                Text(blockReason)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }

                // Security Leaks Card
                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Security Leaks")
                            .font(.headline)

                        HStack {
                            Text("Security Rating:")
                                .font(.subheadline)
                            Spacer()
                            Text(vpnTest.securityLeaks.securityRating)
                                .font(.subheadline.bold())
                                .foregroundColor(vpnTest.securityLeaks.hasLeaks ? .red : .green)
                        }

                        Divider()

                        // FIXED: Don't show green checkmark when DNS server is Unknown
                        // Previously showed contradictory "Unknown" with green checkmark
                        dnsLeakStatusRow(
                            dnsLeakDetected: vpnTest.securityLeaks.dnsLeakDetected,
                            dnsServerIP: vpnTest.securityLeaks.dnsServerIP
                        )

                        // WebRTC Leak Test - N/A for native iOS apps
                        // WebRTC is a browser technology that allows peer-to-peer connections.
                        // Native iOS apps don't have a WebRTC stack unless specifically implemented.
                        webRTCStatusRow()

                        // IPv6 with context
                        ipv6StatusRow(
                            leakDetected: vpnTest.securityLeaks.ipv6LeakDetected,
                            tunneled: vpnTest.securityLeaks.ipv6Tunneled
                        )

                        if vpnTest.securityLeaks.mtuFragmentationDetected {
                            leakStatusRow(
                                icon: "square.split.2x1",
                                label: "MTU Issues",
                                status: true,
                                details: "Optimal: \(vpnTest.securityLeaks.optimalMTU ?? 1500) bytes"
                            )
                        }
                    }
                }

                // IP Reputation Card
                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("IP Reputation")
                            .font(.headline)

                        HStack {
                            Text("Trust Score:")
                                .font(.subheadline)
                            Spacer()
                            Text(vpnTest.reputation.trustRating)
                                .font(.subheadline.bold())
                                .foregroundColor(vpnTest.reputation.trustRating == "High" ? .green : (vpnTest.reputation.trustRating == "Medium" ? .orange : .red))
                        }

                        HStack {
                            Text("Abuse Risk:")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(vpnTest.reputation.abuseRiskScore * 100))%")
                                .font(.subheadline.bold())
                                .foregroundColor(vpnTest.reputation.abuseRiskScore > 0.5 ? .red : .green)
                        }

                        HStack {
                            Text("Residential IP:")
                                .font(.subheadline)
                            Spacer()
                            Text(vpnTest.reputation.isResidentialIP ? "Yes" : "No")
                                .font(.subheadline.bold())
                                .foregroundColor(vpnTest.reputation.isResidentialIP ? .green : .orange)
                        }

                        if !vpnTest.reputation.knownAbuseFlags.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Abuse Flags:")
                                    .font(.caption.bold())
                                    .foregroundColor(.red)
                                ForEach(vpnTest.reputation.knownAbuseFlags, id: \.self) { flag in
                                    Text("• \(flag)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }

                // AI Service Detection Card
                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI Service Compatibility")
                            .font(.headline)

                        HStack {
                            Text("Detection Risk:")
                                .font(.subheadline)
                            Spacer()
                            Text(vpnTest.serviceFriendliness.aiServiceDetectionRisk.rawValue)
                                .font(.subheadline.bold())
                                .foregroundColor(detectionRiskColor(vpnTest.serviceFriendliness.aiServiceDetectionRisk))
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Risk Reasons:")
                                .font(.caption.bold())
                            ForEach(vpnTest.serviceFriendliness.aiServiceRiskReasons, id: \.self) { reason in
                                Text("• \(reason)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let latency = vpnTest.serviceFriendliness.streamingCDNLatency {
                            Divider()
                            HStack {
                                Text("Streaming Quality:")
                                    .font(.subheadline)
                                Spacer()
                                Text(vpnTest.serviceFriendliness.streamingRating)
                                    .font(.subheadline.bold())
                            }

                            Text("CDN Latency: \(Int(latency))ms • \(vpnTest.serviceFriendliness.packetStability)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

            } else {
                // Empty State
                CardView {
                    VStack(spacing: 16) {
                        Image(systemName: "shield.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("No Security Data Available")
                            .font(.headline)

                        Text("Tap 'Run Live Security Analysis' above to check your current connection for VPN detection risk, security leaks, and IP reputation.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 40)
                }
            }
        }
    }

    private func leakStatusRow(icon: String, label: String, status: Bool, details: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(status ? .red : .green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: status ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(status ? .red : .green)
                }

                Text(details)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Special DNS leak status row that handles "Unknown" state properly.
    /// FIXED: Don't show green checkmark when DNS server is unknown - that's misleading.
    private func dnsLeakStatusRow(dnsLeakDetected: Bool, dnsServerIP: String) -> some View {
        let isUnknown = dnsServerIP.isEmpty || dnsServerIP == "Unknown"

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "network")
                .foregroundColor(dnsLeakDetected ? .red : (isUnknown ? .orange : .green))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("DNS Leak")
                        .font(.subheadline)
                    Spacer()

                    if dnsLeakDetected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    } else if isUnknown {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                if dnsLeakDetected {
                    Text("DNS leak detected: \(dnsServerIP)")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if isUnknown {
                    Text("DNS server could not be determined")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("DNS server: \(dnsServerIP)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Plain-English Summary Card

    private func plainEnglishSummaryCard(vpnTest: VPNVisibilityTestResult) -> some View {
        let risk = vpnTest.detectionSignals.overallDetectionRisk
        let hasLeaks = vpnTest.securityLeaks.hasLeaks
        let ipType = vpnTest.detectionSignals.ipType

        return CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "text.bubble")
                        .font(.title2)
                        .foregroundColor(AppColors.accent)
                    Text("What This Means")
                        .font(.headline)
                }

                // Generate plain-English explanation
                VStack(alignment: .leading, spacing: 8) {
                    if hasLeaks {
                        Text("⚠️ Security Issue Detected")
                            .font(.subheadline.bold())
                            .foregroundColor(.red)
                        Text("Your VPN has security leaks. Your real identity may be visible to websites despite using a VPN. Check the \"Security Leaks\" section below for details.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if risk == .high {
                        Text("🔍 Your VPN is Detectable")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                        Text("Websites can likely tell you're using a VPN because your IP belongs to a \(ipType.rawValue.lowercased()). This means some streaming services and AI tools may block you — not because you're doing anything wrong, but because they block all VPN users.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if risk == .medium {
                        Text("🔶 Some Detection Indicators")
                            .font(.subheadline.bold())
                            .foregroundColor(.yellow)
                        Text("Your connection shows some signs of being a VPN. Most websites won't care, but strict services like banking or AI tools might ask for extra verification.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("✅ Looking Good")
                            .font(.subheadline.bold())
                            .foregroundColor(.green)
                        Text("Your VPN is working well with no obvious detection indicators. Your connection appears similar to a regular residential internet user.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Actionable tip
                    Divider()

                    if hasLeaks {
                        Label("Tip: Check your VPN's DNS and IPv6 settings, or try a different VPN provider.", systemImage: "lightbulb")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if risk == .high {
                        Label("Tip: If you're being blocked, try switching VPN servers or using a residential VPN.", systemImage: "lightbulb")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Label("Your VPN is providing good privacy protection.", systemImage: "hand.thumbsup")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }

    /// WebRTC status row - shows N/A for native iOS apps.
    /// WebRTC is browser technology - native iOS apps don't have WebRTC stack.
    private func webRTCStatusRow() -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "video.circle")
                .foregroundColor(.gray)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("WebRTC Leak")
                        .font(.subheadline)
                    Spacer()
                    Text("N/A")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)
                }

                Text("Not applicable — WebRTC is a browser-only technology. Native iOS apps don't have WebRTC leaks.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// IPv6 status row with context for "Not tunneled" state.
    private func ipv6StatusRow(leakDetected: Bool, tunneled: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "network.badge.shield.half.filled")
                .foregroundColor(leakDetected ? .red : (tunneled ? .green : .gray))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("IPv6 Leak")
                        .font(.subheadline)
                    Spacer()

                    if leakDetected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    } else if tunneled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Text("N/A")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.3))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                    }
                }

                if leakDetected {
                    Text("IPv6 leak detected — your real IPv6 address may be visible")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if tunneled {
                    Text("IPv6 traffic is properly routed through VPN tunnel")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("IPv6 not active on this connection — no IPv6 leak possible. Most VPNs disable IPv6 by design for privacy.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func detectionRiskColor(_ risk: DetectionRisk) -> Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private func currentStatusCard(_ prediction: VPNFailurePrediction) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: riskIcon(prediction.riskLevel))
                        .foregroundColor(riskColor(prediction.riskLevel))
                    Text(prediction.statusText)
                        .font(.headline)
                }

                if prediction.failureProbability >= 50 {
                    Text("Failure Probability: \(prediction.failureProbability)%")
                        .font(.subheadline.bold())
                        .foregroundColor(.red)

                    if let timeToFailure = prediction.estimatedTimeToFailure {
                        let minutes = Int(timeToFailure / 60)
                        Text("Est. time to failure: ~\(minutes) minutes")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                if !prediction.warningIndicators.isEmpty {
                    Divider()

                    Text("Warning Signs:")
                        .font(.caption.bold())

                    ForEach(prediction.warningIndicators, id: \.self) { indicator in
                        Text("• \(indicator)")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func quickStatsCard(_ reliability: VPNReliabilityReport) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("VPN Reliability")
                    .font(.headline)

                // FIXED: Show "No data yet" when no historical data exists
                // Previously showed 0/0/0 with 90/100 stability score, which was misleading
                if !reliability.hasHistoricalData {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)

                        Text("No Data Yet")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Reliability tracking will begin automatically when VPN connections are detected. Use the app while connected to VPN to build tracking data.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatBox(
                            title: "Tunnel Drops (24h)",
                            value: "\(reliability.tunnelDropsLast24h)",
                            color: reliability.tunnelDropsLast24h > 2 ? .red : .green
                        )

                        StatBox(
                            title: "Total Connections",
                            value: "\(reliability.totalConnections)",
                            color: .blue
                        )

                        StatBox(
                            title: "Latency Spikes",
                            value: "\(reliability.latencySpikes.count)",
                            color: reliability.latencySpikes.count > 5 ? .orange : .green
                        )

                        StatBox(
                            title: "Stability Score",
                            value: "\(reliability.stabilityScore)/100",
                            color: scoreColor(reliability.stabilityScore)
                        )
                    }

                    if let recommended = reliability.recommendedRegion {
                        Divider()

                        Text("Recommended Region: \(recommended)")
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }

    private func modeComparisonCard(_ comparison: VPNModeComparison) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Best VPN Modes")
                    .font(.headline)

                if let best = comparison.bestOverall {
                    quickModeRow(title: "🏆 Best Overall", mode: best.rawValue)
                }

                if let best = comparison.bestForSpeed {
                    quickModeRow(title: "🚀 Fastest", mode: best.rawValue)
                }

                if let best = comparison.bestForLatency {
                    quickModeRow(title: "⚡ Lowest Latency", mode: best.rawValue)
                }

                if let best = comparison.bestForStability {
                    quickModeRow(title: "🔒 Most Stable", mode: best.rawValue)
                }
            }
        }
    }

    private func quickModeRow(title: String, mode: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
            Spacer()
            Text(mode)
                .font(.caption.bold())
                .foregroundColor(.blue)
        }
    }

    // MARK: - Reliability Tab

    @ViewBuilder
    private func reliabilityTab() -> some View {
        if let report = vm.reliabilityReport {
            VStack(spacing: 16) {
                // Recommendations
                CardView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommendations")
                            .font(.headline)

                        ForEach(report.recommendations, id: \.self) { rec in
                            Text("• \(rec)")
                                .font(.caption)
                        }
                    }
                }

                // Region Statistics
                if !report.regionStatistics.isEmpty {
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Region Statistics")
                                .font(.headline)

                            ForEach(Array(report.regionStatistics.keys.sorted()), id: \.self) { region in
                                if let stats = report.regionStatistics[region] {
                                    regionStatsRow(region: region, stats: stats)
                                }
                            }
                        }
                    }
                }

                // Unstable Regions
                if !report.unstableRegions.isEmpty {
                    CardView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("⚠️ Unstable Regions (Avoid)")
                                .font(.headline)
                                .foregroundColor(.red)

                            ForEach(report.unstableRegions, id: \.self) { region in
                                Text("• \(region)")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        } else {
            Text("No reliability data available")
                .foregroundColor(.secondary)
        }
    }

    private func regionStatsRow(region: String, stats: RegionReliability) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(region)
                    .font(.subheadline.bold())
                Spacer()
                Text("Score: \(stats.stabilityScore)/100")
                    .font(.caption)
                    .foregroundColor(scoreColor(stats.stabilityScore))
            }

            HStack {
                Text("Drops: \(stats.tunnelDrops)")
                Spacer()
                Text("Latency: \(String(format: "%.0f ms", stats.averageLatency))")
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            Divider()
        }
    }

    // MARK: - Benchmarks Tab

    @ViewBuilder
    private func benchmarksTab() -> some View {
        if let comparison = vm.modeComparison {
            VStack(spacing: 16) {
                ForEach(Array(comparison.modePerformance.values.sorted(by: { $0.averagePerformanceScore > $1.averagePerformanceScore })), id: \.mode) { stats in
                    modeBenchmarkCard(stats)
                }
            }
        } else {
            Text("No benchmark data available")
                .foregroundColor(.secondary)
        }
    }

    private func modeBenchmarkCard(_ stats: ModePerformanceStats) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(stats.mode.rawValue)
                        .font(.headline)
                    Spacer()
                    Text("\(Int(stats.averagePerformanceScore))/100")
                        .font(.caption)
                        .foregroundColor(scoreColor(Int(stats.averagePerformanceScore)))
                }

                Text(stats.mode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    miniStat(title: "Speed", value: String(format: "%.1f Mbps", stats.averageDownloadSpeed))
                    miniStat(title: "Latency", value: String(format: "%.0f ms", stats.averageLatency))
                    miniStat(title: "Stability", value: String(format: "%.0f/100", stats.averageStability))
                    miniStat(title: "Tests", value: "\(stats.testCount)")
                }
            }
        }
    }

    private func miniStat(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.bold())
        }
    }

    // MARK: - Prediction Tab

    @ViewBuilder
    private func predictionTab() -> some View {
        if let prediction = vm.failurePrediction {
            VStack(spacing: 16) {
                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: riskIcon(prediction.riskLevel))
                                .font(.system(size: 40))
                                .foregroundColor(riskColor(prediction.riskLevel))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(prediction.riskLevel.rawValue)
                                    .font(.headline)

                                Text("Failure Probability: \(prediction.failureProbability)%")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        Divider()

                        ForEach(prediction.predictions, id: \.self) { pred in
                            Text(pred)
                                .font(.caption)
                        }
                    }
                }

                // Jitter Status
                CardView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Jitter Analysis")
                            .font(.subheadline.bold())

                        HStack {
                            Text("Current: \(String(format: "%.1f ms", prediction.jitterStatus.currentJitter))")
                            Spacer()
                            Text(prediction.jitterStatus.isHigh ? "HIGH" : "Normal")
                                .foregroundColor(prediction.jitterStatus.isHigh ? .red : .green)
                        }
                        .font(.caption)
                    }
                }

                // Latency Trend
                CardView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latency Trend")
                            .font(.subheadline.bold())

                        HStack {
                            Text("Current: \(String(format: "%.0f ms", prediction.latencyTrend.currentLatency))")
                            Spacer()
                            Text(prediction.latencyTrend.isRising ? "RISING ⬆" : "Stable")
                                .foregroundColor(prediction.latencyTrend.isRising ? .orange : .green)
                        }
                        .font(.caption)

                        if prediction.latencyTrend.isRising {
                            Text("Change rate: \(String(format: "%.1f%%", prediction.latencyTrend.changeRate))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } else {
            Text("No prediction data available")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        else if score >= 60 { return .yellow }
        else if score >= 40 { return .orange }
        else { return .red }
    }

    private func riskIcon(_ risk: FailureRiskLevel) -> String {
        switch risk {
        case .low: return "checkmark.circle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    private func riskColor(_ risk: FailureRiskLevel) -> Color {
        switch risk {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Supporting Views

struct StatBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
}

// MARK: - ViewModel

@MainActor
class VPNIntelligenceViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isAnalyzingSecurity = false
    @Published var liveSecurityTest: VPNVisibilityTestResult?

    @Published var bestSetup: VPNSetupScore?
    @Published var reliabilityReport: VPNReliabilityReport?
    @Published var modeComparison: VPNModeComparison?
    @Published var failurePrediction: VPNFailurePrediction?

    // Task management for proper cancellation
    nonisolated(unsafe) private var currentLoadTask: Task<Void, Never>?
    nonisolated(unsafe) private var currentAnalysisTask: Task<Void, Never>?

    // Track if data has been loaded to prevent repeated heavy loads
    private var hasLoaded = false

    // FIXED: Only load if not already loaded - prevents freeze from repeated heavy loads
    func loadIfNeeded() async {
        guard !hasLoaded && !isLoading else {
            debugLog("🔐 [VPNIntelligence] Skipping load - already loaded or loading")
            return
        }
        await loadData()
        hasLoaded = true
    }

    func loadData() async {
        debugLog("🔐 [VPNIntelligence] Starting VPN intelligence load...")
        isLoading = true

        // Load VPN intelligence data
        debugLog("🔐 [VPNIntelligence] Fetching reports...")

        // Get reliability report
        reliabilityReport = await VPNReliabilityTracker.shared.getReliabilityReport()
        debugLog("🔐 [VPNIntelligence] ✅ Reliability report loaded")

        // Get mode comparison
        modeComparison = await VPNModeBenchmark.shared.getModeComparison()
        debugLog("🔐 [VPNIntelligence] ✅ Mode comparison loaded")

        // Get failure prediction for current region
        let currentRegion = reliabilityReport?.currentRegion ?? "Unknown"
        failurePrediction = await VPNFailurePredictor.shared.predictFailure(currentRegion: currentRegion)
        debugLog("🔐 [VPNIntelligence] ✅ Failure prediction loaded")

        // Get best setup score for current region/mode if VPN is active
        if let region = reliabilityReport?.currentRegion {
            bestSetup = await VPNAutoScorer.shared.scoreVPNSetup(region: region, mode: .wireGuard)
        } else {
            // No VPN active - set to nil so we show "No data yet" message
            bestSetup = nil
        }
        debugLog("🔐 [VPNIntelligence] ✅ Best setup loaded")

        debugLog("🔐 [VPNIntelligence] ✅ All data loaded successfully!")
        isLoading = false
    }

    func refreshAll() async {
        await loadData()
    }

    func runLiveSecurityAnalysis() async {
        debugLog("🔐 [VPNIntelligence] Running live VPN security analysis...")
        isAnalyzingSecurity = true

        // FIXED: Don't create new DashboardViewModel - use existing cached data
        // Creating new DashboardViewModel + refresh() triggers cascading network checks
        let networkStatus = NetworkMonitorService.shared.currentStatus
        let geoInfo = GeoIPService.shared.currentGeoIP

        // Use VPNSnapshotManager's security test creation logic
        let snapshotManager = VPNSnapshotManager.shared
        let dnsMetrics = VPNSnapshot.DNSMetrics(
            resolver: networkStatus.dns.resolverIP ?? "Unknown",
            latencyMs: networkStatus.dns.latency ?? 0,
            hijackDetected: false,
            dnsBehavior: "Live Analysis"
        )

        let securityTest = snapshotManager.createVPNVisibilityTest(
            from: geoInfo,
            dns: dnsMetrics,
            networkStatus: networkStatus
        )

        liveSecurityTest = securityTest
        isAnalyzingSecurity = false

        debugLog("🔐 [VPNIntelligence] ✅ Security analysis complete!")
        debugLog("🔐 Detection Risk: \(securityTest.detectionSignals.overallDetectionRisk.rawValue)")
        debugLog("🔐 Security Rating: \(securityTest.securityLeaks.securityRating)")
        debugLog("🔐 IP Type: \(securityTest.detectionSignals.ipType.rawValue)")
    }

    func cancel() {
        currentLoadTask?.cancel()
        currentLoadTask = nil
        currentAnalysisTask?.cancel()
        currentAnalysisTask = nil
        isLoading = false
        isAnalyzingSecurity = false
    }

    deinit {
        currentLoadTask?.cancel()
        currentAnalysisTask?.cancel()
    }
}

#Preview {
    VPNIntelligenceView()
}
