//
//  IntelligentDiagnosticCard.swift
//  NetoSensei
//
//  Intelligent diagnostic results with beginner-friendly explanations
//

import SwiftUI

struct IntelligentDiagnosticCard: View {
    let analysis: RootCauseAnalyzer.Analysis
    @State private var showExpertMode = false
    @State private var isVisible = false
    let onAutoFix: () -> Void

    var body: some View {
        VStack(spacing: UIConstants.spacingL) {
            // Health Score Circle
            healthScoreView
                .scaleIn(delay: 0)

            // Problem Summary
            problemSummaryCard
                .slideInFromBottom(delay: 0.1)

            // Beginner/Expert Toggle
            modeToggle
                .slideInFromBottom(delay: 0.2)

            // Explanation Card
            explanationCard
                .slideInFromBottom(delay: 0.3)

            // Auto-Fix Button
            if analysis.autoFixAvailable {
                autoFixButton
                    .bounceIn(delay: 0.4)
            }
        }
        .onAppear {
            // Haptic feedback based on health score
            HapticManager.shared.diagnosticCompleted(healthScore: analysis.healthScore)
        }
    }

    // MARK: - Health Score

    private var healthScoreView: some View {
        VStack(spacing: UIConstants.spacingS) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                    .frame(width: 120, height: 120)

                // Progress circle
                Circle()
                    .trim(from: 0, to: CGFloat(analysis.healthScore) / 100)
                    .stroke(healthScoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(AnimationConstants.progressComplete, value: analysis.healthScore)

                // Score text
                VStack(spacing: 2) {
                    Text("\(analysis.healthScore)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(healthScoreColor)

                    Text("Health")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Network health score")
            .accessibilityValue("\(analysis.healthScore) out of 100, \(healthScoreDescription)")

            Text(healthScoreDescription)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var healthScoreColor: Color {
        if analysis.healthScore >= 80 { return AppColors.green }
        if analysis.healthScore >= 60 { return AppColors.yellow }
        if analysis.healthScore >= 40 { return Color.orange }
        return AppColors.red
    }

    private var healthScoreDescription: String {
        if analysis.healthScore >= 90 { return "Excellent" }
        if analysis.healthScore >= 75 { return "Good" }
        if analysis.healthScore >= 60 { return "Fair" }
        if analysis.healthScore >= 40 { return "Poor" }
        return "Critical"
    }

    // MARK: - Problem Summary

    private var problemSummaryCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: problemIcon)
                        .font(.title2)
                        .foregroundColor(severityColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(analysis.primaryProblem.rawValue)
                            .font(.headline)
                            .foregroundColor(AppColors.textPrimary)

                        Text(severityText)
                            .font(.caption)
                            .foregroundColor(severityColor)
                    }

                    Spacer()
                }

                if !analysis.contributingFactors.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                        Text("Contributing Factors:")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)

                        ForEach(analysis.contributingFactors, id: \.rawValue) { factor in
                            HStack(spacing: UIConstants.spacingS) {
                                StatusDot(color: AppColors.yellow, size: 6)
                                Text(factor.rawValue)
                                    .font(.caption)
                                    .foregroundColor(AppColors.textPrimary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var problemIcon: String {
        switch analysis.severity {
        case .none: return "checkmark.circle.fill"
        case .minor: return "info.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .severe: return "xmark.octagon.fill"
        case .critical: return "xmark.circle.fill"
        }
    }

    private var severityColor: Color {
        switch analysis.severity {
        case .none: return AppColors.green
        case .minor: return .blue
        case .moderate: return AppColors.yellow
        case .severe: return Color.orange
        case .critical: return AppColors.red
        }
    }

    private var severityText: String {
        switch analysis.severity {
        case .none: return "All Good"
        case .minor: return "Minor Issue"
        case .moderate: return "Moderate Impact"
        case .severe: return "Severe Problem"
        case .critical: return "Critical Issue"
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack {
            Spacer()

            Button(action: {
                HapticManager.shared.toggleSwitched()
                withAnimation(AnimationConstants.spring) {
                    showExpertMode.toggle()
                }
            }) {
                HStack(spacing: UIConstants.spacingS) {
                    Image(systemName: showExpertMode ? "graduationcap.fill" : "person.fill")
                        .font(.caption)

                    Text(showExpertMode ? "Expert Mode" : "Beginner Mode")
                        .font(.caption.bold())
                }
                .foregroundColor(showExpertMode ? AppColors.accent : AppColors.textSecondary)
                .padding(.horizontal, UIConstants.spacingM)
                .padding(.vertical, UIConstants.spacingS)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.cornerRadiusS)
                        .fill(showExpertMode ? AppColors.accent.opacity(0.1) : Color.gray.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showExpertMode ? "Switch to beginner mode" : "Switch to expert mode")
            .accessibilityHint(showExpertMode ? "Shows simplified explanations" : "Shows technical details")

            Spacer()
        }
    }

    // MARK: - Explanation Card

    private var explanationCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                // What's Wrong
                sectionView(
                    icon: "exclamationmark.bubble.fill",
                    title: "What's Wrong",
                    content: showExpertMode ? analysis.expertExplanation : analysis.beginnerExplanation
                )

                Divider()

                // Why It Matters
                sectionView(
                    icon: "lightbulb.fill",
                    title: "Why It Matters",
                    content: analysis.whyItMatters
                )

                Divider()

                // What To Do
                sectionView(
                    icon: "wrench.and.screwdriver.fill",
                    title: "What To Do",
                    content: analysis.whatToDoNext
                )
            }
        }
    }

    private func sectionView(icon: String, title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.spacingS) {
            HStack(spacing: UIConstants.spacingS) {
                Image(systemName: icon)
                    .foregroundColor(AppColors.accent)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(AppColors.textPrimary)
            }

            Text(content)
                .font(.body)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Auto-Fix Button

    private var autoFixButton: some View {
        Button(action: {
            HapticManager.shared.autoFixTriggered()
            onAutoFix()
        }) {
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.headline)

                Text(autoFixButtonText)
                    .font(.headline)

                Spacer()

                Image(systemName: "chevron.right")
            }
            .foregroundColor(.white)
            .padding()
            .background(
                LinearGradient(
                    colors: [AppColors.accent, AppColors.accent.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(UIConstants.cornerRadiusM)
        }
        .buttonStyle(.plain)
        .shadow(color: AppColors.accent.opacity(0.3), radius: 10, x: 0, y: 5)
        .accessibilityLabel(autoFixButtonText)
        .accessibilityHint("Opens a guide to fix this network issue")
    }

    private var autoFixButtonText: String {
        guard let action = analysis.autoFixAction else { return "Fix Now" }

        switch action {
        case .restartRouter:
            return "Restart Router"
        case .switchWifiChannel:
            return "Optimize WiFi Channel"
        case .moveCloserToRouter:
            return "Show WiFi Tips"
        case .enableVPN:
            return "Enable VPN"
        case .switchVPNRegion:
            return "Switch VPN Region"
        case .switchVPNProtocol:
            return "Optimize VPN Protocol"
        case .changeDNS:
            return "Switch to Fast DNS"
        case .optimizeVPNForStreaming:
            return "Optimize for Streaming"
        case .contactISP:
            return "Contact ISP"
        case .reconnectWifi:
            return "Reconnect WiFi"
        case .disableVPN:
            return "Disable VPN"
        case .none:
            return "Fix Now"
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack {
            IntelligentDiagnosticCard(
                analysis: RootCauseAnalyzer.Analysis(
                    primaryProblem: .ispCongestion,
                    severity: .moderate,
                    beginnerExplanation: "Your internet is slow today (683ms). Your internet provider's network is congested. This is NOT your WiFi or router.",
                    expertExplanation: "High last-mile latency detected (683ms). Symptom typical of ISP peak congestion or overloaded NAT/CGNAT.",
                    whyItMatters: "ISP congestion slows down: streaming quality, downloads, uploads, online gaming. Nothing you do locally will fix this.",
                    whatToDoNext: "Enable a VPN to bypass your ISP's slow routing. Or contact your ISP to report congestion.",
                    autoFixAvailable: true,
                    autoFixAction: .enableVPN,
                    contributingFactors: [.dnsSlow],
                    healthScore: 62
                ),
                onAutoFix: {}
            )
            .padding()
        }
    }
    .background(AppColors.background)
}
