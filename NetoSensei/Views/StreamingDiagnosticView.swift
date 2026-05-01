//
//  StreamingDiagnosticView.swift
//  NetoSensei
//
//  Streaming diagnostic view for CDN and streaming tests
//  STEP 6 - Integration
//

import SwiftUI

/// Streaming diagnostic view for modal/sheet presentation
struct StreamingDiagnosticView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = StreamingDiagnosticViewModel()

    var body: some View {
        NavigationView {
            StreamingDiagnosticContentView(vm: vm)
                .navigationTitle("Streaming Diagnostic")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }

                    if vm.hasResult && !vm.isRunning {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Run Again") {
                                vm.reset()
                            }
                        }
                    }
                }
        }
    }
}

/// Streaming diagnostic content view (reusable in tabs or sheets)
struct StreamingDiagnosticContentView: View {
    @ObservedObject var vm: StreamingDiagnosticViewModel

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
    }

    // MARK: - Intro View

    private var introView: some View {
        VStack(spacing: UIConstants.spacingXL) {
            Spacer()

            Image(systemName: "play.tv.fill")
                .font(.system(size: UIConstants.iconSizeXL * 2))
                .foregroundColor(AppColors.accent)

            VStack(spacing: UIConstants.spacingM) {
                Text("Streaming Diagnostic")
                    .font(.largeTitle.bold())

                Text("Test why your streaming is slow. We'll analyze CDN performance, Wi-Fi quality, and identify bottlenecks.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal)
            }

            // Platform Selector
            platformSelector

            Button(action: {
                Task {
                    await vm.runStreamingDiagnostic()
                }
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Start Streaming Test")
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

    // MARK: - Platform Selector

    private var platformSelector: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacingM) {
            Text("Select Platform")
                .font(.headline)
                .foregroundColor(AppColors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: UIConstants.spacingM) {
                    ForEach(StreamingPlatform.allCases, id: \.self) { platform in
                        PlatformButton(
                            platform: platform,
                            isSelected: vm.selectedPlatform == platform,
                            action: {
                                vm.selectedPlatform = platform
                            }
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Running View

    private var runningView: some View {
        VStack(spacing: UIConstants.spacingXL) {
            Spacer()

            ProgressView(value: vm.progress) {
                VStack(spacing: UIConstants.spacingS) {
                    Text("Testing streaming...")
                        .font(.headline)

                    Text("\(Int(vm.progress * 100))%")
                        .font(.title.bold())
                        .foregroundColor(AppColors.accent)
                }
            }
            .progressViewStyle(.linear)
            .tint(AppColors.accent)
            .frame(width: 250)

            Text(vm.currentTest)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Results View

    @ViewBuilder
    private func resultsView(result: StreamingDiagnosticResult) -> some View {
        // Streaming Capability (from speed test)
        streamingCapabilityCard

        // Platform info
        platformInfoCard(result: result)

        // Bottleneck card
        bottleneckCard(result: result)

        // Recommendation
        recommendationCard(result: result)
    }

    // MARK: - Streaming Capability Card (Based on Speed Test)

    private var streamingCapabilityCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                Text("Streaming Capability")
                    .font(.headline)

                if let lastSpeed = HistoryManager.shared.speedTestHistory.first {
                    let capability = lastSpeed.streamingCapability
                    // FIX (Speed Issue 1/6): the "Max Quality" line now reads
                    // from ConnectionCapabilityAnalyzer, the same source the
                    // icon row at the top uses. Previously the icon row said
                    // "no 4K" while max-quality could simultaneously promise
                    // 4K — three views, three answers.
                    let unifiedCapability = ConnectionCapabilityAnalyzer.analyze(from: lastSpeed)

                    // Show max quality (unified)
                    HStack {
                        Image(systemName: "play.tv.fill")
                            .foregroundColor(AppColors.accent)
                        Text("Max Quality: \(unifiedCapability.maxStreamingQuality.rawValue)")
                            .font(.title3.bold())
                    }

                    Divider()

                    // Platform-specific capabilities
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(capability.supportedPlatforms, id: \.platform) { platform in
                            HStack {
                                Text(platform.platform)
                                    .frame(width: 80, alignment: .leading)
                                Text(platform.maxQuality.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(qualityColor(platform.maxQuality).opacity(0.2))
                                    .foregroundColor(qualityColor(platform.maxQuality))
                                    .cornerRadius(4)
                                Spacer()
                                Text(platform.expectedBuffering.rawValue)
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    Divider()

                    // FIX (Speed Issue 2): Video Calls / Gaming labels now come
                    // from ConnectionCapabilityAnalyzer too, so the Speed Test
                    // tab and the Streaming tab agree.
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Video Calls")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Text(unifiedVideoCallText(unifiedCapability.videoCalls))
                                .font(.caption.bold())
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Gaming")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Text(unifiedGamingText(unifiedCapability.gaming))
                                .font(.caption.bold())
                        }
                    }

                    // Limiting factor
                    if let factor = capability.limitingFactor, factor != .none {
                        Text("Limiting factor: \(factor.rawValue)")
                            .font(.caption)
                            .foregroundColor(AppColors.yellow)
                            .padding(.top, 4)
                    }

                    // Source info
                    Text("Based on speed test: \(String(format: "%.1f", lastSpeed.downloadSpeed)) Mbps down, \(String(format: "%.1f", lastSpeed.uploadSpeed)) Mbps up, \(Int(lastSpeed.ping))ms")
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.top, 4)

                } else {
                    // No speed test data
                    VStack(spacing: UIConstants.spacingM) {
                        Image(systemName: "speedometer")
                            .font(.title)
                            .foregroundColor(AppColors.textSecondary)
                        Text("Run a speed test first to see streaming capability")
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        }
    }

    // FIX (Speed Issue 2): unified labels match the Speed Test tab so users
    // don't see "HD video calls" in one place and "SD video calls" in another.
    private func unifiedVideoCallText(_ rating: ActivityRating) -> String {
        switch rating {
        case .excellent: return "HD video calls with screen sharing"
        case .good: return "HD video calls"
        case .degraded: return "Audio-only recommended"
        case .poor: return "Video calls not recommended"
        }
    }

    private func unifiedGamingText(_ rating: ActivityRating) -> String {
        switch rating {
        case .excellent: return "Competitive gaming ready"
        case .good: return "Casual gaming"
        case .degraded: return "Single player only"
        case .poor: return "Gaming not recommended"
        }
    }

    private func qualityColor(_ quality: StreamingCapability.VideoQuality) -> Color {
        switch quality {
        case .uhd4K: return AppColors.green
        case .fullHD: return AppColors.green
        case .hd720: return AppColors.yellow
        case .sd480: return .orange  // No AppColors.orange, use native
        case .sd360, .audioOnly: return AppColors.red
        }
    }

    private func platformInfoCard(result: StreamingDiagnosticResult) -> some View {
        CardView {
            VStack(spacing: UIConstants.spacingM) {
                Text(result.platform.rawValue.capitalized)
                    .font(.title2.bold())

                HStack(spacing: UIConstants.spacingXL) {
                    VStack {
                        Text("CDN Ping")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Text("\(Int(result.cdnPing))ms")
                            .font(.title3.bold())
                            .foregroundColor(cdnPingColor(result.cdnPing))
                    }

                    VStack {
                        Text("Throughput")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                        // FIXED: 0.0 Mbps should show error, not a valid value
                        Text(throughputDisplayText(result.cdnThroughput))
                            .font(.title3.bold())
                            .foregroundColor(throughputDisplayColor(result.cdnThroughput))
                    }
                }
            }
        }
    }

    private func bottleneckCard(result: StreamingDiagnosticResult) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                Text("Primary Bottleneck")
                    .font(.headline)

                // FIX (Speed Issue 4): use VPN-aware display label so the
                // header reads "VPN Server Distance" instead of the
                // misleading "CDN Routing" when the user is on a VPN.
                Text(result.primaryBottleneckDisplay)
                    .font(.title3.bold())
                    .foregroundColor(AppColors.red)

                if !result.secondaryFactors.isEmpty {
                    Text("Contributing Factors:")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)

                    ForEach(result.secondaryFactors, id: \.self) { factor in
                        HStack {
                            StatusDot(color: AppColors.yellow, size: 8)
                            Text(factor.rawValue.capitalized)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func recommendationCard(result: StreamingDiagnosticResult) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(AppColors.yellow)
                    Text("Sensei's Advice")
                        .font(.headline)
                }

                Text(result.recommendation)
                    .font(.body)
                    .foregroundColor(AppColors.textPrimary)

                if !result.actionableSteps.isEmpty {
                    Divider()

                    Text("Recommended Actions:")
                        .font(.subheadline.bold())

                    ForEach(Array(result.actionableSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: UIConstants.spacingS) {
                            Text("\(index + 1).")
                                .font(.subheadline.bold())
                                .foregroundColor(AppColors.accent)

                            Text(step)
                                .font(.subheadline)

                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func cdnPingColor(_ ping: Double) -> Color {
        if ping < 50 { return AppColors.green }
        else if ping < 150 { return AppColors.yellow }
        else { return AppColors.red }
    }

    private func throughputColor(_ throughput: Double) -> Color {
        if throughput >= 25 { return AppColors.green }
        else if throughput >= 5 { return AppColors.yellow }
        else { return AppColors.red }
    }

    // FIXED: Show streaming capability when throughput test fails
    // The capability is calculated from the last speed test result
    private func throughputDisplayText(_ throughput: Double) -> String {
        if throughput < 0 {
            // CDN blocked - show capability based on speed test
            if let lastSpeed = HistoryManager.shared.speedTestHistory.first {
                let capability = lastSpeed.streamingCapability
                return capability.maxVideoQuality.rawValue
            }
            return "CDN blocked"
        } else if throughput < 0.1 {
            // Test failed - show capability based on speed test
            if let lastSpeed = HistoryManager.shared.speedTestHistory.first {
                let capability = lastSpeed.streamingCapability
                return capability.maxVideoQuality.rawValue
            }
            return "Run speed test"
        } else {
            return String(format: "%.1f Mbps", throughput)
        }
    }

    private func throughputDisplayColor(_ throughput: Double) -> Color {
        if throughput < 0 || throughput < 0.1 {
            return AppColors.textSecondary
        } else {
            return throughputColor(throughput)
        }
    }
}

// MARK: - Platform Button

struct PlatformButton: View {
    let platform: StreamingPlatform
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: platformIcon)
                    .font(.system(size: 32))
                    .foregroundColor(isSelected ? .white : AppColors.textSecondary)

                Text(platform.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : AppColors.textPrimary)
            }
            .frame(width: 100, height: 90)
            .background(isSelected ? AppColors.accent : AppColors.card)
            .cornerRadius(UIConstants.cornerRadiusM)
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadiusM)
                    .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var platformIcon: String {
        switch platform {
        case .netflix: return "play.rectangle.fill"
        case .youtube: return "play.circle.fill"
        case .tiktok: return "music.note"
        case .twitch: return "video.fill"
        case .disneyPlus: return "star.fill"
        case .amazonPrime: return "shippingbox.fill"
        case .appleTV: return "tv.fill"
        case .hulu: return "rectangle.stack.fill"
        }
    }
}

// MARK: - Preview

struct StreamingDiagnosticView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 20)

                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)

                    Text("Streaming Diagnostic")
                        .font(.title.bold())

                    Text("Test streaming platform connectivity")
                        .foregroundColor(.gray)

                    // Platform buttons
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(["Netflix", "YouTube", "TikTok", "Twitch"], id: \.self) { platform in
                            VStack {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.title)
                                Text(platform)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle("Streaming")
            .navigationBarTitleDisplayMode(.inline)
        }
        .previewDisplayName("Streaming Diagnostic")
    }
}
