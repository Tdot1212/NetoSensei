//
//  DashboardView.swift
//  NetoSensei
//
//  Main dashboard with real-time network indicators
//  STEP 5 - Complete Implementation
//

import SwiftUI

struct DashboardView: View {
    let openTab: (NetoTab) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCoverage = false
    @State private var showConnectionRepair = false
    @StateObject private var vm = DashboardViewModel()
    @ObservedObject private var signalTracker = SignalStrengthTracker.shared
    // PART 3: Removed showingDiagnostic, showingAdvancedDiagnostic, showingVPNTools
    // These buttons are now in DiagnoseTabView and SecurityTabView
    @State private var showingIPInfo = false
    @State private var showingInternetLatencyInfo = false
    @State private var showingDebugPanel = false
    @State private var showingAIChat = false
    @State private var showingSettings = false
    @State private var versionTapCount = 0
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var cellularRadio = CellularRadioInfo.shared
    @State private var showingCellularInfo = false

    var body: some View {
        NavigationView {
            ScrollView {
                // Home has a bounded number of cards. Keeping their layout
                // stable avoids repeated lazy placement while scrolling.
                VStack(spacing: 20) {
                    headerView
                    overviewDetails

                    if let verdict = vm.verdict {
                        FindingsCard(verdict: verdict)
                    }

                    BriefSectionTitle(title: "Connection details")
                    if vm.status.wifi.isConnected, let strength = signalTracker.currentStrength, strength > 0 {
                        signalStrengthCard
                    }
                    if ConnectionCards.showsCellularCard(vm.status) {
                        cellularCard
                    }
                    if ConnectionCards.showsWiFiCard(vm.status) {
                        wifiCard
                    }
                    if ConnectionCards.showsRouterCard(vm.status) {
                        routerCard
                        if let adminURL = vm.status.router.adminURL, let url = URL(string: adminURL) {
                            routerAdminButton(url: url)
                        }
                    }
                    if SmartVPNDetector.shared.detectionResult?.isVPNActive == true {
                        vpnCard
                    }
                    if vm.hasISPWarning { internetWarning }
                    if vm.status.dns.resolverIP != nil || vm.hasDNSWarning { dnsCard }
                    publicIPCard
                    trendsCard
                    StabilityCard(stabilityMonitor: ConnectionStabilityMonitor.shared)
                    versionLabel
                }
                .connectionBriefColumn()
            }
            .background(ConnectionBriefStyle.canvas)
            .refreshable {
                // Commit 8: never rate-limited, forces a fresh network read,
                // and waits for + re-runs after any in-flight refresh so
                // the gesture always ends with post-gesture data.
                await vm.refresh(trigger: .userInitiated)
            }

            .navigationTitle("Netosensei")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingAIChat = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("AI Assistant")

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .onAppear {
                // PART 1: Only refresh once on launch (not on every tab switch)
                Task {
                    await vm.refresh(trigger: .automatic)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Commit 8: returning from Settings after toggling Wi-Fi is the
                // same scenario as pull-to-refresh — re-read the network quietly.
                if phase == .active {
                    Task { await vm.refresh(trigger: .foreground) }
                }
            }
            .sheet(isPresented: $showingIPInfo) {
                IPInfoView()
            }
            .sheet(isPresented: $showingInternetLatencyInfo) {
                internetLatencyInfoSheet
            }
            #if DEBUG
            .sheet(isPresented: $showingDebugPanel) {
                NetworkDebugView()
            }
            #endif
            .sheet(isPresented: $showConnectionRepair) { WiFiAssistantView(guide: .lag) }
            .sheet(isPresented: $showingAIChat) {
                AIChatView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Version Label (tap 5 times for debug panel)

    private var versionLabel: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let label = Text("NetoSensei v\(version) (\(build))")
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

        #if DEBUG
        return label
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
        #else
        return label
        #endif
    }

    // MARK: - Connection overview

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: vm.isConnected ? "checkmark.circle.fill" : "globe")
                    .foregroundStyle(vm.isConnected ? ConnectionBriefStyle.mint : ConnectionBriefStyle.softWhite)
                    .accessibilityHidden(true)
                Text("Connection status")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ConnectionBriefStyle.softWhite)
            }

            Text(vm.internetStatusText)
                .font(.largeTitle.weight(.bold))
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("home.internetStatus")
                .accessibilityAddTraits(.isHeader)

