//
//  SpeedTestView.swift
//  NetoSensei
//
//  Speed test view for measuring network throughput
//  IMPROVED: VPN-aware explanations, activity checklist, improvement tips
//

import SwiftUI

/// Speed test view for modal/sheet presentation
struct SpeedTestView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = SpeedTestViewModel()

    var body: some View {
        NavigationView {
            SpeedTestContentView(vm: vm)
                .navigationTitle("Speed Test")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }

                    if vm.hasHistory {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("History") {
                                // Show history
                            }
                        }
                    }
                }
        }
    }
}

/// Speed test content view (reusable in tabs or sheets)
struct SpeedTestContentView: View {
    @ObservedObject var vm: SpeedTestViewModel

    @AppStorage("ispPlanDownloadMbps") private var ispPlanDownload: Double = 0
    @AppStorage("ispPlanUploadMbps") private var ispPlanUpload: Double = 0
    @State private var showingISPPlanSheet = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: UIConstants.spacingL) {
                    if vm.isRunning {
                        // Running test
                        runningView
                    } else if let result = vm.result {
                        // Results
                        resultsView(result: result)
                    } else {
                        // Intro
                        introView
                    }
                }
                .padding()
            }

            // Loading overlay
            if vm.isRunning {
                LoadingOverlay(
                    message: vm.currentTest,
                    progress: vm.progress
                )
            }
        }
        .sheet(isPresented: $showingISPPlanSheet) {
            ISPPlanSettingsSheet(
                downloadMbps: $ispPlanDownload,
                uploadMbps: $ispPlanUpload
            )
        }
    }

    // MARK: - Intro View

    private var introView: some View {
        VStack(spacing: UIConstants.spacingXL) {
            Spacer()

            Image(systemName: "speedometer")
                .font(.system(size: UIConstants.iconSizeXL * 2))
                .foregroundColor(AppColors.accent)

            VStack(spacing: UIConstants.spacingM) {
                Text("Speed Test")
                    .font(.largeTitle.bold())

                Text("Measure your download and upload speeds, ping, and network quality.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal)
            }

            Button(action: {
                // Haptic feedback on button press
                HapticFeedback.medium()
                vm.runSpeedTest()
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Start Speed Test")
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
            .accessibleAction(label: "Start Speed Test", hint: "Double tap to begin measuring your network speed")

            Spacer()
        }
    }

    // MARK: - Running View

    private var runningView: some View {
        VStack(spacing: UIConstants.spacingXL) {
            Spacer()

            ProgressView(value: vm.progress) {
                VStack(spacing: UIConstants.spacingS) {
                    Text("Testing speed...")
                        .font(.headline)

                    Text("\(Int(vm.progress * 100))%")
                        .font(.title.bold())
                        .foregroundColor(AppColors.accent)
                }
            }
            .progressViewStyle(.linear)
            .tint(AppColors.accent)
            .frame(width: 250)

            Text(vm.phaseDescription)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Results View

    @ViewBuilder
    private func resultsView(result: SpeedTestResult) -> some View {
        // FIXED: Show complete failure state when BOTH download AND upload fail
        if result.downloadSpeed < 0.1 && result.uploadSpeed < 0.1 {
            completeFailureView
        } else {
            // Big download number
            downloadSpeedCard(result: result)

            // Metrics row with explanations
            metricsRow(result: result)

            // VPN Context (only if VPN is confidently detected)
            if result.vpnActive {
                vpnContextCard(result: result)
            }

            // Quality card with VPN awareness
            qualityCard(result: result)

            // ISP Plan comparison (only when not on VPN — VPN measures the tunnel, not the plan)
            if !result.vpnActive {
                ispPlanCard(result: result)
            }

            // What can you do with this speed
            activityChecklist(result: result)

            // How to improve
            improvementTips(result: result)

            // Retest button
            retestButton
        }
    }

    // MARK: - Complete Failure View

    private var completeFailureView: some View {
        VStack(spacing: UIConstants.spacingXL) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(AppColors.red)

            VStack(spacing: UIConstants.spacingM) {
                Text("Test Failed")
                    .font(.title.bold())

                Text("Unable to measure network speed. This could be caused by:")
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                    Text("• VPN or proxy blocking test servers")
                    Text("• Firewall restrictions")
                    Text("• Very slow or unstable connection")
                    Text("• Network timeout")
                }
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
            }

            Button(action: {
                HapticFeedback.medium()
                vm.runSpeedTest()
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Tap to Retry")
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

            Spacer()
        }
    }

    // MARK: - Download Speed Card

    private func downloadSpeedCard(result: SpeedTestResult) -> some View {
        CardView {
            VStack(spacing: UIConstants.spacingM) {
                Text("Download Speed")
                    .font(.headline)
                    .foregroundColor(AppColors.textSecondary)

                if result.downloadSpeed < 0.1 {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(AppColors.yellow)
                        Text("Test Failed")
                            .font(.title2.bold())
                            .foregroundColor(AppColors.textSecondary)
                        Text("Unable to measure download speed")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding()
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", result.downloadSpeed))
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(AppColors.accent)
                        Text("Mbps")
                            .font(.title3)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                HStack(spacing: UIConstants.spacingXL) {
                    VStack {
                        Text("Upload")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Text(result.uploadSpeed < 0.1 ? "Failed" : String(format: "%.1f Mbps", result.uploadSpeed))
                            .font(.headline)
                            .foregroundColor(result.uploadSpeed < 0.1 ? AppColors.textSecondary : AppColors.textPrimary)
                    }

                    VStack {
                        Text("Ping")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Text(String(format: "%.0f ms", result.ping))
                            .font(.headline)
                    }
                }
            }
        }
    }

    // MARK: - Metrics Row with Explanations

    private func metricsRow(result: SpeedTestResult) -> some View {
        VStack(spacing: UIConstants.spacingM) {
            HStack(spacing: UIConstants.spacingM) {
                MetricBox(
                    title: "Jitter",
                    value: String(format: "%.0f", result.jitter),
                    unit: "ms",
                    color: jitterColor(result.jitter, vpnActive: result.vpnActive),
                    icon: "waveform.path.ecg"
                )

                MetricBox(
                    title: "Packet Loss",
                    value: String(format: "%.1f", result.packetLoss),
                    unit: "%",
                    color: packetLossColor(result.packetLoss),
                    icon: "antenna.radiowaves.left.and.right.slash"
                )
            }

            // Jitter explanation
            Text(jitterExplanation(result: result))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Ping explanation
            Text(pingExplanation(result: result))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - VPN Context Card

    private func vpnContextCard(result: SpeedTestResult) -> some View {
        CardView {
            HStack(alignment: .top, spacing: UIConstants.spacingM) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(AppColors.accent)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Testing Through VPN")
                        .font(.subheadline.bold())

                    Text("This measures your speed through the VPN tunnel. Your actual WiFi/cellular speed is likely faster.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)

                    Text("The \(Int(result.ping))ms ping is VPN round-trip time, not your local network latency.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Quality Card

    private func qualityCard(result: SpeedTestResult) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Text("Network Quality")
                        .font(.headline)

                    Spacer()

                    Text(result.qualityDescription)
                        .font(.headline.bold())
                        .foregroundColor(qualityColor(result.quality, vpnActive: result.vpnActive))
                }

                Divider()

                // Streaming guide
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "play.rectangle")
                            .foregroundColor(AppColors.textSecondary)
                        Text("Streaming Guide")
                            .font(.subheadline.bold())
                    }

                    Text(streamingGuideText(result: result))
                        .font(.caption)
                        .foregroundColor(streamingGuideColor(result: result))
                }
            }
        }
    }

    // MARK: - ISP Plan Comparison Card

    @ViewBuilder
    private func ispPlanCard(result: SpeedTestResult) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "building.2.fill")
                        .foregroundColor(AppColors.accent)
                    Text("Your ISP Plan")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingISPPlanSheet = true }) {
                        Image(systemName: ispPlanDownload > 0 ? "pencil" : "plus")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accent)
                }

                if ispPlanDownload <= 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .foregroundColor(AppColors.textSecondary)
                        Text("Set your ISP plan speed to compare actual results.")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                } else {
                    let downloadPct = (result.downloadSpeed / ispPlanDownload) * 100
                    ispPlanRow(
                        label: "Download",
                        actual: result.downloadSpeed,
                        plan: ispPlanDownload,
                        percent: downloadPct
                    )

                    if ispPlanUpload > 0 {
                        let uploadPct = (result.uploadSpeed / ispPlanUpload) * 100
                        ispPlanRow(
                            label: "Upload",
                            actual: result.uploadSpeed,
                            plan: ispPlanUpload,
                            percent: uploadPct
                        )
                    }

                    Text(ispPlanSummary(downloadPercent: downloadPct))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    private func ispPlanRow(label: String, actual: Double, plan: Double, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: "%.1f / %.0f Mbps", actual, plan))
                    .font(.caption.monospaced())
                    .foregroundColor(AppColors.textSecondary)
                Text(String(format: "%.0f%%", percent))
                    .font(.subheadline.bold())
                    .foregroundColor(ispPlanPercentColor(percent))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.textSecondary.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ispPlanPercentColor(percent))
                        .frame(width: max(0, min(1, percent / 100)) * geo.size.width, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func ispPlanPercentColor(_ percent: Double) -> Color {
        if percent >= 80 { return AppColors.green }
        if percent >= 50 { return Color.orange }
        return AppColors.red
    }

    private func ispPlanSummary(downloadPercent: Double) -> String {
        if downloadPercent >= 90 {
            return "You're getting your full plan speed."
        } else if downloadPercent >= 80 {
            return "Close to your plan speed — normal variation."
        } else if downloadPercent >= 50 {
            return "Below your plan speed. Try moving closer to the router or restarting it."
        } else {
            return "Far below your plan speed. Contact your ISP if this persists."
        }
    }

    // MARK: - Activity Checklist

    private func activityChecklist(result: SpeedTestResult) -> some View {
        // FIX (Speed Issue 2/6): SAME ConnectionCapabilityAnalyzer that drives
        // the Streaming tab icon row and per-service detail. Eliminates the
        // bug where this checklist green-checked Video Calls while the
        // Streaming tab simultaneously called them "SD video calls".
        let capability = ConnectionCapabilityAnalyzer.analyze(from: result)

        return CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                Text("What can you do with this speed?")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    activityRow(
                        icon: "globe",
                        activity: "Web browsing & email",
                        requirement: "1+ Mbps",
                        rating: capability.web
                    )
                    activityRow(
                        icon: "play.rectangle",
                        activity: "Streaming (480p SD)",
                        requirement: "3+ Mbps",
                        rating: capability.streamingSD
                    )
                    activityRow(
                        icon: "play.rectangle.fill",
                        activity: "HD streaming (720p-1080p)",
                        requirement: "8+ Mbps",
                        rating: capability.streamingHD
                    )
                    activityRow(
                        icon: "video",
                        activity: "Video calls (Zoom/FaceTime)",
                        requirement: "5+ Mbps, ≤150ms ping, ≤30ms jitter",
                        rating: capability.videoCalls
                    )
                    activityRow(
                        icon: "gamecontroller",
                        activity: "Online gaming",
                        requirement: "10+ Mbps, ≤50ms ping",
                        rating: capability.gaming
                    )
                    activityRow(
                        icon: "4k.tv",
                        activity: "4K streaming",
                        requirement: "25+ Mbps",
                        rating: capability.streaming4K
                    )
                }
            }
        }
    }

    /// FIX (Speed Issue 1/6): three-state icon (✓ green / ⚠️ yellow / ✗ red)
    /// instead of binary works/doesn't-work. A 170ms-ping connection should
    /// show ⚠️ for video calls (audio-only), not a flat ✗.
    private func activityRow(icon: String, activity: String, requirement: String, rating: ActivityRating) -> some View {
        let tint: Color = {
            switch rating {
            case .excellent, .good: return AppColors.green
            case .degraded: return AppColors.yellow
            case .poor: return AppColors.red
            }
        }()
        return HStack(spacing: 12) {
            Image(systemName: rating.sfSymbol)
                .foregroundColor(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity)
                    .font(.subheadline)
                Text(requirement)
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Improvement Tips

    private func improvementTips(result: SpeedTestResult) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                Text("How to improve your speed")
                    .font(.headline)

                if result.vpnActive {
                    tipRow(number: 1, tip: "Switch VPN server", detail: "A server closer to you or less crowded could double your speed.")
                    tipRow(number: 2, tip: "Try WireGuard protocol", detail: "WireGuard is usually the fastest VPN protocol. Check your VPN app settings.")
                    tipRow(number: 3, tip: "Test without VPN", detail: "Disconnect VPN and run the test again to see your actual internet speed.")
                } else {
                    // FIXED: Check quality rating, not just download speed
                    // Prevents saying "Your speed is good" when quality is "Poor" due to latency
                    if result.quality == .poor || result.quality == .fair {
                        if result.ping > 100 {
                            tipRow(number: 1, tip: "High latency detected (\(Int(result.ping))ms)", detail: "This makes browsing feel sluggish. Try restarting your router or check your ISP connection.")
                        }
                        if result.downloadSpeed < 10 {
                            tipRow(number: 2, tip: "Move closer to your WiFi router", detail: "WiFi signal weakens with distance and walls.")
                        }
                        tipRow(number: 3, tip: "Restart your router", detail: "Unplug for 30 seconds, then plug back in. This clears the router's memory.")
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your speed is good")
                                    .font(.subheadline.bold())
                                Text("No immediate improvements needed.")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func tipRow(number: Int, tip: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(AppColors.accent))

            VStack(alignment: .leading, spacing: 2) {
                Text(tip)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Retest Button

    private var retestButton: some View {
        Button(action: {
            vm.runSpeedTest()
        }) {
            HStack {
                Image(systemName: "arrow.clockwise")
                Text("Run Again")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppColors.card)
            .foregroundColor(AppColors.accent)
            .cornerRadius(UIConstants.cornerRadiusM)
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadiusM)
                    .stroke(AppColors.accent, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Functions

    private func jitterExplanation(result: SpeedTestResult) -> String {
        // FIX (Speed Issue 3): Jitter thresholds now match the user's spec
        // (and reality):
        //   < 10ms  Excellent
        //   10-25   Low
        //   25-50   Moderate
        //   50-100  High
        //   > 100   Very High
        // Previously 42ms got the green "Low jitter" label, which is wrong
        // (42ms is moderate). Same scale used regardless of VPN — VPN doesn't
        // make 42ms of jitter "stable", it just makes it more common.
        let jitter = result.jitter
        let vpnNote = result.vpnActive ? " — typical for international VPN connections" : ""

        if jitter > 100 {
            return "Very high jitter (\(Int(jitter))ms) — your connection is unstable. Video calls and gaming will suffer.\(vpnNote)"
        } else if jitter > 50 {
            return "High jitter (\(Int(jitter))ms) — video calls may stutter and gaming will feel laggy.\(vpnNote)"
        } else if jitter > 25 {
            return "Moderate jitter (\(Int(jitter))ms)\(vpnNote)."
        } else if jitter > 10 {
            return "Low jitter (\(Int(jitter))ms) — your connection is stable. Great for video calls and gaming."
        } else {
            return "Excellent jitter (\(Int(jitter))ms) — rock solid stability."
        }
    }

    private func pingExplanation(result: SpeedTestResult) -> String {
        let ping = result.ping

        if result.vpnActive {
            return "\(Int(ping))ms is the round-trip time through your VPN. Your local network latency is much lower — this delay is mostly the VPN tunnel."
        } else {
            if ping > 100 {
                return "\(Int(ping))ms is slow. Web pages will feel sluggish. Try restarting your router."
            } else if ping > 30 {
                return "\(Int(ping))ms is okay for browsing but not ideal for gaming."
            } else {
                return "\(Int(ping))ms is excellent. Everything should feel snappy."
            }
        }
    }

    private func streamingGuideText(result: SpeedTestResult) -> String {
        let download = result.downloadSpeed

        if download >= 25 {
            return "Your speed supports 4K streaming on Netflix, YouTube, and other services."
        } else if download >= 8 {
            return "Your speed supports 1080p HD streaming. For 4K, you'd need about \(Int(25 - download)) Mbps more."
        } else if download >= 3 {
            return "Your speed supports 720p streaming. HD content may buffer occasionally."
        } else {
            if result.vpnActive {
                return "Your speed is too slow for smooth video streaming. Try switching to a faster VPN server."
            } else {
                return "Your speed is too slow for smooth video streaming. Try restarting your router or moving closer to it."
            }
        }
    }

    private func streamingGuideColor(result: SpeedTestResult) -> Color {
        let download = result.downloadSpeed
        if download >= 25 { return AppColors.green }
        if download >= 8 { return AppColors.textSecondary }
        if download >= 3 { return Color.orange }
        return AppColors.red
    }

    private func jitterColor(_ jitter: Double, vpnActive: Bool) -> Color {
        // FIX (Speed Issue 3): Aligned to the explanatory text thresholds.
        // 42ms now lights up yellow ("Moderate"), not green. Same thresholds
        // regardless of VPN — VPN context lives in the explanatory string.
        if jitter < 10 { return AppColors.green }
        if jitter < 25 { return AppColors.green }
        if jitter < 50 { return AppColors.yellow }
        if jitter < 100 { return Color.orange }
        return AppColors.red
    }

    private func packetLossColor(_ loss: Double) -> Color {
        NetworkColors.forPacketLoss(loss)
    }

    private func qualityColor(_ quality: SpeedTestResult.QualityRating, vpnActive: Bool) -> Color {
        switch quality {
        case .excellent, .good: return AppColors.green
        case .fair: return Color.orange
        case .poor: return AppColors.red
        }
    }
}

// MARK: - ISP Plan Settings Sheet

struct ISPPlanSettingsSheet: View {
    @Binding var downloadMbps: Double
    @Binding var uploadMbps: Double
    @Environment(\.dismiss) private var dismiss

    @State private var downloadInput: String = ""
    @State private var uploadInput: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        TextField("e.g. 100", text: $downloadInput)
                            .keyboardType(.decimalPad)
                        Text("Mbps")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                        TextField("e.g. 20 (optional)", text: $uploadInput)
                            .keyboardType(.decimalPad)
                        Text("Mbps")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Your ISP Plan Speed")
                } footer: {
                    Text("Enter the speeds advertised by your internet provider. Speed test results will be compared against these values.")
                }

                if downloadMbps > 0 || uploadMbps > 0 {
                    Section {
                        Button(role: .destructive) {
                            downloadMbps = 0
                            uploadMbps = 0
                            downloadInput = ""
                            uploadInput = ""
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear ISP Plan")
                            }
                        }
                    }
                }
            }
            .navigationTitle("ISP Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        downloadMbps = Double(downloadInput) ?? 0
                        uploadMbps = Double(uploadInput) ?? 0
                        dismiss()
                    }
                    .disabled(Double(downloadInput) == nil && !downloadInput.isEmpty)
                }
            }
            .onAppear {
                downloadInput = downloadMbps > 0 ? String(format: "%g", downloadMbps) : ""
                uploadInput = uploadMbps > 0 ? String(format: "%g", uploadMbps) : ""
            }
        }
    }
}

// MARK: - Preview

struct SpeedTestView_Previews: PreviewProvider {
    static var previews: some View {
        SpeedTestView()
    }
}
