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
                VStack(spacing: UIConstants.spacingL) {
                    headerView

                    // Signal Strength Card (only when iOS gave us a REAL value)
                    // FIX (Issue 5): NEHotspotNetwork returns 0.0 when iOS doesn't
                    // know — never render "0% Poor" from that. SignalStrengthTracker
                    // already drops 0.0 samples, but guard here too in case
                    // currentStrength is exactly 0 from an older state.
                    if vm.status.wifi.isConnected, let s = signalTracker.currentStrength, s > 0 {
                        signalStrengthCard
                    }

                    // Commit 9: cellular is a first-class connection. On
                    // cellular-only the Wi-Fi card is HIDDEN (its absence is
                    // not a failure); on dual-stack both cards show.
                    if ConnectionCards.showsCellularCard(vm.status) {
                        cellularCard
                    }
                    if ConnectionCards.showsWiFiCard(vm.status) {
                        wifiCard
                    }

                    if ConnectionCards.showsRouterCard(vm.status) {
                        routerCard
                        if let adminURL = vm.status.router.adminURL,
                           let url = URL(string: adminURL) {
                            routerAdminButton(url: url)
                        }
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

                    // Diagnosis v2: findings from the ONE verdict replace the
                    // Smart Recommendations and Issues & Solutions engines.
                    if let v = vm.verdict {
                        FindingsCard(verdict: v)
                    }

                    // Version label with hidden debug tap
                    versionLabel
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                // Commit 8: never rate-limited, forces a fresh network read,
                // and waits for + re-runs after any in-flight refresh so
                // the gesture always ends with post-gesture data.
                await vm.refresh(trigger: .userInitiated)
            }

            .navigationTitle("Netosensei")
            .navigationBarTitleDisplayMode(.large)
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
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                Label {
                    Text(vm.internetStatusText)
                        .font(.title2.bold())
                        .accessibilityIdentifier("home.internetStatus")
                } icon: {
                    Image(systemName: vm.isConnected ? "checkmark.circle.fill" : "globe")
                        .foregroundStyle(vm.isConnected ? AppColors.green : .secondary)
                        .accessibilityHidden(true)
                }
                .accessibilityAddTraits(.isHeader)

                if vm.status.connectionType != nil {
                    Label(vm.connectionTypeDescription, systemImage: vm.status.connectionType?.iconName ?? "network")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if let verdict = vm.verdict {
                    if let score = verdict.score {
                        Text("Connection quality \(score.value)/100 · \(score.band.word)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(score.band.color)
                    }

                    if verdict.state == .degraded || verdict.state == .broken {
                        Text(verdict.headline)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    DisclosureGroup("Check details") {
                        VStack(alignment: .leading, spacing: 6) {
                            if verdict.score == nil {
                                Text("Connection quality score unavailable")
                                    .font(.subheadline)
                            }
                            CoverageLine(coverage: verdict.coverage)
                        }
                        .padding(.top, 6)
                    }
                    .font(.subheadline)
                } else if vm.status.measurementsPending {
                    Text("Measuring connection quality…")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                } else if vm.status.measurementsIncomplete {
                    Text("Some connection checks couldn’t finish.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

                        if let text = m.latencyText {
                            StatusRow(title: "Network latency", value: text,
                                      color: m.latencyMs.map { latencyColor($0) } ?? .secondary)
                        }
                        if let dns = m.dnsMs {
                            StatusRow(title: "DNS", value: "\(Int(dns))ms", color: dnsLatencyColor(dns))
                        }
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
                    Spacer()
                    // (i): explains what "Latency" measures and surfaces the
                    // secondary "App response time" (HTTP RTT) + methodology.
                    Button {
                        showingInternetLatencyInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundColor(AppColors.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("How latency is measured")
                }

                if !ConnectionCards.showsCellularCard(vm.status) {
                    let validLatency = vm.latencyIntercepted ? nil : (vm.smoothedInternetLatency ?? vm.status.internet.displayableLatency)
                    StatusRow(title: "Network latency",
                              value: ConnectionCards.internetLatencyText(status: vm.status, smoothedLatency: vm.smoothedInternetLatency),
                              color: validLatency.map { latencyColor($0) } ?? .secondary)
                }
                if let response = vm.status.internet.httpRTT {
                    StatusRow(title: "HTTPS response", value: "\(Int(response)) ms", color: .secondary)
                }

                // FIXED: Latency warning - attribute correctly based on VPN status
                if vm.hasISPWarning {
                    if vpnActive {
                        // VPN is active - latency is caused by VPN routing, not ISP
                        Text("ℹ️ High endpoint latency while VPN is active; cause unverified")
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

                // Latency — smoothed, never a sentinel
                let dnsLatencyMs = vm.smoothedDNSLatency ?? vm.status.dns.displayableLatency
                let latencyValue = dnsLatencyMs.map { "\(Int($0))ms" }
                let latencyColor = dnsLatencyMs.map(dnsLatencyColor) ?? .secondary

                if let value = latencyValue {
                    StatusRow(
                        title: "Latency",
                        value: value,
                        color: latencyColor
                    )
                }

                if vm.hasDNSWarning {
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