            if vm.status.connectionType != nil {
                Label(activeConnectionLabel, systemImage: vm.status.connectionType?.iconName ?? "network")
                    .font(.subheadline)
                    .foregroundStyle(ConnectionBriefStyle.softWhite)
            }

            if let next = nextCheck {
                Text(next.detail)
                    .font(.subheadline)
                    .foregroundStyle(ConnectionBriefStyle.softWhite)
                    .accessibilityIdentifier("home.nextCheckReason")
                Button(next.title, systemImage: next.tab == .speed ? "speedometer" : "stethoscope") {
                    openTab(next.tab)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color(red: 0.09, green: 0.18, blue: 0.39))
                .controlSize(.large)
                .accessibilityIdentifier(next.tab == .speed ? "home.openSpeed" : "home.openDiagnose")
            }

            if let verdict = vm.verdict {
                Rectangle().fill(.white.opacity(0.23)).frame(height: 1)
                    .accessibilityHidden(true)
                coverageButton
                if showCoverage {
                    VStack(alignment: .leading, spacing: 6) {
                        if let score = verdict.score {
                            Text("Connection quality \(score.value)/100 · \(score.band.word)")
                                .font(.subheadline.weight(.semibold))
                        } else {
                            Text("Connection quality score unavailable")
                                .font(.subheadline.weight(.semibold))
                        }
                        CoverageLine(coverage: verdict.coverage)
                    }
                    .environment(\.colorScheme, .dark)
                    .transition(reduceMotion ? .identity : .opacity)
                }
            } else if vm.status.measurementsPending || vm.status.measurementsIncomplete {
                Text(vm.status.measurementsPending ? "Measuring connection quality…" : "Some connection checks couldn’t finish.")
                    .font(.subheadline)
                    .foregroundStyle(ConnectionBriefStyle.softWhite)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(ConnectionBriefStyle.hero, in: RoundedRectangle(cornerRadius: 25))
    }

    private var activeConnectionLabel: String {
        if vm.status.connectionType == .wifi {
            return vm.status.wifi.ssid.map { "Wi-Fi · \($0)" } ?? "Wi-Fi"
        }
        if vm.status.connectionType == .cellular, let generation = cellularRadio.generation {
            return "\(generation) cellular"
        }
        return vm.connectionTypeDescription
    }

    private var nextCheck: (title: String, detail: String, tab: NetoTab)? {
        guard !vm.isInitializing else { return nil }
        if vm.status.connectionType == nil {
            return ("Open Diagnose", "To get online, join a network in Settings → Wi-Fi or turn on Cellular Data.", .diagnose)
        }
        if vm.isConnected, vm.verdict?.primary?.kind == .proxyInterception {
            return ("Check speed and website response", "An internet target answered. Direct delay is unavailable, so use the speed and website checks if something feels slow.", .speed)
        }
        if let verdict = vm.verdict, verdict.state == .degraded || verdict.state == .broken {
            return ("Open Diagnose", verdict.headline, .diagnose)
        }
        if vm.status.measurementsPending || vm.status.measurementsIncomplete { return nil }
        if !vm.isConnected {
            return ("Open Diagnose", "This connection hasn’t returned an internet response. Check website access and DNS to narrow it down.", .diagnose)
        }
        if vm.verdict?.state == .working, vm.verdict?.coverage.failed.isEmpty == true {
            return ("Open Diagnose", "The checks that ran found no connection issue. If one site is slow, check that site by name.", .diagnose)
        }
        return ("Open Diagnose", "An internet target answered. Check your connection further if browsing, calls or streaming are still slow.", .diagnose)
    }

