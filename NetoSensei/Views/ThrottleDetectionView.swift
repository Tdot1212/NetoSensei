//
//  ThrottleDetectionView.swift
//  NetoSensei
//
//  ISP Throttle Detection view - compares speeds to different endpoints
//  IMPROVED: VPN-aware, plain-English explanations, no false positives
//

import SwiftUI

struct ThrottleDetectionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = ThrottleDetectionViewModel()

    var body: some View {
        NavigationView {
            ThrottleDetectionContentView(vm: vm)
                .navigationTitle("ISP Throttle Test")
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
                                Task {
                                    await vm.runTest()
                                }
                            }
                        }
                    }
                }
        }
    }
}

// MARK: - Content View

struct ThrottleDetectionContentView: View {
    @ObservedObject var vm: ThrottleDetectionViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: UIConstants.spacingL) {
                if vm.isRunning {
                    runningView
                } else if let result = vm.result {
                    resultsView(result: result)
                } else {
                    introView
                }
            }
            .padding()
        }
    }

    // MARK: - Intro View

    private var introView: some View {
        VStack(spacing: UIConstants.spacingXL) {
            Spacer()

            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: UIConstants.iconSizeXL * 2))
                .foregroundColor(AppColors.accent)

            VStack(spacing: UIConstants.spacingM) {
                Text("ISP Throttle Test")
                    .font(.largeTitle.bold())

                Text("Detect if your ISP is throttling specific services. We'll compare download speeds from multiple CDNs to identify selective throttling.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal)
            }

            // What is throttling
            CardView {
                VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(AppColors.accent)
                        Text("What is ISP Throttling?")
                            .font(.headline)
                    }

                    Text("ISP throttling is when your internet provider intentionally slows down specific types of traffic (like streaming or gaming) while keeping other traffic fast. This test compares speeds to different services to detect this behavior.")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            // How it works
            CardView {
                VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                    Text("How It Works")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                        howItWorksStep("1.", "Download test files from multiple CDNs")
                        howItWorksStep("2.", "Measure and compare download speeds")
                        howItWorksStep("3.", "Identify if any services are significantly slower")
                    }
                }
            }

            Button(action: {
                Task {
                    await vm.runTest()
                }
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Start Throttle Test")
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

    private func howItWorksStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top) {
            Text(number)
                .foregroundColor(AppColors.accent)
                .font(.subheadline.bold())
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Running View

    private var runningView: some View {
        VStack(spacing: UIConstants.spacingXL) {
            Spacer()

            ProgressView(value: vm.progress) {
                VStack(spacing: UIConstants.spacingS) {
                    Text("Testing Endpoints...")
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

            Spacer()
        }
    }

    // MARK: - Results View

    @ViewBuilder
    private func resultsView(result: ThrottleAnalysis) -> some View {
        // FIX (Phase 6.2): If the test was skipped because VPN is active,
        // render the explanation + recommendation only. Don't show a baseline
        // of 0 Mbps, "0/0 valid tests", or an empty results table.
        if result.wasSkipped {
            CardView {
                VStack(spacing: UIConstants.spacingM) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .font(.title)
                            .foregroundColor(AppColors.accent)
                        Text(result.overallStatus)
                            .font(.title3.bold())
                            .foregroundColor(AppColors.accent)
                    }
                    Text(result.summary)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                }
            }
            explanationCard(result: result)
            recommendationCard(result: result)
        } else {
            // Summary Card
            CardView {
                VStack(spacing: UIConstants.spacingM) {
                    HStack {
                        Image(systemName: statusIcon(result))
                            .font(.title)
                            .foregroundColor(statusColor(result.overallStatusColor))

                        Text(result.overallStatus)
                            .font(.title3.bold())
                            .foregroundColor(statusColor(result.overallStatusColor))
                    }

                    HStack(spacing: UIConstants.spacingM) {
                        if result.baselineSpeed > 0 {
                            VStack {
                                Text("Baseline")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                                Text("\(String(format: "%.1f", result.baselineSpeed)) Mbps")
                                    .font(.subheadline.bold())
                            }
                        }

                        VStack {
                            Text("Valid Tests")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Text("\(result.validTestCount)/\(result.results.count)")
                                .font(.subheadline.bold())
                        }

                        VStack {
                            Text("Confidence")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Text(result.confidence.rawValue)
                                .font(.subheadline.bold())
                                .foregroundColor(confidenceColor(result.confidence))
                        }
                    }

                    Text(result.summary)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                }
            }

            // Plain-English Explanation
            explanationCard(result: result)

            // Results List
            CardView {
                VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                    HStack {
                        Text("Test Results")
                            .font(.headline)
                        Spacer()
                        Text("by speed")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    ForEach(result.results.sorted(by: { ($0.speedMbps ?? -1) > ($1.speedMbps ?? -1) })) { endpoint in
                        endpointRow(endpoint: endpoint, baseline: result.baselineSpeed)
                        if endpoint.id != result.results.last?.id {
                            Divider()
                        }
                    }
                }
            }

            // Recommendation Card
            recommendationCard(result: result)
        }
    }

    // MARK: - VPN Active Card

    private var vpnActiveCard: some View {
        CardView {
            HStack(spacing: UIConstants.spacingM) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(AppColors.accent)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("VPN Active")
                        .font(.subheadline.bold())
                    Text("Your traffic is encrypted. Speed differences are likely due to server locations, not ISP throttling.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Explanation Card

    private func explanationCard(result: ThrottleAnalysis) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(AppColors.accent)
                    Text("What Does This Mean?")
                        .font(.headline)
                }

                Text(result.explanation)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Recommendation Card

    private func recommendationCard(result: ThrottleAnalysis) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(AppColors.yellow)
                    Text("Recommendation")
                        .font(.headline)
                }

                Text(result.recommendation)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textPrimary)
            }
        }
    }

    // MARK: - Endpoint Row

    private func endpointRow(endpoint: ThrottleResult, baseline: Double) -> some View {
        HStack {
            Image(systemName: endpoint.statusIcon)
                .foregroundColor(statusColor(endpoint.statusColor))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(endpoint.endpoint)
                        .font(.subheadline.bold())

                    Text(endpoint.category)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(AppColors.accent.opacity(0.2))
                        .foregroundColor(AppColors.accent)
                        .cornerRadius(3)
                }

                // Status text
                Group {
                    switch endpoint.status {
                    case .success:
                        if endpoint.throttled, let percent = endpoint.percentSlower {
                            Text("\(Int(percent))% slower than baseline")
                                .foregroundColor(Color.orange)
                        } else if let percent = endpoint.percentSlower, percent > 20 {
                            Text("\(Int(percent))% slower")
                                .foregroundColor(AppColors.textSecondary)
                        } else {
                            Text("Normal speed")
                                .foregroundColor(AppColors.green)
                        }
                    case .endpointError:
                        Text(endpoint.note ?? "Endpoint returned insufficient data")
                            .foregroundColor(AppColors.yellow)
                    case .failed, .timeout:
                        Text(endpoint.statusText)
                            .foregroundColor(.gray)
                    }
                }
                .font(.caption)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(endpoint.displaySpeed)
                    .font(.subheadline.bold().monospaced())
                    .foregroundColor(statusColor(endpoint.statusColor))

                if endpoint.throttled {
                    Text("SLOW")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }

                if endpoint.status == .endpointError {
                    Text("SKIP")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.yellow)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func statusIcon(_ result: ThrottleAnalysis) -> String {
        switch result.overallStatus {
        case "Possible Throttling":
            return "exclamationmark.triangle.fill"
        case "No Throttling":
            return "checkmark.shield.fill"
        case "Inconclusive":
            return "questionmark.circle.fill"
        default:
            return "xmark.circle.fill"
        }
    }

    private func statusColor(_ colorName: String) -> Color {
        switch colorName {
        case "green": return AppColors.green
        case "yellow": return AppColors.yellow
        case "orange": return Color.orange
        case "red": return AppColors.red
        default: return .gray
        }
    }

    private func confidenceColor(_ confidence: ThrottleAnalysis.Confidence) -> Color {
        switch confidence {
        case .high: return AppColors.green
        case .medium: return AppColors.yellow
        case .low: return Color.orange
        case .inconclusive: return .gray
        case .skipped: return AppColors.accent
        }
    }
}

// MARK: - ViewModel

@MainActor
class ThrottleDetectionViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var currentTest = ""
    @Published var result: ThrottleAnalysis?

    var hasResult: Bool { result != nil }

    func runTest() async {
        isRunning = true
        progress = 0
        currentTest = "Starting..."

        result = await ThrottleDetectionService.shared.detectThrottling { [weak self] progress, status in
            Task { @MainActor in
                self?.progress = progress
                self?.currentTest = status
            }
        }

        isRunning = false
    }
}

// MARK: - Preview

struct ThrottleDetectionView_Previews: PreviewProvider {
    static var previews: some View {
        ThrottleDetectionView()
    }
}
