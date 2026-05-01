//
//  NetworkSecurityAuditView.swift
//  NetoSensei
//
//  Network Security Audit View
//  Performs honest, real security checks on your network connection
//

import SwiftUI
import UIKit

struct NetworkSecurityAuditView: View {
    @StateObject private var vm = NetworkSecurityAuditViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // Overall Rating Card
                        if let result = vm.result {
                            overallRatingCard(result)
                        }

                        // What This Checks Section
                        if vm.result == nil && !vm.isScanning {
                            whatThisChecksCard
                        }

                        // Individual Checks
                        if let result = vm.result {
                            checksSection(result)
                        }

                        // Summary & Recommendations
                        if let result = vm.result {
                            summaryCard(result)
                        }
                    }
                    .padding()
                }

                if vm.isScanning {
                    LoadingOverlay(message: vm.currentProgress)
                }
            }
            .navigationTitle("Network Security Audit")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await vm.runAudit()
                        }
                    }) {
                        Image(systemName: vm.result == nil ? "play.fill" : "arrow.clockwise")
                    }
                    .disabled(vm.isScanning)
                }
            }
            // FIXED: Removed auto-run to prevent freeze
            // User must tap "Start Audit" button to run
            // .onAppear {
            //     if vm.result == nil {
            //         Task {
            //             await vm.runAudit()
            //         }
            //     }
            // }
        }
    }

    // MARK: - Overall Rating Card

    private func overallRatingCard(_ result: SecurityAuditResult) -> some View {
        CardView {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: result.overallRating.icon)
                        .font(.system(size: 50))
                        .foregroundColor(ratingColor(result.overallRating))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.overallRating.rawValue)
                            .font(.title2.bold())
                            .foregroundColor(ratingColor(result.overallRating))

                        Text(result.summary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                // Stats row
                HStack(spacing: 20) {
                    AuditStatBadge(value: result.passedCount, label: "Passed", color: .green)
                    AuditStatBadge(value: result.warningCount, label: "Warnings", color: .yellow)
                    AuditStatBadge(value: result.failedCount, label: "Issues", color: .red)
                }
            }
        }
    }

    // MARK: - What This Checks Card

    private var whatThisChecksCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("What This Audit Checks")
                    .font(.headline)

                Divider()

                ForEach(auditExplanations, id: \.title) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.icon)
                            .foregroundColor(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.bold())
                            Text(item.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var auditExplanations: [(icon: String, title: String, description: String)] {
        [
            ("network", "DNS Integrity", "Verifies DNS servers return correct IP addresses and aren't being hijacked."),
            ("lock.shield", "TLS Certificates", "Checks that HTTPS certificates are valid and from trusted issuers."),
            ("wifi.exclamationmark", "Captive Portal", "Detects if your connection is being intercepted by a login gateway."),
            ("arrow.triangle.branch", "Proxy Configuration", "Checks if a proxy is configured that could monitor your traffic."),
            ("lock", "HTTPS Enforcement", "Verifies that secure HTTPS connections work properly."),
            ("wifi", "Network Security", "Identifies potentially insecure public or open networks.")
        ]
    }

    // MARK: - Checks Section

    private func checksSection(_ result: SecurityAuditResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Security Checks")
                .font(.headline)
                .padding(.leading, 4)

            ForEach(result.checks) { check in
                SecurityCheckCard(check: check)
            }
        }
    }

    // MARK: - Summary Card

    private func summaryCard(_ result: SecurityAuditResult) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("About This Audit")
                        .font(.headline)
                }

                Divider()

                Text("This audit checks your network connection for security issues like DNS hijacking, certificate interception, captive portals, and proxy configurations.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("What it CAN detect:")
                    .font(.caption.bold())
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("  \u{2022} Captive portals and login gateways")
                    Text("  \u{2022} Proxy configurations that intercept traffic")
                    Text("  \u{2022} TLS/HTTPS certificate issues")
                    Text("  \u{2022} DNS hijacking attempts")
                    Text("  \u{2022} Potentially insecure public networks")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Divider()

                Text("What it CANNOT do:")
                    .font(.caption.bold())

                Text("iOS apps cannot scan for device malware, monitor other apps, or access system files. For device security, keep iOS updated and only install apps from the App Store.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Audit completed: \(formattedTimestamp(result.timestamp))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Helpers

    private func ratingColor(_ rating: SecurityAuditResult.Rating) -> Color {
        switch rating {
        case .secure: return .green
        case .moderateRisk: return .yellow
        case .highRisk: return .red
        }
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct SecurityCheckCard: View {
    let check: SecurityCheck

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: check.status.systemImage)
                        .foregroundColor(statusColor)
                        .font(.title2)

                    Text(check.name)
                        .font(.subheadline.bold())

                    Spacer()

                    Text(check.status.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.2))
                        .foregroundColor(statusColor)
                        .cornerRadius(4)
                }

                Text(check.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let recommendation = check.recommendation {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)

                        Text(recommendation)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var statusColor: Color {
        switch check.status {
        case .passed: return .green
        case .warning: return .yellow
        case .failed: return .red
        case .unknown: return .gray
        }
    }
}

struct AuditStatBadge: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ViewModel

@MainActor
class NetworkSecurityAuditViewModel: ObservableObject {
    @Published var result: SecurityAuditResult?
    @Published var isScanning = false
    @Published var currentProgress = "Starting audit..."

    private let service = NetworkSecurityAuditService.shared

    func runAudit() async {
        isScanning = true
        currentProgress = "Starting security audit..."

        // Disable idle timer during scan
        UIApplication.shared.isIdleTimerDisabled = true

        result = await service.runFullAudit { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.currentProgress = progress
            }
        }

        isScanning = false

        // Haptic feedback based on result
        if let result = result {
            switch result.overallRating {
            case .secure:
                HapticFeedback.success()
            case .moderateRisk:
                HapticFeedback.warning()
            case .highRisk:
                HapticFeedback.error()
            }
        }

        // Re-enable idle timer
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

// MARK: - Preview

#Preview {
    NetworkSecurityAuditView()
}