    private var coverageButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                showCoverage.toggle()
            }
        } label: {
            HStack {
                Text("Check details").font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: showCoverage ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showCoverage ? "Expanded" : "Collapsed")
    }

    private var overviewDetails: some View {
        let layout = widthClass == .regular && !dynamicType.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(spacing: 20))
        return layout {
            readings
            nextActions
        }
    }

    private var readings: some View {
        let latency = ConnectionCards.internetLatencyText(
            status: vm.status, smoothedLatency: vm.smoothedInternetLatency
        )
        let missingReading = vm.isInitializing || vm.status.measurementsPending ? "Measuring…" : "Unavailable"
        let https = vm.status.internet.httpRTT.map { "\(Int($0)) ms" }
        let dns = (vm.smoothedDNSLatency ?? vm.status.dns.displayableLatency).map { "\(Int($0)) ms" }
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        return CardView {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Live readings")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        showingInternetLatencyInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.accent)
                    .accessibilityLabel("How latency is measured")
                }

                layout {
                    reading("Network latency", value: vm.isInitializing ? missingReading : latency)
                    reading("HTTPS response", value: https ?? missingReading)
                    reading("DNS lookup", value: dns ?? missingReading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reading(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nextActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            BriefSectionTitle(title: "Network tools")
            CardView {
                VStack(spacing: 0) {
                    if nextCheck?.tab != .diagnose {
                        Button { openTab(.diagnose) } label: {
                            BriefActionLabel(title: "Find the cause and what to try", icon: "stethoscope")
                        }
                        .accessibilityIdentifier("home.openDiagnose")
                        Divider()
                    }
                    if nextCheck?.tab != .speed {
                        Button { openTab(.speed) } label: {
                            BriefActionLabel(title: "Test speed and streaming", icon: "speedometer")
                        }
                        .accessibilityIdentifier("home.openSpeed")
                        Divider()
                    }
                    Button { openTab(.security) } label: {
                        BriefActionLabel(title: "Review security and devices", icon: "shield.checkerboard")
                    }
                    .accessibilityIdentifier("home.openSecurity")
                    if ConnectionCards.showsRouterCard(vm.status) {
                        Divider()
                        Button { showConnectionRepair = true } label: {
                            BriefActionLabel(title: "Fix Wi-Fi and retest", icon: "wrench.and.screwdriver")
                        }
                    }
                }
                .buttonStyle(.plain)
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

    // MARK: - Cellular Card (Commit 9)

    private var cellularCardModel: CellularCardModel? {
        // Commit 11: the record was keyed with ExitPath.country() at test time;
        // resolve the card's key from the same source (GeoIP, else the VPN
        // detector's lookup) so a fresh launch with GeoIP still pending does
        // not produce "Cellular|direct|-" against a "Cellular|direct|CN" record.
        // `_ = vm.geoIPInfo` keeps the view re-evaluating when GeoIP resolves.
        _ = vm.geoIPInfo
        return ConnectionCards.cellularCard(
            status: vm.status,
            generation: cellularRadio.generation,
            smoothedLatency: vm.smoothedInternetLatency,
            smoothedDNS: vm.smoothedDNSLatency,
            recentSpeedTest: HistoryManager.shared.speedTestHistory.first,
            publicCountry: ExitPath.country()
        )
    }

    private var cellularCard: some View {
        Group {
            if let m = cellularCardModel {
                CardView {
                    VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: UIConstants.iconSizeM))
                                .foregroundColor(AppColors.textSecondary)
                            Text("Cellular")
                                .font(.headline)
                            Spacer()
                            Button {
                                showingCellularInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.accent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("About cellular measurements")
                        }

                        // Positive statement of the connection; the generation
                        // only when iOS reported one.
                        StatusRow(title: "Status", value: vm.isInitializing ? "Detecting..." : m.statusText,
                                  color: vm.isInitializing ? .secondary : AppColors.green)

                        if let down = m.downloadMbps {
                            StatusRow(title: "Download", value: String(format: "%.1f Mbps", down), color: NetworkColors.forSpeed(down))
                        }
                        if let up = m.uploadMbps {
                            StatusRow(title: "Upload", value: String(format: "%.1f Mbps", up), color: NetworkColors.forSpeed(up))
                        }
                        if let loss = m.packetLossPercent {
                            StatusRow(title: "Packet loss", value: String(format: "%.1f%%", loss), color: NetworkColors.forPacketLoss(loss))
                        }
                        if let j = m.jitterMs {
                            StatusRow(title: "Jitter", value: "\(Int(j))ms", color: NetworkColors.forJitter(j))
                        }
                        if m.downloadMbps == nil {
                            Text("Run a speed test on this connection to see throughput here.")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                }
                .sheet(isPresented: $showingCellularInfo) {
                    cellularInfoSheet(m)
                }
            }
        }
    }

    private func cellularInfoSheet(_ m: CellularCardModel) -> some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Signal strength")
                            .font(.headline)
                        Text(CellularRadioInfo.signalStrengthLimitation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Radio")
                            .font(.headline)
                        Text(m.generation.map { "iOS reports this connection as \($0)." }
                             ?? "iOS did not report a radio generation for this connection, so none is shown.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let raw = cellularRadio.rawTechnology {
                            Text("Reported value: \(raw)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What is measured here")
                            .font(.headline)
                        Text("Network latency times a TCP connection to a test endpoint. A VPN or proxy can make that timing unreliable. DNS times a lookup. Throughput, packet loss and jitter use measurements from a speed test on this connection in the past 10 minutes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Not measured on cellular")
                            .font(.headline)
                        Text("There is no local router on a mobile connection, so the router check is not applicable rather than failed.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Cellular")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingCellularInfo = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Router Card (Diagnosis v2: no interpreter; live latency + MetricBands)

    private var routerCard: some View {
        let latency = vm.smoothedGatewayLatency ?? vm.status.router.displayableLatency

        return CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                Label("Router", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .accessibilityIdentifier("home.router")

                StatusRow(title: "Gateway", value: vm.status.router.gatewayIP ?? "Unavailable", color: .secondary)

                if let latency {
                    StatusRow(title: "Response", value: "\(Int(latency)) ms", color: latencyColor(latency))
                } else if vm.status.measurementsPending {
                    StatusRow(title: "Status", value: "Checking router…", color: .secondary)
                } else if vm.status.router.isReachable {
                    StatusRow(title: "Status", value: "Responded", color: AppColors.green)
                } else {
                    StatusRow(title: "Status", value: "Response unconfirmed", color: .secondary)
                }
            }
        }
    }

    private var internetWarning: some View {
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive == true
        return CardView {
            Text(vpnActive
                 ? "High endpoint latency while VPN is active. The cause needs a comparison."
                 : "High latency to the test endpoint. Rerun Diagnose to check where the delay starts.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var internetLatencyInfoSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                    Text("Network latency")
                        .font(.headline)
                    Text(ConnectionCards.internetLatencyText(status: vm.status, smoothedLatency: vm.smoothedInternetLatency))
                    Text(vm.latencyIntercepted
                         ? "A VPN or proxy may have answered the TCP probe locally. Use HTTPS response time to compare web responsiveness on the current connection."
                         : "This measures how long a TCP connection takes to open to a test endpoint.")
                        .foregroundStyle(.secondary)
                    Divider()
                    Text("HTTPS response")
                        .font(.headline)
                    Text(vm.status.internet.httpRTT.map { "\(Int($0)) ms" } ?? "Unavailable")
                    Text("This times an HTTPS request to a test endpoint. It can include connection setup, encryption, and server response time.")
                        .foregroundStyle(.secondary)
                    Divider()
                    Text("DNS lookup")
                        .font(.headline)
                    Text("This times how long the system takes to find a server address for a hostname. It can include a cached reply.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("About Latency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingInternetLatencyInfo = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

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
                if vm.status.vpn.isAuthoritative, let tunnelType = vm.status.vpn.tunnelType {
                    StatusRow(
                        title: "Protocol",
                        value: tunnelType,
                        color: AppColors.green
                    )
                }

                // VPN Health Score
                if vm.status.vpn.isAuthoritative, let score = vm.vpnHealthScore {
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
                        title: "Protection",
                        value: "Unverified",
                        color: .secondary
                    )
                }

                // Show VPN overhead if calculable
                if let overhead = vm.vpnOverhead {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                        Text("VPN difference ~\(Int(overhead))ms")
                            .font(.caption2)
                    }
                    .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - DNS Card (Diagnosis v2: no interpreter)

    private var dnsCard: some View {
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
                        color: vm.status.dns.health.uiColor
                    )
                }

                if vm.hasDNSWarning {
                    Text("DNS lookups are slow. Compare resolver response times in Diagnose before changing your settings.")
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
                        Text("Public IP & network organization")
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
                            Text("Organization")
                                .font(.subheadline)
                                .foregroundColor(AppColors.textSecondary)
                            Spacer()
                            Text(vm.ispName)
                                .font(.body)
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }

                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Smart Recommendations Section

    // PART 3: Action buttons (Quick Check, Deep Scan, VPN Tools) removed from home screen
    // These are now accessible via the Diagnose and Security tabs

    // MARK: - Helper Computed Properties

    private var wifiStatusColor: Color {
        if vm.isInitializing { return .secondary }
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
