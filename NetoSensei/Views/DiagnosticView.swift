//
//  DiagnosticView.swift
//  NetoSensei
//
//  Diagnostic view with progress tracking and results
//  STEP 5 - Complete Implementation
//

import SwiftUI

/// Diagnostic view for modal/sheet presentation
struct DiagnosticView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = DiagnosticViewModel()

    var body: some View {
        NavigationView {
            DiagnosticContentView(vm: vm)
                .navigationTitle("Network Diagnostic")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    // Auto-start diagnostic when sheet opens
                    if !vm.isRunning && vm.result == nil {
                        vm.runFullDiagnostic()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(vm.isRunning ? "Minimize" : "Close") {
                            // Don't cancel the diagnostic - let it run in background
                            dismiss()
                        }
                    }

                    if vm.isRunning {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Cancel", role: .destructive) {
                                vm.cancelDiagnostic()
                                dismiss()
                            }
                        }
                    } else if vm.hasResult {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Run Again") {
                                vm.runFullDiagnostic()
                            }
                        }
                    }
                }
        }
    }
}

/// Diagnostic content view (reusable in tabs or sheets)
struct DiagnosticContentView: View {
    @ObservedObject var vm: DiagnosticViewModel
    @State private var showingRouterGuide = false
    @State private var showingWiFiTips = false
    @State private var showingDNSGuide = false
    @State private var showingVPNGuide = false
    @State private var showingISPContact = false
    @State private var showingVPNRegionPicker = false
    @State private var showingVPNProtocolSelector = false
    @State private var showingStreamingOptimizer = false
    @State private var showingDNSBenchmark = false
    @State private var showingThrottleTest = false
    @State private var recommendedDNS = "1.1.1.1"
    @State private var recommendedVPNRegion: String?

    var body: some View {
        ScrollView {
            VStack(spacing: UIConstants.spacingL) {
                if vm.isRunning {
                    diagnosticRunningView
                } else if let result = vm.result {
                    diagnosticResultsView(result: result)
                } else {
                    diagnosticIntroView
                }
            }
            .padding()
        }
            .sheet(isPresented: $showingRouterGuide) {
                RouterRestartGuideSheet()
            }
            .sheet(isPresented: $showingWiFiTips) {
                WiFiOptimizationSheet()
            }
            .sheet(isPresented: $showingDNSGuide) {
                DNSChangeSheet(recommendedDNS: recommendedDNS)
            }
            .sheet(isPresented: $showingVPNGuide) {
                VPNSetupGuideSheet()
            }
            .sheet(isPresented: $showingISPContact) {
                ISPContactSheet()
            }
            .sheet(isPresented: $showingVPNRegionPicker) {
                VPNRegionPickerSheet(recommendedRegion: recommendedVPNRegion)
            }
            .sheet(isPresented: $showingVPNProtocolSelector) {
                VPNProtocolSelectorSheet()
            }
            .sheet(isPresented: $showingStreamingOptimizer) {
                StreamingOptimizationSheet()
            }
            .sheet(isPresented: $showingDNSBenchmark) {
                DNSBenchmarkView()
            }
            .sheet(isPresented: $showingThrottleTest) {
                ThrottleDetectionView()
            }
    }

    // MARK: - Intro View

