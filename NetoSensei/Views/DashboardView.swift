//
//  DashboardView.swift
//  NetoSensei
//
//  Main dashboard with real-time network indicators
//  STEP 5 - Complete Implementation
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @ObservedObject private var signalTracker = SignalStrengthTracker.shared
    // PART 3: Removed showingDiagnostic, showingAdvancedDiagnostic, showingVPNTools
    // These buttons are now in DiagnoseTabView and SecurityTabView
    @State private var showingIPInfo = false
    @State private var showingDebugPanel = false
    @State private var showingAIChat = false
    @State private var versionTapCount = 0

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: UIConstants.spacingL) {
                        // Header with smoothed health score
                        headerView

                        // PART 2: Simple Summary Section (plain-English)
                        simpleSummaryView

                        // Signal Strength Card (only when iOS gave us a REAL value)
                        // FIX (Issue 5): NEHotspotNetwork returns 0.0 when iOS doesn't
                        // know — never render "0% Poor" from that. SignalStrengthTracker
                        // already drops 0.0 samples, but guard here too in case
                        // currentStrength is exactly 0 from an older state.
                        if let s = signalTracker.currentStrength, s > 0 {
                            signalStrengthCard
                        }

                        // Wi-Fi Card
                        wifiCard

                        // Router Card (FIXED: yellow warning when VPN active)
                        routerCard

                        // Router Admin Button (only when available)
                        if let adminURL = vm.status.router.adminURL,
                           let url = URL(string: adminURL) {
                            routerAdminButton(url: url)
                        }

                        // Internet Card (uses smoothed latency)
                        internetCard

                        // VPN Card (conditional)
                        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
                        if vpnActive {
                            vpnCard
                        }

                        // DNS Card (uses smoothed latency)
                        dnsCard

                        // Public IP Card
                        publicIPCard

                        // Trend Insights (from speed + diagnostic history)
                        trendsCard

                        // Connection Stability Card
                        StabilityCard(stabilityMonitor: ConnectionStabilityMonitor.shared)

                        // Smart Recommendations (data-driven)
                        smartRecommendationsSection

                        // Problem Solutions (actionable fixes)
                        ProblemSolutionsCard(
                            solutions: SolutionEngine.solutions(for: vm.status)
                        )

                        // Version label with hidden debug tap
                        versionLabel
                    }
                    .padding()
                }
                .refreshable {
                    // PART 1: Force refresh on pull-to-refresh (bypass 60s limit)
                    await vm.refresh(forceRefresh: true)
                }

                // Loading overlay
                if vm.isLoading {
                    LoadingOverlay(message: "Refreshing network status...")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                aiAssistantFAB
            }
            .navigationTitle("Netosensei")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                // PART 1: Only refresh once on launch (not on every tab switch)
                Task {
                    await vm.refresh()
                }
            }
            .sheet(isPresented: $showingIPInfo) {
                IPInfoView()
            }
            .sheet(isPresented: $showingDebugPanel) {
                NetworkDebugView()
            }
            .sheet(isPresented: $showingAIChat) {
                AIChatView()
            }
        }
    }

    // MARK: - AI Assistant Floating Action Button

    private var aiAssistantFAB: some View {
        Button {
            showingAIChat = true
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
        .accessibilityLabel("AI Assistant")
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Version Label (tap 5 times for debug panel)

    private var versionLabel: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        return Text("NetoSensei v\(version) (\(build))")
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .onTapGesture {
                versionTapCount += 1
                if versionTapCount >= 5 {
                    versionTapCount = 0
                    showingDebugPanel = true
                }
                // Reset after 3 seconds of inactivity
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    versionTapCount = 0
                }
            }
    }

    // MARK: - Header View (PART 1: Uses smoothed/stable health rating)

    private var headerView: some View {
        CardView {
            HStack(spacing: UIConstants.spacingM) {
                // Health score circle
                ZStack {
                    Circle()
                        .stroke(stableStatusColor.opacity(0.3), lineWidth: 8)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: CGFloat(vm.smoothedHealthScore) / 100)
                        .stroke(stableStatusColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))

                    Text("\(vm.smoothedHealthScore)")
                        .font(.title3.bold())
                        .foregroundColor(stableStatusColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // PART 1: Use stableOverallHealth (with hysteresis) instead of raw overallHealth
                    Text("\(vm.stableOverallHealth.displayName)")
                        .font(.title2.bold())
                        .foregroundColor(AppColors.textPrimary)

                    Text(vm.connectionQuality)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)

                    // Connection type indicator
                    HStack(spacing: 4) {
                        Image(systemName: vm.status.connectionType?.iconName ?? "network")
                            .font(.caption)
                        Text(vm.connectionTypeDescription)
                            .font(.caption)
                    }
                    .foregroundColor(AppColors.accent)
                }

                Spacer()
            }
        }
    }

    // MARK: - Simple Summary View (PART 2: Plain-English summary)

    private var simpleSummaryView: some View {
        let items = vm.generateSimpleSummary()

        return CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("What's happening")
                    .font(.headline)

                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.emoji)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.bold())
                            Text(item.explanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Router Admin Button

    private func routerAdminButton(url: URL) -> some View {
        Button(action: {
            UIApplication.shared.open(url)
        }) {
            HStack(spacing: 12) {
                Image(systemName: "gear")
                    .font(.title3)
                    .foregroundColor(AppColors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Router Settings")
                        .font(.subheadline.bold())
                        .foregroundColor(AppColors.textPrimary)
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trends Card

    private var trendsCard: some View {
        // FIX (Issue 7): pass the SAME latency value used by Connection Stability
        // / the live dashboard so Trends can suppress historical "improved/
        // worsened" claims that contradict what the user is seeing right now.
        let referenceLatency = ConnectionStabilityMonitor.shared.averageLatency
            ?? vm.smoothedInternetLatency
            ?? vm.status.internet.displayableLatency
        let insights = TrendAnalyzer.allInsights(
            speedHistory: HistoryManager.shared.speedTestHistory,
            diagnosticHistory: HistoryManager.shared.diagnosticHistory,
            referenceLatencyMs: referenceLatency
        )

        return Group {
            if !insights.isEmpty {
                CardView {
                    VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: UIConstants.iconSizeM))
                                .foregroundColor(AppColors.accent)
                            Text("Trends")
                                .font(.headline)
                        }

                        ForEach(Array(insights.prefix(2))) { insight in
                            HStack(spacing: 8) {
                                Image(systemName: trendIcon(insight.severity))
                                    .foregroundColor(trendColor(insight.severity))
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(insight.title)
                                        .font(.subheadline.bold())
                                    Text(insight.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func trendIcon(_ severity: TrendAnalyzer.TrendInsight.Severity) -> String {
        switch severity {
        case .positive: return "arrow.up.right.circle.fill"
        case .neutral: return "arrow.right.circle.fill"
        case .negative: return "arrow.down.right.circle.fill"
        }
    }

    private func trendColor(_ severity: TrendAnalyzer.TrendInsight.Severity) -> Color {
        switch severity {
        case .positive: return AppColors.green
        case .neutral: return AppColors.yellow
        case .negative: return AppColors.red
        }
    }

    // MARK: - Signal Strength Card (from NEHotspotNetwork — real data)

    private var signalStrengthCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "wifi")
                        .font(.system(size: UIConstants.iconSizeM))
                        .foregroundColor(AppColors.textSecondary)
                    Text("Signal Strength")
                        .font(.headline)
                    Spacer()

                    // Trend arrow
                    let trend = signalTracker.trend
                    Image(systemName: trend.icon)
                        .font(.caption)
                        .foregroundColor(trend == .improving ? AppColors.green : trend == .degrading ? AppColors.red : AppColors.textSecondary)
                }

                if let strength = signalTracker.currentStrength, strength > 0 {
                    HStack(spacing: 16) {
                        // Signal bar visualization
                        HStack(spacing: 3) {
                            ForEach(0..<4, id: \.self) { index in
                                let threshold = Double(index + 1) * 0.25
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(strength >= threshold ? signalColor(strength) : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: CGFloat(8 + index * 6))
                            }
                        }
                        .frame(height: 26, alignment: .bottom)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(strength * 100))%")
                                .font(.title2.bold())
                                .foregroundColor(signalColor(strength))
                            Text(vm.status.wifi.signalQualityLevel.rawValue.capitalized)
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        // Average if enough samples
                        if let avg = signalTracker.averageStrength, signalTracker.samples.count >= 3 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Avg \(Int(avg * 100))%")
                                    .font(.caption.bold())
                                    .foregroundColor(AppColors.textSecondary)
                                Text("\(signalTracker.samples.count) samples")
                                    .font(.caption2)
                                    .foregroundColor(AppColors.textSecondary.opacity(0.7))
                            }
                        }
                    }
                } else {
                    // FIX (Issue 5): Honest fallback when iOS doesn't expose
                    // signal strength (no entitlement / location denied / sim).
                    Text("Signal data unavailable")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    private func signalColor(_ strength: Double) -> Color {
        switch strength {
        case 0.75...: return AppColors.green
        case 0.5..<0.75: return AppColors.green.opacity(0.8)
        case 0.25..<0.5: return AppColors.yellow
        default: return AppColors.red
        }
    }

    // MARK: - Wi-Fi Card
    // FIXED: Removed fake "Signal" display - iOS has NO public API for RSSI
    // Only show actually measurable data

    private var wifiCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                // Title
                HStack {
                    Image(systemName: "wifi")
                        .font(.system(size: UIConstants.iconSizeM))
                        .foregroundColor(AppColors.textSecondary)
                    TooltipText(text: "Wi-Fi", term: "SSID", font: .headline)
                }

                // Status
                StatusRow(
                    title: "Status",
                    value: vm.wifiStatusText,
                    color: wifiStatusColor
                )

                // Connection type
                if vm.status.wifi.isConnected {
                    StatusRow(
                        title: "Connection",
                        value: vm.connectionTypeDescription,
                        color: AppColors.green
                    )
                }
            }
        }
    }

    // MARK: - Router Card (STEP 3: Uses NetworkInterpreter for consistent messages)

    private var routerCard: some View {
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false

        // SINGLE SOURCE OF TRUTH: Use interpreter's router status when available
        let interpreterRouter = NetworkInterpreter.shared.current?.router

        // Pre-compute health status values outside ViewBuilder
        // FIX (Issue 2): a real measured latency to the gateway is proof it's
        // reachable — never label it "Unknown" / "Unreachable" in that case.
        let routerHasLiveLatency = vm.status.router.displayableLatency != nil ||
            vm.smoothedGatewayLatency != nil
        let healthText: String = {
            if let router = interpreterRouter {
                // Override interpreter "Unknown"/"Bad" if we have a fresh measurement.
                if routerHasLiveLatency && (router.status == .bad || router.status == .inactive) {
                    return ComponentStatus.StatusLevel.good.rawValue
                }
                return router.status.rawValue
            } else if routerHasLiveLatency {
                return NetworkHealth.excellent.displayName
            } else {
                return vpnActive && !vm.status.router.isReachable && vm.status.vpn.vpnState.isLikelyOn ? "Unreachable (VPN active)" : vm.status.router.health.displayName
            }
        }()
        let healthColor: Color = {
            if routerHasLiveLatency {
                if let l = vm.smoothedGatewayLatency ?? vm.status.router.displayableLatency {
                    return latencyColor(l)
                }
                return AppColors.green
            }
            return interpreterRouter?.color ?? routerStatusColor(vpnActive: vpnActive)
        }()

        return CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                // Title
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: UIConstants.iconSizeM))
                        .foregroundColor(AppColors.textSecondary)
                    Text("Router")
                        .font(.headline)
                }

                // Gateway
                // FIX (Issue 2): use displayedGatewayIP — which falls back to the
                // gateway derived from the local IP — so we never show "Unknown"
                // alongside a successful latency reading to that very gateway.
                if let gateway = vm.displayedGatewayIP {
                    StatusRow(
                        title: "Gateway",
                        value: gateway,
                        color: interpreterRouter?.color ?? routerStatusColor(vpnActive: vpnActive)
                    )
                } else {
                    // Use interpreter's value/color if available, otherwise fallback
                    let value = interpreterRouter?.value ?? (vpnActive && vm.status.vpn.vpnState.isLikelyOn ? "Unreachable (VPN)" : "Unknown")
                    let color = interpreterRouter?.color ?? (vpnActive ? AppColors.yellow : AppColors.red)
                    StatusRow(
                        title: "Gateway",
                        value: value,
                        color: color
                    )
                }

                // Health status - using pre-computed values
                StatusRow(
                    title: "Status",
                    value: healthText,
                    color: healthColor
                )

                // Latency (use smoothed value, but never a sentinel)
                // FIX (Issue 3): displayableLatency strips 999/sentinel timeouts.
                if let latency = vm.smoothedGatewayLatency ?? vm.status.router.displayableLatency {
                    StatusRow(
                        title: "Latency",
                        value: "\(Int(latency))ms",
                        color: latencyColor(latency)
                    )
                }

                // Warning text - use interpreter's detail for consistency
                // FIX (Issue 2/6): suppress "Router may be unreachable" when we
                // just measured a working latency to it, OR when the failure
                // tracker hasn't seen a hard run of consecutive misses.
                if let router = interpreterRouter, router.status == .hidden {
                    // VPN tunnel hides router - show interpreter's explanation
                    Text("ℹ️ \(router.detail)")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.top, 4)
                } else if vm.hasRouterProblem && !routerHasLiveLatency {
                    if vpnActive && vm.status.vpn.vpnState.isLikelyOn {
                        Text("ℹ️ Gateway unreachable while VPN active — this is normal")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.top, 4)
                    } else if !vpnActive {
                        Text("⚠️ Router may be unreachable")
                            .font(.caption)
                            .foregroundColor(AppColors.red)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    /// Router status color (PART 2: yellow when VPN hides it)
    private func routerStatusColor(vpnActive: Bool) -> Color {
        if !vm.status.router.isReachable {
            return vpnActive ? AppColors.yellow : AppColors.red  // Yellow when VPN, red when broken
        } else if let latency = vm.status.router.latency {
            if latency > 100 { return AppColors.red }
            else if latency > 30 { return AppColors.yellow }  // Use yellow instead of orange
            else { return AppColors.green }
        }
        return vpnActive ? AppColors.yellow : AppColors.green
    }

    // MARK: - Internet Card (PART 1: Uses smoothed latency)

    private var internetCard: some View {
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false

        return CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                // Title
                HStack {
                    Image(systemName: "globe")
                        .font(.system(size: UIConstants.iconSizeM))
                        .foregroundColor(AppColors.textSecondary)
                    Text("Internet")
                        .font(.headline)
                }

                // Connection status
                StatusRow(
                    title: "Status",
                    value: vm.internetStatusText,
                    color: vm.isConnected ? AppColors.green : AppColors.red
                )

                // PART 1: Use smoothed latency instead of raw value
                if let latency = vm.smoothedInternetLatency ?? vm.status.internet.latencyToExternal {
                    StatusRow(
                        title: "Latency",
                        value: "\(Int(latency))ms",
                        color: latencyColor(latency)
                    )
                }

                // FIXED: Latency warning - attribute correctly based on VPN status
                if vm.hasISPWarning {
                    if vpnActive {
                        // VPN is active - latency is caused by VPN routing, not ISP
                        Text("ℹ️ High latency — caused by VPN routing (not ISP)")
                            .font(.caption)
                            .foregroundColor(AppColors.yellow)
                            .padding(.top, 4)
                    } else {
                        // No VPN - could be ISP congestion
                        Text("⚠️ High latency — possible ISP congestion")
                            .font(.caption)
                            .foregroundColor(AppColors.yellow)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: - VPN Card

    private var vpnCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                // Title
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: UIConstants.iconSizeM))
                        .foregroundColor(AppColors.textSecondary)
                    TooltipText(text: "VPN", term: "VPN", font: .headline)
                }

                // Status (authoritative vs inferred)
                StatusRow(
                    title: "Status",
                    value: vm.vpnStatusText,
                    color: vm.status.vpn.isAuthoritative ? AppColors.green : AppColors.yellow
                )

                // Protocol
                if let tunnelType = vm.status.vpn.tunnelType {
                    StatusRow(
                        title: "Protocol",
                        value: tunnelType,
                        color: AppColors.green
                    )
                }

                // VPN Health Score
                if let score = vm.vpnHealthScore {
                    HStack(spacing: 12) {
                        // Mini score circle
                        ZStack {
                            Circle()
                                .stroke(vm.vpnHealthColor.opacity(0.3), lineWidth: 4)
                                .frame(width: 36, height: 36)
                            Circle()
                                .trim(from: 0, to: CGFloat(score) / 100)
                                .stroke(vm.vpnHealthColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 36, height: 36)
                                .rotationEffect(.degrees(-90))
                            Text("\(score)")
                                .font(.caption2.bold())
                                .foregroundColor(vm.vpnHealthColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Health")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Text(vm.vpnHealthDescription)
                                .font(.subheadline.bold())
                                .foregroundColor(vm.vpnHealthColor)
                        }
                    }
                } else {
                    StatusRow(
                        title: "Health",
                        value: vm.vpnHealthDescription,
                        color: vm.vpnHealthColor
                    )
                }

                // Show VPN overhead if calculable
                if let overhead = vm.vpnOverhead {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                        Text("VPN adds ~\(Int(overhead))ms latency")
                            .font(.caption2)
                    }
                    .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - DNS Card (STEP 3: Uses NetworkInterpreter for consistent messages)

    private var dnsCard: some View {
        // SINGLE SOURCE OF TRUTH: Use interpreter's DNS status when available
        let interpreterDNS = NetworkInterpreter.shared.current?.dns

        return CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                // Title
                HStack {
                    Image(systemName: "server.rack")
                        .font(.system(size: UIConstants.iconSizeM))
                        .foregroundColor(AppColors.textSecondary)
                    TooltipText(text: "DNS", term: "DNS", font: .headline)
                }

                // DNS Resolver
                if let dns = vm.status.dns.resolverIP {
                    StatusRow(
                        title: "Server",
                        value: dns,
                        color: interpreterDNS?.color ?? vm.status.dns.health.uiColor
                    )
                }

                // Latency - use interpreter's value or smoothed fallback
                let latencyValue = interpreterDNS?.value ?? (vm.smoothedDNSLatency ?? vm.status.dns.latency).map { "\(Int($0))ms" }
                let latencyColor = interpreterDNS?.color ?? dnsLatencyColor(vm.smoothedDNSLatency ?? vm.status.dns.latency ?? 0)

                if let value = latencyValue {
                    StatusRow(
                        title: "Latency",
                        value: value,
                        color: latencyColor
                    )
                }

                // Warning - use interpreter's detail for consistency
                if let dns = interpreterDNS, dns.hasIssue {
                    Text("⚠️ \(dns.detail)")
                        .font(.caption)
                        .foregroundColor(AppColors.yellow)
                        .padding(.top, 4)
                } else if vm.hasDNSWarning {
                    Text("⚠️ Slow DNS - consider switching to 1.1.1.1 or 8.8.8.8")
                        .font(.caption)
                        .foregroundColor(AppColors.yellow)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Public IP Card (Tappable - opens IP Info)

    private var publicIPCard: some View {
        Button(action: {
            showingIPInfo = true
        }) {
            CardView {
                VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                    // Title with chevron
                    HStack {
                        Image(systemName: "network")
                            .font(.system(size: UIConstants.iconSizeM))
                            .foregroundColor(AppColors.textSecondary)
                        Text("Public IP & ISP")
                            .font(.headline)
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    // Public IP
                    if !vm.publicIP.isEmpty && vm.publicIP != "0.0.0.0" {
                        HStack {
                            Text("Public IP")
                                .font(.subheadline)
                                .foregroundColor(AppColors.textSecondary)
                            Spacer()
                            Text(vm.publicIP)
                                .font(.body.bold().monospaced())
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }

                    // Location
                    if let city = vm.geoIPInfo.city, !city.isEmpty {
                        HStack {
                            Text("Location")
                                .font(.subheadline)
                                .foregroundColor(AppColors.textSecondary)
                            Spacer()
                            Text(vm.geoIPInfo.displayLocation)
                                .font(.body)
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }

                    // ISP
                    if !vm.ispName.isEmpty {
                        HStack {
                            Text("ISP")
                                .font(.subheadline)
                                .foregroundColor(AppColors.textSecondary)
                            Spacer()
                            Text(vm.ispName)
                                .font(.body)
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }

                    // Tap for more
                    Text("Tap for full IP details")
                        .font(.caption2)
                        .foregroundColor(AppColors.accent)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Smart Recommendations Section

    private var smartRecommendationsSection: some View {
        let recommendations = SmartRecommendationEngine.shared.generateRecommendations(
            from: vm.status,
            speedTest: HistoryManager.shared.speedTestHistory.first
        )

        // Only show if there are actionable recommendations (not just "All Good")
        return Group {
            if recommendations.count > 1 || (recommendations.first?.priority ?? 10) < 10 {
                CardView {
                    VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(AppColors.accent)
                            Text("Smart Recommendations")
                                .font(.headline)
                        }

                        // Show top 2 recommendations
                        ForEach(Array(recommendations.prefix(2).enumerated()), id: \.element.id) { index, rec in
                            if index > 0 {
                                Divider()
                            }
                            CompactRecommendationRow(recommendation: rec)
                        }

                        if recommendations.count > 2 {
                            Text("+ \(recommendations.count - 2) more recommendations")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // PART 3: Action buttons (Quick Check, Deep Scan, VPN Tools) removed from home screen
    // These are now accessible via the Diagnose and Security tabs

    // MARK: - Helper Computed Properties

    /// PART 1: Use stableOverallHealth (with hysteresis) for status color
    private var stableStatusColor: Color {
        switch vm.stableOverallHealth {
        case .excellent: return AppColors.green
        case .fair: return AppColors.yellow
        case .poor: return AppColors.red
        case .unknown: return .gray
        }
    }

    private var statusColor: Color {
        switch vm.overallHealth {
        case .excellent: return AppColors.green
        case .fair: return AppColors.yellow
        case .poor: return AppColors.red
        case .unknown: return .gray
        }
    }

    private var wifiStatusColor: Color {
        // FIX (Issue 1): match wifiStatusText logic — a private LAN IP is also
        // proof of WiFi connectivity even if status.wifi.isConnected is stale.
        let hasPrivateIP: Bool = {
            guard let ip = vm.status.localIP else { return false }
            return ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.")
        }()
        return (vm.status.wifi.isConnected || hasPrivateIP) ? AppColors.green : AppColors.red
    }

    private var signalStrengthColor: Color {
        guard let rssi = vm.status.wifi.rssi else { return .gray }
        if rssi >= -50 { return AppColors.green }
        else if rssi >= -70 { return AppColors.yellow }
        else { return AppColors.red }
    }

    private var wifiSignalIcon: String {
        guard let rssi = vm.status.wifi.rssi else { return "wifi.slash" }
        if rssi >= -50 { return "wifi" }
        else if rssi >= -60 { return "wifi" }
        else if rssi >= -70 { return "wifi" }
        else { return "wifi" }
    }

    private func latencyColor(_ latency: Double) -> Color {
        NetworkColors.forLatency(latency)
    }

    private func dnsLatencyColor(_ latency: Double) -> Color {
        NetworkColors.forDNSLatency(latency)
    }
}

// MARK: - Network Health Extension

extension NetworkHealth {
    var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .unknown: return "Unknown"
        }
    }

    var uiColor: Color {
        switch self {
        case .excellent: return AppColors.green
        case .fair: return AppColors.yellow
        case .poor: return AppColors.red
        case .unknown: return .gray
        }
    }
}

// MARK: - Preview

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Preview
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading) {
                            Text("Excellent")
                                .font(.title2.bold())
                            Text("Network is performing well")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(12)

                    // WiFi Preview
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "wifi")
                                .foregroundColor(.blue)
                            Text("Wi-Fi")
                                .font(.headline)
                        }
                        Text("Connected to MyNetwork")
                            .foregroundColor(.green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(12)

                    // Internet Preview
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.blue)
                            Text("Internet")
                                .font(.headline)
                        }
                        Text("Connected (25ms)")
                            .foregroundColor(.green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(12)

                    // Router Preview
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "wifi.router")
                                .foregroundColor(.blue)
                            Text("Router")
                                .font(.headline)
                        }
                        Text("Gateway: 192.168.1.1")
                            .foregroundColor(.green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("NetoSensei")
        }
        .previewDisplayName("Dashboard")
    }
}
