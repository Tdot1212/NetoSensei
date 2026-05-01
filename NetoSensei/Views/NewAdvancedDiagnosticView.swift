//
//  NewAdvancedDiagnosticView.swift
//  NetoSensei
//
//  Advanced Diagnostics View using new Engine Architecture
//

import SwiftUI

struct NewAdvancedDiagnosticView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = AdvancedDiagnosticViewModel()
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @State private var destination = "www.google.com"
    @State private var selectedMode: DiagnosticMode = .full

    enum DiagnosticMode: String, CaseIterable {
        case full = "Full Diagnostics"
        case security = "Security Only"
        case performance = "Performance Only"
    }

    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.isRunning {
                    progressView
                } else if let summary = viewModel.summary {
                    resultsView(summary: summary)
                } else {
                    startView
                }
            }
            .navigationTitle("Advanced Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if viewModel.summary != nil && !viewModel.isRunning {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: startDiagnostics) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Start View

    private var startView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "stethoscope.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.purple.gradient)

                    Text("Advanced Diagnostics")
                        .font(.title.bold())

                    Text("Deep network analysis with AI interpretation")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                // Mode Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Diagnostic Mode")
                        .font(.headline)

                    Picker("Mode", selection: $selectedMode) {
                        ForEach(DiagnosticMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)

                // Target Host
                VStack(alignment: .leading, spacing: 12) {
                    Text("Target Host")
                        .font(.headline)

                    TextField("e.g., www.google.com", text: $destination)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal)

                // Tests Description
                VStack(alignment: .leading, spacing: 16) {
                    TestInfoRow(
                        icon: "shield.checkered",
                        title: "Security Tests",
                        description: "DNS hijacking detection"
                    )

                    TestInfoRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Performance Tests",
                        description: "Real packet loss, jitter, throughput measurements, intelligent traceroute"
                    )
                }
                .padding(.horizontal)

                // Start Button
                Button(action: startDiagnostics) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Diagnostics")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.top, 20)

                Text(modeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "stethoscope.circle.fill")
                .font(.system(size: 70))
                .foregroundStyle(.purple.gradient)
                .symbolEffect(.pulse)

            VStack(spacing: 12) {
                Text("Running Diagnostics")
                    .font(.title2.bold())

                Text(viewModel.currentTask)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ProgressView(value: viewModel.progress)
                    .tint(.purple)
                    .scaleEffect(x: 1, y: 2, anchor: .center)

                Text("\(Int(viewModel.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }

    // MARK: - Results View

    private func resultsView(summary: AdvancedDiagnosticSummary) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary Card
                summaryCard(summary: summary)

                // OVERALL SOLUTION (Always shown)
                overallSolutionCard(summary: summary)

                // INTELLIGENT DIAGNOSIS (Priority #1)
                if let diagnosis = summary.networkDiagnosis {
                    intelligentDiagnosisCard(diagnosis: diagnosis)
                }

                // Security Results (Real Tests Only)
                if !summary.dnsHijackResults.isEmpty {
                    dnsResultsCard(results: summary.dnsHijackResults)
                }

                // Routing Results (Semi-Real - Real Latency)
                if let routing = summary.routingInterpretation {
                    routingCard(routing: routing)
                }

                // Performance Results (Real Measurements)
                if let performance = summary.performanceMetrics {
                    performanceCard(metrics: performance)
                }

                // WiFi Details (Real Data)
                if networkMonitor.currentStatus.wifi.isConnected {
                    wifiDetailsCard()
                }
            }
            .padding()
        }
    }

    // MARK: - Result Cards

    private func summaryCard(summary: AdvancedDiagnosticSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: threatLevelIcon(summary.overallThreatLevel))
                    .foregroundColor(threatLevelColor(summary.overallThreatLevel))
                    .font(.title2)

                VStack(alignment: .leading) {
                    Text("Diagnostic Summary")
                        .font(.headline)
                    Text(summary.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(summary.overallThreatLevel.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(threatLevelColor(summary.overallThreatLevel).opacity(0.2))
                    .foregroundColor(threatLevelColor(summary.overallThreatLevel))
                    .cornerRadius(8)
            }

            Divider()

            Text(summary.summaryText)
                .font(.subheadline)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Overall Solution Card

    private func overallSolutionCard(summary: AdvancedDiagnosticSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.orange)
                    .font(.title2)

                Text("Overall Assessment & Solutions")
                    .font(.headline)

                Spacer()
            }

            Divider()

            // Key Findings
            VStack(alignment: .leading, spacing: 12) {
                Text("Key Findings:")
                    .font(.subheadline.bold())

                // Performance Finding
                if let perf = summary.performanceMetrics {
                    findingRow(
                        icon: "speedometer",
                        color: performanceColor(perf),
                        title: "Performance",
                        description: performanceAssessment(perf)
                    )
                }

                // Security Finding - FIXED: Use region-aware DNS logic (consistent with summaryText)
                if !summary.dnsHijackResults.isEmpty {
                    let (securityColor, securityDesc) = securityFindingForDNS(summary)
                    findingRow(
                        icon: "shield.checkered",
                        color: securityColor,
                        title: "DNS Security",
                        description: securityDesc
                    )
                }

                // VPN Leak Finding - FIXED: Show VPN leak test results
                if let vpnLeak = summary.vpnLeakResult {
                    if vpnLeak.vpnIP == "N/A - No VPN Active" {
                        // No VPN active - don't show leak finding
                    } else if vpnLeak.leaked {
                        findingRow(
                            icon: "lock.open.trianglebadge.exclamationmark",
                            color: .red,
                            title: "VPN Leak",
                            description: "Your real IP may be leaking through the VPN. Check your VPN's kill switch settings."
                        )
                    } else {
                        findingRow(
                            icon: "lock.shield",
                            color: .green,
                            title: "VPN Security",
                            description: "VPN is protecting your IP (\(vpnLeak.vpnIP.prefix(12))...). No leaks detected."
                        )
                    }
                }

                // WiFi Finding (if connected)
                if networkMonitor.currentStatus.wifi.isConnected {
                    findingRow(
                        icon: "wifi",
                        color: wifiAssessmentColor(),
                        title: "WiFi Quality",
                        description: wifiAssessmentText()
                    )
                }

                // Routing Finding
                if let routing = summary.routingInterpretation {
                    findingRow(
                        icon: "arrow.triangle.branch",
                        color: .blue,
                        title: "Routing",
                        description: routing.userFriendlyExplanation.components(separatedBy: ".").first ?? "Routing analyzed"
                    )
                }
            }

            Divider()

            // Prioritized Recommendations
            VStack(alignment: .leading, spacing: 12) {
                Text("What You Should Do:")
                    .font(.subheadline.bold())

                let recommendations = generateRecommendations(summary)
                ForEach(Array(recommendations.enumerated()), id: \.offset) { index, recommendation in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(priorityColor(index))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(recommendation.title)
                                .font(.subheadline.bold())
                            Text(recommendation.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.1), Color.yellow.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
        )
    }

    private func findingRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.body)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // FIXED: Region-aware DNS security finding (consistent with summaryText and overallThreatLevel)
    private func securityFindingForDNS(_ summary: AdvancedDiagnosticSummary) -> (Color, String) {
        switch summary.dnsBehaviorType {
        case .allNormal:
            return (.green, "DNS resolution is normal. No hijacking detected.")
        case .normalChinaISP:
            // This is expected behavior - don't flag as red/critical
            return (.yellow, "ISP intercepts overseas DNS (normal for this region). Use VPN to bypass.")
        case .dnsConfigurationIssue:
            return (.orange, "DNS configuration issue detected. Check router or device DNS settings.")
        case .abnormalDNSBehavior:
            return (.red, "Abnormal DNS behavior: domestic domains being redirected. Investigate router settings.")
        }
    }

    private func performanceColor(_ perf: PerformanceMetrics) -> Color {
        if perf.packetLoss > 5 || perf.jitter > 30 { return .red }
        if perf.packetLoss > 1 || perf.jitter > 15 { return .orange }
        return .green
    }

    private func performanceAssessment(_ perf: PerformanceMetrics) -> String {
        if perf.packetLoss > 5 {
            return "High packet loss (\(String(format: "%.1f", perf.packetLoss))%) - severe connection issues"
        } else if perf.packetLoss > 1 {
            return "Moderate packet loss (\(String(format: "%.1f", perf.packetLoss))%) - some buffering expected"
        } else if perf.jitter > 30 {
            return "High jitter (\(perf.jitter)ms) - unstable connection"
        } else if perf.jitter > 15 {
            return "Moderate jitter (\(perf.jitter)ms) - minor instability"
        } else {
            return "Good performance - low packet loss and jitter"
        }
    }

    private func wifiAssessmentColor() -> Color {
        let wifi = networkMonitor.currentStatus.wifi
        guard let rssi = wifi.rssi else { return .gray }
        if rssi >= -60 { return .green }
        if rssi >= -70 { return .orange }
        return .red
    }

    private func wifiAssessmentText() -> String {
        // FIXED: iOS cannot measure WiFi RSSI - return accurate message
        let wifi = networkMonitor.currentStatus.wifi
        if wifi.isConnected {
            if let ssid = wifi.ssid, !ssid.isEmpty {
                return "Connected to \(ssid). WiFi metrics not available on iOS."
            }
            return "WiFi connected. Signal metrics not available on iOS."
        }
        return "Not connected to WiFi"
    }

    struct Recommendation {
        let title: String
        let description: String
    }

    private func generateRecommendations(_ summary: AdvancedDiagnosticSummary) -> [Recommendation] {
        var recommendations: [Recommendation] = []

        // FIXED: Check VPN status for context-aware recommendations
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false

        // FIXED: Use region-aware DNS logic instead of generic "hijacking detected"
        // Must match the logic in summaryText and overallThreatLevel to avoid contradictions
        switch summary.dnsBehaviorType {
        case .abnormalDNSBehavior:
            // Only truly abnormal behavior (China-native hijacked but overseas OK)
            recommendations.append(Recommendation(
                title: "Investigate Abnormal DNS Behavior",
                description: "China-native domains are being redirected, which is unusual. Check router DNS settings or contact your ISP."
            ))
        case .dnsConfigurationIssue:
            // Both domestic and overseas have issues - user configuration problem
            recommendations.append(Recommendation(
                title: "Fix DNS Configuration",
                description: "Both domestic and overseas domains show issues. Change DNS to 1.1.1.1 or 8.8.8.8 in your WiFi or router settings."
            ))
        case .normalChinaISP:
            // This is normal behavior for China - don't flag as "hijacking"
            // but provide helpful context
            if vpnActive {
                // User has VPN active, overseas DNS going through VPN - all good
                break
            }
            // No VPN and ISP intercepting overseas DNS - suggest VPN
            recommendations.append(Recommendation(
                title: "Overseas DNS Intercepted by ISP (Normal)",
                description: "Your ISP intercepts Google/overseas DNS queries. This is standard behavior in this region. Use a VPN to bypass if needed."
            ))
        case .allNormal:
            // DNS is fine, no recommendation needed
            break
        }

        // VPN-specific recommendations when VPN is active
        if vpnActive {
            // Check VPN performance using jitter as indicator of tunnel quality
            if let perf = summary.performanceMetrics {
                // High jitter on VPN often indicates congested or distant VPN server
                if perf.jitter > 50 {
                    recommendations.append(Recommendation(
                        title: "VPN Connection Unstable",
                        description: "High jitter (\(perf.jitter)ms) suggests VPN server is overloaded or far away. Try a closer server or WireGuard protocol."
                    ))
                }
            }

            // Check routing latency for VPN overhead (from traceroute-like measurement)
            if let routing = summary.routingInterpretation,
               let firstHop = routing.hops.first,
               let hopLatency = firstHop.latency {
                if hopLatency > 300 {
                    recommendations.append(Recommendation(
                        title: "VPN is Very Slow — Switch Servers",
                        description: "VPN tunnel latency is \(hopLatency)ms. Connect to a server closer to you. WireGuard protocol is usually fastest."
                    ))
                } else if hopLatency > 200 {
                    recommendations.append(Recommendation(
                        title: "VPN Overhead is High",
                        description: "VPN tunnel latency is \(hopLatency)ms. A closer VPN server could improve speed, but current performance is usable."
                    ))
                }
            }
        }

        // Check performance issues based on measurable metrics
        if let perf = summary.performanceMetrics {
            if perf.packetLoss > 5 {
                // FIXED: VPN-aware advice
                if vpnActive {
                    recommendations.append(Recommendation(
                        title: "High Packet Loss",
                        description: "Packet loss is \(String(format: "%.1f", perf.packetLoss))%. Try switching VPN servers or protocols. If issue persists, check local WiFi."
                    ))
                } else {
                    recommendations.append(Recommendation(
                        title: "Fix Severe Packet Loss",
                        description: "Packet loss is \(String(format: "%.1f", perf.packetLoss))%. Restart router, disconnect unused devices, or contact ISP."
                    ))
                }
            } else if perf.packetLoss > 1 {
                recommendations.append(Recommendation(
                    title: "Reduce Packet Loss",
                    description: "Packet loss is \(String(format: "%.1f", perf.packetLoss))%. Check for network congestion or try restarting router."
                ))
            }

            if perf.jitter > 30 {
                if vpnActive {
                    recommendations.append(Recommendation(
                        title: "Unstable VPN Connection",
                        description: "High jitter (\(String(format: "%.0f", perf.jitter))ms). Try a different VPN server or switch to WireGuard protocol."
                    ))
                } else {
                    recommendations.append(Recommendation(
                        title: "Stabilize Connection",
                        description: "High jitter (\(String(format: "%.0f", perf.jitter))ms) indicates unstable connection. Restart router or try 5GHz band if available."
                    ))
                }
            }
        }

        // Check routing if available - but FILTER based on VPN status
        // FIX (Phase 2): When traceroute fails (iOS sandboxing), the engine
        // returns an empty hops list and zero recommendations. Don't synthesize
        // a "Routing Optimization — Check your internet connection" card from
        // that — it's misleading platform-restriction feedback, not a problem.
        if let routing = summary.routingInterpretation, !routing.hops.isEmpty {
            // FIXED: Don't recommend "restart router" when VPN is active
            let filteredRecs = routing.recommendations.filter { rec in
                let lower = rec.lowercased()
                // Drop generic "check your connection" / "try again later" advice
                // that comes from the no-hops fallback path.
                if lower.contains("check your internet connection") ||
                   lower.contains("try again later") {
                    return false
                }
                if vpnActive {
                    return !lower.contains("restart your router") &&
                           !lower.contains("router congestion")
                }
                return true
            }
            for rec in filteredRecs.prefix(1) {
                recommendations.append(Recommendation(
                    title: "Routing Optimization",
                    description: rec
                ))
            }
        }

        // Default recommendation if everything is good
        if recommendations.isEmpty {
            recommendations.append(Recommendation(
                title: "Everything Looks Good!",
                description: "Your network is performing well. No immediate action needed."
            ))
        }

        return recommendations
    }

    private func priorityColor(_ index: Int) -> Color {
        switch index {
        case 0: return .red      // Highest priority
        case 1: return .orange   // High priority
        case 2: return .yellow   // Medium priority
        default: return .blue    // Lower priority
        }
    }

    // MARK: - Intelligent Diagnosis Card

    private func intelligentDiagnosisCard(diagnosis: NetworkDiagnosisResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                    .font(.title2)

                VStack(alignment: .leading) {
                    Text("Network Doctor Diagnosis")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text("Confidence:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(diagnosis.confidence.rawValue) (\(diagnosis.confidence.percentage)%)")
                            .font(.caption.bold())
                            .foregroundColor(confidenceColor(diagnosis.confidence))
                    }
                }

                Spacer()
            }

            Divider()

            // Problem Type
            VStack(alignment: .leading, spacing: 8) {
                Text(diagnosis.userFriendlySummary)
                    .font(.title3.bold())
                    .foregroundColor(problemColor(diagnosis.primaryProblem))

                Text(diagnosis.explanation)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Actionable Recommendations
            VStack(alignment: .leading, spacing: 12) {
                Text("Recommended Actions:")
                    .font(.headline)

                ForEach(diagnosis.recommendations) { rec in
                    recommendationRow(recommendation: rec)
                }
            }

            // Technical Details (Collapsible)
            DisclosureGroup("Technical Details") {
                VStack(alignment: .leading, spacing: 8) {
                    technicalDetailRow(label: "VPN Active", value: diagnosis.technicalDetails.vpnActive ? "Yes" : "No")
                    technicalDetailRow(label: "Public IP", value: diagnosis.technicalDetails.publicIP)
                    technicalDetailRow(label: "Local Latency", value: "\(Int(diagnosis.technicalDetails.localLatency))ms")
                    if let foreign = diagnosis.technicalDetails.foreignLatency {
                        technicalDetailRow(label: "Foreign Latency", value: "\(Int(foreign))ms")
                    }
                    technicalDetailRow(label: "Packet Loss", value: String(format: "%.1f%%", diagnosis.technicalDetails.packetLoss))
                    technicalDetailRow(label: "Jitter", value: "\(diagnosis.technicalDetails.jitter)ms")
                    technicalDetailRow(label: "Download Speed", value: String(format: "%.1f Mbps", diagnosis.technicalDetails.downloadSpeed))

                    Divider()
                        .padding(.vertical, 4)

                    Text("Detected Symptoms:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    Text(diagnosis.technicalDetails.symptomsDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
            .font(.subheadline)
            .tint(.purple)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.1), Color.blue.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
    }

    private func recommendationRow(recommendation: ActionableRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: priorityIcon(recommendation.priority))
                    .foregroundColor(priorityColor(recommendation.priority))
                    .font(.subheadline)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(recommendation.action)
                            .font(.subheadline.bold())

                        Spacer()

                        Text(recommendation.priority.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(priorityColor(recommendation.priority).opacity(0.2))
                            .foregroundColor(priorityColor(recommendation.priority))
                            .cornerRadius(4)
                    }

                    Text(recommendation.reasoning)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Expected: \(recommendation.expectedImprovement)")
                        .font(.caption)
                        .foregroundColor(.green)
                        .italic()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func technicalDetailRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(.primary)
        }
    }

    private func dnsResultsCard(results: [DNSHijackResult]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(.blue)
                Text("DNS Hijacking Test")
                    .font(.headline)
            }

            ForEach(results, id: \.domain) { result in
                HStack {
                    Image(systemName: result.hijacked ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(result.hijacked ? .red : .green)

                    Text(result.domain)
                        .font(.subheadline)

                    Spacer()

                    if !result.resolvedIPs.isEmpty {
                        Text(result.resolvedIPs.first ?? "")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    private func routingCard(routing: RoutingInterpretation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(.purple)
                Text("Intelligent Traceroute")
                    .font(.headline)
            }

            Text(routing.userFriendlyExplanation)
                .font(.subheadline)

            Divider()

            Text("Recommendations:")
                .font(.caption.bold())

            ForEach(routing.recommendations, id: \.self) { rec in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                    Text(rec)
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    private func performanceCard(metrics: PerformanceMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "speedometer")
                    .foregroundColor(.blue)
                Text("Performance Metrics")
                    .font(.headline)
            }

            Text(metrics.userFriendlyDescription)
                .font(.subheadline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricBox(label: "Packet Loss", value: String(format: "%.1f%%", metrics.packetLoss))
                MetricBox(label: "Jitter", value: "\(metrics.jitter)ms")
                MetricBox(label: "Speed", value: metrics.throughput < 0 ? "Blocked" : String(format: "%.1f Mbps", metrics.throughput))
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    private func wifiDetailsCard() -> some View {
        let wifi = networkMonitor.currentStatus.wifi

        return VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "wifi")
                    .foregroundColor(.cyan)
                Text("WiFi Radio State")
                    .font(.headline)
            }

            // SSID and BSSID (these ARE available on iOS with Location permission)
            if let ssid = wifi.ssid {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network: \(ssid)")
                        .font(.subheadline.bold())
                    if let bssid = wifi.bssid {
                        Text("BSSID: \(bssid)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()
            }

            // FIXED: Show unavailable message instead of fake data
            // Apple explicitly blocks access to WiFi radio metrics on iOS
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 8) {
                    Text("WiFi Radio Metrics Unavailable")
                        .font(.subheadline.bold())

                    Text("WiFi radio metrics (RSSI, channel, MCS, link speed) are not accessible to third-party apps on iOS due to Apple platform restrictions.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("For detailed WiFi diagnostics, use Apple's built-in tools:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Settings → Wi-Fi → tap (i) next to network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• macOS: Option+click WiFi icon for details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

            // Note: All the conditional blocks below won't render since rssi, noise, linkSpeed, etc. are nil
            // Keeping them for code compatibility but they will never execute

            // RSSI - Signal Strength (NEVER available on iOS)
            if let rssi = wifi.rssi {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("RSSI (Signal Strength)")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(rssi) dBm")
                            .font(.subheadline.bold())
                            .foregroundColor(rssiColor(rssi))
                        Text(rssiQuality(rssi))
                            .font(.caption)
                            .foregroundColor(rssiColor(rssi))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(rssiColor(rssi).opacity(0.1))
                            .cornerRadius(4)
                    }

                    Text(rssiExplanation(rssi))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            // SNR - Signal-to-Noise Ratio (VERY IMPORTANT)
            if let noise = wifi.noise, let rssi = wifi.rssi {
                let snr = rssi - noise
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("SNR (Signal-to-Noise Ratio)")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(snr) dB")
                            .font(.subheadline.bold())
                            .foregroundColor(snrColor(snr))
                        Text(snrQuality(snr))
                            .font(.caption)
                            .foregroundColor(snrColor(snr))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(snrColor(snr).opacity(0.1))
                            .cornerRadius(4)
                    }

                    Text(snrExplanation(snr))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Calculated: RSSI (\(rssi) dBm) - Noise (\(noise) dBm) = \(snr) dB")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.vertical, 4)
            }

            // TX Rate - Link Speed (Actual Airtime Quality)
            if let linkSpeed = wifi.linkSpeed {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("TX Rate (Link Speed)")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(linkSpeed) Mbps")
                            .font(.subheadline.bold())
                            .foregroundColor(.cyan)
                    }

                    Text(txRateExplanation(linkSpeed))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            // Channel Width
            if let width = wifi.channelWidth, let band = wifi.band {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Channel: \(wifi.channel ?? 0) (\(band), \(width) MHz)")
                            .font(.subheadline.bold())
                        Spacer()
                    }

                    Text(channelWidthExplanation(width))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            // MCS Index - Modulation Quality
            if let mcs = wifi.mcsIndex, let phyMode = wifi.phyMode {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Modulation Quality")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("MCS \(mcs) (\(phyMode))")
                            .font(.subheadline.bold())
                            .foregroundColor(.purple)
                    }

                    Text(mcsExplanation(mcs))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let nss = wifi.nss {
                        Text("Spatial Streams: \(nss) (number of antennas actively transmitting)")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    // WiFi Quality Helpers
    private func rssiColor(_ rssi: Int) -> Color {
        if rssi >= -50 { return .green }
        if rssi >= -60 { return .cyan }
        if rssi >= -70 { return .orange }
        return .red
    }

    private func rssiQuality(_ rssi: Int) -> String {
        if rssi >= -50 { return "Excellent" }
        if rssi >= -60 { return "Good" }
        if rssi >= -70 { return "Fair" }
        return "Poor"
    }

    private func snrColor(_ snr: Int) -> Color {
        if snr > 30 { return .green }
        if snr >= 20 { return .orange }
        return .red
    }

    private func snrQuality(_ snr: Int) -> String {
        if snr > 30 { return "Excellent" }
        if snr >= 20 { return "OK" }
        return "Poor"
    }

    // WiFi Metric Explanations
    private func rssiExplanation(_ rssi: Int) -> String {
        if rssi >= -50 {
            return "Excellent signal strength. Your device has a very strong connection to the WiFi router. No signal-related issues expected."
        } else if rssi >= -60 {
            return "Good signal strength. Your connection is solid and should handle video streaming without buffering."
        } else if rssi >= -70 {
            return "Marginal signal. You may experience occasional buffering during video playback. Consider moving closer to the router."
        } else {
            return "Poor signal strength. Video buffering and connection drops are likely. Move closer to the router or switch to 2.4 GHz band for better range."
        }
    }

    private func snrExplanation(_ snr: Int) -> String {
        if snr > 30 {
            return "Excellent SNR. Your signal is clean with minimal interference. This indicates your WiFi channel is not congested and neighboring networks aren't causing problems."
        } else if snr >= 20 {
            return "OK SNR. Some interference present, possibly from neighboring WiFi networks or 2.4 GHz devices (microwaves, Bluetooth). May cause minor performance issues."
        } else {
            return "Poor SNR. High interference/congestion detected. Your WiFi channel likely has multiple competing networks. This causes packet loss and video buffering even with good RSSI. Try changing your WiFi channel."
        }
    }

    private func txRateExplanation(_ linkSpeed: Int) -> String {
        if linkSpeed >= 400 {
            return "Excellent TX rate. Your device is achieving optimal WiFi speeds (\(linkSpeed) Mbps physical layer). This indicates good airtime quality and minimal router congestion."
        } else if linkSpeed >= 200 {
            return "Good TX rate. Your connection is using \(linkSpeed) Mbps at the physical layer. Adequate for most activities including HD streaming."
        } else if linkSpeed >= 100 {
            return "Medium TX rate (\(linkSpeed) Mbps). This may indicate: (1) router congestion from multiple devices, (2) poor signal causing fallback to lower modulation, or (3) 2.4 GHz band limitations."
        } else {
            return "Low TX rate (\(linkSpeed) Mbps). WARNING: Router is forcing very low speeds. Likely causes: severe congestion (too many devices), interference, or you're on 2.4 GHz with poor signal. Video buffering expected."
        }
    }

    private func channelWidthExplanation(_ width: Int) -> String {
        if width >= 80 {
            return "80 MHz channel = Fast but fragile. You get maximum speed BUT it's more susceptible to interference. If you experience buffering despite good speed tests, this wide channel may be the culprit. Consider dropping to 40 MHz for stability."
        } else if width == 40 {
            return "40 MHz channel = Balanced. You sacrifice some peak speed for better stability. Good choice in crowded WiFi environments (apartments, offices)."
        } else {
            return "20 MHz channel = Slow but most stable. Minimal interference, but speeds are limited. Best for maximizing range in 2.4 GHz or when many neighbors share the same channels."
        }
    }

    private func mcsExplanation(_ mcs: Int) -> String {
        if mcs >= 7 {
            return "High MCS index (\(mcs)) = Router is using advanced modulation schemes. This means conditions are good (strong signal, low interference) so the router can pack more data per transmission."
        } else if mcs >= 4 {
            return "Medium MCS index (\(mcs)) = Router using moderate modulation. Acceptable performance, but not optimal. May indicate mild interference or distance from router."
        } else {
            return "Low MCS index (\(mcs)) = Router is forced to use basic modulation due to poor conditions. This indicates: (1) high interference, (2) weak signal, or (3) channel congestion. Result: Slower speeds even if TX rate looks OK."
        }
    }

    // MARK: - Helper Views

    private struct TestInfoRow: View {
        let icon: String
        let title: String
        let description: String

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.purple.gradient)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.bold())
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private struct MetricBox: View {
        let label: String
        let value: String

        var body: some View {
            VStack(spacing: 4) {
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundColor(.blue)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(8)
        }
    }

    // MARK: - Actions

    private func startDiagnostics() {
        viewModel.reset()

        switch selectedMode {
        case .full:
            viewModel.runFullDiagnostics(targetHost: destination)
        case .security:
            viewModel.runSecurityScan()
        case .performance:
            viewModel.runPerformanceTest(targetHost: destination)
        }
    }

    private var modeDescription: String {
        switch selectedMode {
        case .full:
            return "Complete diagnostic scan (~60 seconds)"
        case .security:
            return "Security tests only (~30 seconds)"
        case .performance:
            return "Performance tests only (~30 seconds)"
        }
    }

    // MARK: - Helper Functions

    private func threatLevelIcon(_ level: ThreatLevel) -> String {
        switch level {
        case .secure: return "checkmark.shield.fill"
        case .low: return "checkmark.shield.fill"
        case .medium: return "exclamationmark.shield.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.shield.fill"
        }
    }

    private func threatLevelColor(_ level: ThreatLevel) -> Color {
        switch level {
        case .secure: return .green
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }

    // MARK: - Diagnosis Helper Functions

    private func confidenceColor(_ confidence: DiagnosisConfidence) -> Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }

    private func problemColor(_ problem: NetworkProblemType) -> Color {
        switch problem {
        case .wifiRouterIssue: return .red
        case .vpnServerSlow: return .red
        case .vpnInstability: return .orange
        case .ispThrottling: return .orange
        case .ispLocalCongestion: return .red
        case .normalPerformance: return .green
        case .insufficientData: return .gray
        }
    }

    private func priorityColor(_ priority: RecommendationPriority) -> Color {
        switch priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .blue
        case .low: return .gray
        }
    }

    private func priorityIcon(_ priority: RecommendationPriority) -> String {
        switch priority {
        case .critical: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "info.circle.fill"
        case .low: return "lightbulb.fill"
        }
    }

}

#Preview {
    NewAdvancedDiagnosticView()
}
