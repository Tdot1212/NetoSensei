//
//  SecurityIntelligenceView.swift
//  NetoSensei
//
//  Security Intelligence Dashboard - 100% Real Security Analysis
//  Displays threats, warnings, and actionable recommendations
//

import SwiftUI

struct SecurityIntelligenceView: View {
    @Environment(\.dismiss) var dismiss
    @State private var report: SecurityIntelligenceReport?
    @State private var isScanning = false
    @State private var progress: Double = 0.0
    @State private var currentTask: String = ""

    var body: some View {
        NavigationView {
            ZStack {
                if isScanning {
                    scanningView
                } else if let report = report {
                    reportView(report: report)
                } else {
                    startView
                }
            }
            .navigationTitle("Security Intelligence")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if report != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: runScan) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Start View

    private var startView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 80))
                .foregroundStyle(.purple.gradient)

            // Title
            VStack(spacing: 12) {
                Text("Security Intelligence")
                    .font(.title.bold())

                Text("100% Real Security Analysis")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Description
            VStack(alignment: .leading, spacing: 12) {
                Text("NetoSensei will analyze:")
                    .font(.headline)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    securityFeature(icon: "network", text: "DNS Hijacking & Manipulation")
                    securityFeature(icon: "lock.shield", text: "DNS Encryption Status")
                    securityFeature(icon: "globe.badge.chevron.backward", text: "DNS Server Location & Safety")
                    securityFeature(icon: "eye.slash", text: "VPN Leaks & DNS Leaks")
                    securityFeature(icon: "exclamationmark.triangle", text: "Privacy Risks")
                }
                .padding(.horizontal)
            }
            .padding()
            .background(Color.purple.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)

            // Start Button
            Button(action: runScan) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Network Security Check")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    private func securityFeature(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.purple)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 70))
                .foregroundStyle(.purple.gradient)
                .symbolEffect(.pulse)

            VStack(spacing: 12) {
                Text("Scanning Network Security")
                    .font(.title2.bold())

                Text(currentTask)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(.purple)
                    .scaleEffect(x: 1, y: 2, anchor: .center)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }

    // MARK: - Report View

    private func reportView(report: SecurityIntelligenceReport) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overall Security Score
                overallScoreCard(report: report)

                // Critical Threats
                if report.hasCriticalThreats {
                    criticalThreatsSection(report: report)
                }

                // All Threats
                if !report.threats.isEmpty {
                    threatsSection(report: report)
                }

                // Warnings
                if !report.warnings.isEmpty {
                    warningsSection(report: report)
                }

                // Recommendations
                if !report.recommendations.isEmpty {
                    recommendationsSection(report: report)
                }

                // DNS Security Details
                dnsSecurityDetails(dnsStatus: report.dnsSecurityStatus)

                // Privacy Status Details
                privacyStatusDetails(privacyStatus: report.privacyStatus)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Overall Score Card

    private func overallScoreCard(report: SecurityIntelligenceReport) -> some View {
        VStack(spacing: 16) {
            Text(report.overallScore.emoji)
                .font(.system(size: 60))

            Text(report.userFriendlySummary)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if report.hasThreats {
                Text("\(report.threats.count) finding\(report.threats.count == 1 ? "" : "s") detected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("No security issues found")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }

            Text(report.timestamp, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            LinearGradient(
                colors: [report.overallScore.color.opacity(0.2), report.overallScore.color.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Critical Threats Section

    private func criticalThreatsSection(report: SecurityIntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Critical Findings")
                    .font(.headline)
                    .foregroundColor(.red)
            }
            .padding(.horizontal)

            ForEach(report.threats.filter { $0.severity == .critical }) { threat in
                threatCard(threat: threat, highlighted: true)
            }
        }
    }

    // MARK: - Threats Section

    private func threatsSection(report: SecurityIntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Findings")
                .font(.headline)
                .padding(.horizontal)

            ForEach(report.threats) { threat in
                threatCard(threat: threat, highlighted: false)
            }
        }
    }

    private func threatCard(threat: SecurityThreat, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(threat.severity.emoji)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(threat.title)
                        .font(.headline)
                        .foregroundColor(highlighted ? .red : .primary)

                    Text(threat.type.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(threat.severity.rawValue.uppercased())
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(threat.severity.color.opacity(0.2))
                    .foregroundColor(threat.severity.color)
                    .cornerRadius(4)
            }

            // Description
            Text(threat.description)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            // Technical Details (Collapsible)
            DisclosureGroup("Technical Details") {
                Text(threat.technicalDetails)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .font(.caption)

            // Actionable Steps
            if !threat.actionable.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("What You Can Do:")
                        .font(.caption.bold())

                    ForEach(threat.actionable, id: \.self) { action in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text(action)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding()
        .background(highlighted ? Color.red.opacity(0.1) : Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(highlighted ? Color.red : Color.clear, lineWidth: 2)
        )
        .padding(.horizontal)
    }

    // MARK: - Warnings Section

    private func warningsSection(report: SecurityIntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Warnings")
                .font(.headline)
                .padding(.horizontal)

            ForEach(report.warnings) { warning in
                warningCard(warning: warning)
            }
        }
    }

    private func warningCard(warning: SecurityWarning) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(warning.title)
                    .font(.subheadline.bold())
                Text(warning.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Recommendations Section

    private func recommendationsSection(report: SecurityIntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sensei Recommendations")
                .font(.headline)
                .padding(.horizontal)

            ForEach(report.recommendations) { rec in
                recommendationCard(rec: rec)
            }
        }
    }

    private func recommendationCard(rec: SecurityRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.title)
                        .font(.headline)

                    Text(rec.estimatedImpact)
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Spacer()

                Text(rec.priority.rawValue.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(priorityColor(rec.priority).opacity(0.2))
                    .foregroundColor(priorityColor(rec.priority))
                    .cornerRadius(4)
            }

            // Description
            Text(rec.description)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            // Actions
            if !rec.actions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Steps:")
                        .font(.caption.bold())

                    ForEach(Array(rec.actions.enumerated()), id: \.offset) { index, action in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption.bold())
                                .foregroundColor(.purple)
                            Text(action)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func priorityColor(_ priority: RecommendationPriority) -> Color {
        switch priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }

    // MARK: - DNS Security Details

    private func dnsSecurityDetails(dnsStatus: DNSSecurityStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DNS Security Details")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                detailRow(label: "Status", value: dnsStatus.statusText)
                detailRow(label: "DNS Server", value: dnsStatus.currentDNSServer)

                if let location = dnsStatus.dnsServerLocation {
                    detailRow(label: "Server Location", value: location)
                }

                detailRow(label: "Encrypted", value: dnsStatus.isEncrypted ? "Yes (\(dnsStatus.encryptionType?.rawValue ?? ""))" : "No")
                detailRow(label: "Security Score", value: "\(dnsStatus.securityScore)/100")
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Privacy Status Details

    private func privacyStatusDetails(privacyStatus: PrivacyStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy Status")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                detailRow(label: "Status", value: privacyStatus.statusText)
                detailRow(label: "VPN Active", value: privacyStatus.vpnActive ? "Yes" : "No")

                if privacyStatus.vpnActive {
                    detailRow(label: "VPN Leak", value: privacyStatus.vpnLeakDetected ? "⚠️ Detected" : "✅ None")
                    detailRow(label: "DNS Leak", value: privacyStatus.dnsLeakDetected ? "⚠️ Detected" : "✅ None")
                }

                if let location = privacyStatus.publicIPLocation {
                    detailRow(label: "Public IP Location", value: location)
                }

                detailRow(label: "Privacy Score", value: "\(privacyStatus.privacyScore)/100")
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Actions

    private func runScan() {
        Task {
            isScanning = true
            progress = 0.0

            let scanReport = await SecurityIntelligenceEngine.shared.runFullSecurityScan { prog, task in
                Task { @MainActor in
                    progress = prog
                    currentTask = task
                }
            }

            await MainActor.run {
                report = scanReport
                isScanning = false
            }
        }
    }
}

#Preview {
    SecurityIntelligenceView()
}