    private var diagnosticIntroView: some View {
        VStack(spacing: UIConstants.spacingXL) {
            Spacer()

            Image(systemName: "stethoscope.circle.fill")
                .font(.system(size: UIConstants.iconSizeXL * 2))
                .foregroundColor(AppColors.accent)

            VStack(spacing: UIConstants.spacingM) {
                Text("Network Diagnostic")
                    .font(.largeTitle.bold())

                Text("We'll run comprehensive tests to identify any issues affecting your network performance.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal)
            }

            Button(action: {
                vm.runFullDiagnostic()
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Start Diagnostic")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.accent)
                .foregroundColor(.white)
                .cornerRadius(UIConstants.cornerRadiusL)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, UIConstants.spacingXL)

            // Quick Tools Section
            DiagnosticToolsCard(
                showingDNSBenchmark: $showingDNSBenchmark,
                showingThrottleTest: $showingThrottleTest
            )
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Running View

    private var diagnosticRunningView: some View {
        VStack(spacing: UIConstants.spacingXL) {
            Spacer()

            // Animated icon
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 80))
                .foregroundColor(AppColors.accent)
                .symbolEffect(.pulse, options: .repeating)

            // Status text
            VStack(spacing: UIConstants.spacingS) {
                Text("Diagnostic Running...")
                    .font(.title2.bold())
                    .foregroundColor(AppColors.textPrimary)

                Text("You can minimize and continue using the app")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Progress bar
            VStack(spacing: UIConstants.spacingS) {
                HStack {
                    Text(vm.currentTest.isEmpty ? "Initializing..." : vm.currentTest)
                        .font(.subheadline.bold())
                        .foregroundColor(AppColors.accent)
                    Spacer()
                    Text("\(Int(vm.progress * 100))%")
                        .font(.subheadline.bold().monospaced())
                        .foregroundColor(AppColors.accent)
                }

                ProgressView(value: vm.progress)
                    .progressViewStyle(.linear)
                    .tint(AppColors.accent)
            }
            .padding(.horizontal, UIConstants.spacingXL)

            Spacer()
        }
    }

    // MARK: - Results View
    // FIXED: Completely rewritten to be self-contained without external component dependencies

    @ViewBuilder
    private func diagnosticResultsView(result: DiagnosticResult) -> some View {
        VStack(spacing: 20) {
            // Health Score Circle
            if let analysis = vm.analysis {
                ZStack {
                    Circle()
                        .stroke(colorForScore(analysis.healthScore), lineWidth: 10)
                        .frame(width: 140, height: 140)
                    VStack(spacing: 4) {
                        Text("\(analysis.healthScore)")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(colorForScore(analysis.healthScore))
                        Text("Health")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 20)

                // Health Label
                Text(analysis.healthScore >= 70 ? "Good" : analysis.healthScore >= 40 ? "Fair" : "Poor")
                    .font(.title3.bold())
                    .foregroundColor(colorForScore(analysis.healthScore))
            }

            // Summary Card
            VStack(spacing: 12) {
                // Status icon
                Image(systemName: statusIcon(for: result.overallStatus))
                    .font(.system(size: 40))
                    .foregroundColor(vm.severityColor)

                // Summary text
                Text(result.summary)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)

                // Issue count
                Text("\(result.issues.count) issue\(result.issues.count == 1 ? "" : "s") found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(12)

            // Test Results Section
            // STEP 3: Use NetworkInterpreter's test results for consistent display
            VStack(alignment: .leading, spacing: 0) {
                Text("Test Results")
                    .font(.headline)
                    .padding(.bottom, 12)

                // Prefer interpreter's test results (shows "Hidden by VPN" instead of "Fail")
                if let interpreterResults = NetworkInterpreter.shared.current?.testResults {
                    ForEach(Array(interpreterResults.enumerated()), id: \.offset) { index, testResult in
                        HStack {
                            Image(systemName: testResult.icon)
                                .foregroundColor(testResult.statusColor)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(testResult.name)
                                    .font(.subheadline)
                                Text(testResult.detail)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(testResult.value)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)

                            Circle()
                                .fill(testResult.statusColor)
                                .frame(width: 10, height: 10)
                        }
                        .padding(.vertical, 8)

                        if index < interpreterResults.count - 1 {
                            Divider()
                        }
                    }
                } else {
                    // Fallback to original diagnostic test results
                    ForEach(Array(result.testsPerformed.enumerated()), id: \.offset) { index, test in
                        HStack {
                            Image(systemName: testResultIcon(test.result))
                                .foregroundColor(testResultColor(test.result))
                                .frame(width: 24)

                            Text(test.name)
                                .font(.subheadline)

                            Spacer()

                            if let latency = test.latency {
                                Text("\(Int(latency))ms")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                            }

                            Circle()
                                .fill(testResultColor(test.result))
                                .frame(width: 10, height: 10)
                        }
                        .padding(.vertical, 8)

                        if index < result.testsPerformed.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            // Issues Section (if any)
            if !result.issues.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Issues Found")
                        .font(.headline)

                    ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(severityColor(issue.severity))
                                .frame(width: 10, height: 10)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.title)
                                    .font(.subheadline.bold())
                                Text(issue.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }

            // Root Cause - STEP 3: Prefer interpreter's root cause for consistency
            if let interpreterRootCause = NetworkInterpreter.shared.current?.rootCause {
                // Use single source of truth from interpreter
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: interpreterRootCause.icon)
                            .foregroundColor(interpreterRootCause.severity.color)
                        Text("Root Cause")
                            .font(.headline)
                    }

                    Text(interpreterRootCause.title)
                        .font(.subheadline.bold())
                        .foregroundColor(interpreterRootCause.severity.color)

                    Text(interpreterRootCause.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else if let analysis = vm.analysis {
                // Fallback to original analysis
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text("Root Cause")
                            .font(.headline)
                    }

                    Text(analysis.beginnerExplanation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }

            Spacer(minLength: 40)
        }
    }

    private func colorForScore(_ score: Int) -> Color {
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }

    // MARK: - Smart Recommendations Card

    private var smartRecommendationsCard: some View {
        let recommendations = SmartRecommendationEngine.shared.generateRecommendations(
            from: NetworkMonitorService.shared.currentStatus,
            speedTest: HistoryManager.shared.speedTestHistory.first
        )
        return SmartRecommendationsCard(recommendations: recommendations)
    }

    // MARK: - Summary Card

    private func summaryCard(result: DiagnosticResult) -> some View {
        CardView {
            VStack(spacing: UIConstants.spacingM) {
                // Status circle
                ZStack {
                    Circle()
                        .fill(vm.severityColor)
                        .frame(width: 80, height: 80)

                    Image(systemName: statusIcon(for: result.overallStatus))
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }

                // Summary
                Text(result.summary)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                // Critical warning
                if result.hasCriticalIssues {
                    Text("⚠️ Critical issues require immediate attention")
                        .font(.caption)
                        .foregroundColor(AppColors.red)
                        .padding(.top, 4)
                }

                // Completion time
                Text("Test completed • \(result.issues.count) issue\(result.issues.count == 1 ? "" : "s") found")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Cause and Explanation Card

    private var causeExplanationCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                // Cause
                VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                    Text("Cause")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)

                    Text(vm.causeText)
                        .font(.headline)
                        .foregroundColor(vm.severityColor)
                }

                Divider()

                // Explanation
                VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                    Text("Explanation")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)

                    Text(vm.explanationText)
                        .font(.body)
                        .foregroundColor(AppColors.textPrimary)
                }
            }
        }
    }

    // MARK: - Recommendation Card

    private var recommendationCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                // Title
                HStack {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundColor(AppColors.accent)
                    Text("Recommended Fix")
                        .font(.headline)
                }

                // Fix description
                Text(vm.recommendationText)
                    .font(.body)
                    .foregroundColor(AppColors.textSecondary)

                // Apply fix button
                if let fixAction = vm.result?.primaryIssue?.fixAction {
                    Button(action: {
                        applyFix(fixAction)
                    }) {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text(vm.result?.primaryIssue?.fixTitle ?? "Apply Fix")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(UIConstants.cornerRadiusM)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Issues List Card

    private func issuesListCard(issues: [IdentifiedIssue]) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                Text("Issues Found (\(issues.count))")
                    .font(.headline)

                ForEach(Array(issues.enumerated()), id: \.offset) { index, issue in
                    issueRow(issue: issue)

                    if index < issues.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func issueRow(issue: IdentifiedIssue) -> some View {
        HStack(alignment: .top, spacing: UIConstants.spacingM) {
            StatusDot(color: severityColor(issue.severity), size: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.subheadline.bold())

                Text(issue.description)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)

                if !issue.estimatedImpact.isEmpty {
                    Text("Impact: \(issue.estimatedImpact)")
                        .font(.caption)
                        .foregroundColor(AppColors.yellow)
                }
            }

            Spacer()
        }
    }

    // MARK: - Test Results Card

    @State private var isTestResultsExpanded = false

    private func testResultsCard(tests: [DiagnosticTest]) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                Button(action: { isTestResultsExpanded.toggle() }) {
                    HStack {
                        Text("Test Results (\(tests.count))")
                            .font(.headline)
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        Image(systemName: isTestResultsExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isTestResultsExpanded {
                    ForEach(Array(tests.enumerated()), id: \.offset) { index, test in
                        testResultRow(test: test)

                        if index < tests.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func testResultRow(test: DiagnosticTest) -> some View {
        HStack {
            Image(systemName: testResultIcon(test.result))
                .foregroundColor(testResultColor(test.result))

            VStack(alignment: .leading, spacing: 2) {
                Text(test.name)
                    .font(.subheadline.bold())

                Text(test.details)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            if let latency = test.latency {
                Text("\(Int(latency))ms")
                    .font(.caption.monospaced())
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Recommendations Card

    private func recommendationsCard(recommendations: [String]) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(AppColors.yellow)
                    Text("Sensei's Advice")
                        .font(.headline)
                }

                ForEach(Array(recommendations.enumerated()), id: \.offset) { index, recommendation in
                    HStack(alignment: .top, spacing: UIConstants.spacingS) {
                        Text("\(index + 1).")
                            .font(.subheadline.bold())
                            .foregroundColor(AppColors.accent)

                        Text(recommendation)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func statusIcon(for health: NetworkHealth) -> String {
        switch health {
        case .excellent: return "checkmark.circle.fill"
        case .fair: return "exclamationmark.triangle.fill"
        case .poor: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private func severityColor(_ severity: IssueSeverity) -> Color {
        switch severity {
        case .critical: return AppColors.red
        case .moderate: return AppColors.yellow
        case .minor: return .blue
        case .none: return AppColors.green
        }
    }

    private func testResultIcon(_ result: DiagnosticTest.TestResult) -> String {
        switch result {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }

    private func testResultColor(_ result: DiagnosticTest.TestResult) -> Color {
        switch result {
        case .pass: return AppColors.green
        case .fail: return AppColors.red
        case .warning: return AppColors.yellow
        case .skipped: return .gray
        }
    }

    private func applyFix(_ action: IdentifiedIssue.FixAction) {
        switch action {
        case .reconnectWiFi:
            openSystemSettings()
        case .restartRouter:
            // Show instructions
            break
        case .switchDNS:
            openSystemSettings()
        case .disconnectVPN:
            Task { @MainActor in
                VPNEngine.shared.disconnectVPN()
            }
        case .reconnectVPN:
            Task {
                await VPNEngine.shared.reconnectVPN()
            }
        case .switchVPNServer:
            // Open VPN app
            break
        case .switchVPNProtocol:
            // Open VPN app
            break
        case .changeCellular:
            openSystemSettings()
        case .forgetNetwork:
            openSystemSettings()
        case .moveCloserToRouter:
            // Show instruction
            break
        case .contactISP:
            // Show ISP contact
            break
        case .changeVPNRegion:
            // Open VPN app
            break
        case .openSystemSettings:
            openSystemSettings()
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Auto-Fix Handler

    private func handleAutoFix(_ action: RootCauseAnalyzer.Analysis.AutoFixAction?) {
        guard let action = action else { return }

        switch action {
        case .restartRouter:
            // Show instructions to restart router
            showRestartRouterInstructions()

        case .switchWifiChannel:
            openSystemSettings()

        case .moveCloserToRouter:
            // Show WiFi tips
            showWiFiTips()

        case .enableVPN:
            // Guide user to enable VPN
            showVPNSetupGuide()

        case .switchVPNRegion(let recommended):
            // Show VPN region selection with recommendation
            showVPNRegionSelector(recommended: recommended)

        case .switchVPNProtocol:
            // Show VPN protocol options
            showVPNProtocolOptions()

        case .changeDNS(let recommended):
            // Show DNS change instructions
            showDNSChangeInstructions(recommended: recommended)

        case .optimizeVPNForStreaming:
            // Show streaming optimization guide
            showStreamingOptimizationGuide()

        case .contactISP:
            // Show ISP contact info
            showISPContactInfo()

        case .reconnectWifi:
            openSystemSettings()

        case .disableVPN:
            Task { @MainActor in
                VPNEngine.shared.disconnectVPN()
            }

        case .none:
            break
        }
    }

    // Auto-fix action implementations

    private func showRestartRouterInstructions() {
        showingRouterGuide = true
    }

    private func showWiFiTips() {
        showingWiFiTips = true
    }

    private func showVPNSetupGuide() {
        showingVPNGuide = true
    }

    private func showVPNRegionSelector(recommended: String) {
        recommendedVPNRegion = recommended
        showingVPNRegionPicker = true
    }

    private func showVPNProtocolOptions() {
        showingVPNProtocolSelector = true
    }

    private func showDNSChangeInstructions(recommended: String) {
        recommendedDNS = recommended
        showingDNSGuide = true
    }

    private func showStreamingOptimizationGuide() {
        // Show streaming-specific VPN optimization guide
        showingStreamingOptimizer = true
    }

    private func showISPContactInfo() {
        showingISPContact = true
    }
}

// MARK: - Preview

struct DiagnosticView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 40)

                    Image(systemName: "stethoscope")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("Network Diagnostic")
                        .font(.title.bold())

                    Text("Comprehensive network analysis")
                        .foregroundColor(.gray)

                    // Sample results
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("WiFi Connection")
                            Spacer()
                            Text("Pass")
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)

                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Router")
                            Spacer()
                            Text("Pass")
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)

                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Internet")
                            Spacer()
                            Text("Pass")
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)

                    Button("Run Diagnostic") { }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)

                    Spacer()
                }
            }
            .navigationTitle("Diagnostic")
            .navigationBarTitleDisplayMode(.inline)
        }
        .previewDisplayName("Diagnostic View")
    }
}
