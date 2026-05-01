//
//  SecurityTabView.swift
//  NetoSensei
//
//  Redesigned Security tab with 3 clear sections:
//  1. Privacy Shield (Am I Protected?)
//  2. Exposure Check (What Can Others See?)
//  3. Security Tools (On-demand tests)
//

import SwiftUI

struct SecurityTabView: View {
    @StateObject private var privacyService = PrivacyShieldService.shared
    @ObservedObject private var vpnDetector = SmartVPNDetector.shared
    @ObservedObject private var interpretationEngine = InterpretationEngine.shared

    // FIX: WiFi Safety + VPN Leak buttons replaced by a single
    // "Run Full Security Check" entry. Old standalone sheets are kept in the
    // codebase but no longer have an entry point on this tab.
    @State private var showingFullSecurityCheck = false
    @State private var showingPortScanner = false
    @State private var showingDeviceHistory = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Section 1: Privacy Shield
                    privacyShieldSection

                    // Section 2: Exposure Check
                    exposureCheckSection

                    // VPN Details (expandable, shown when VPN active)
                    VPNDetailsCard()

                    // WiFi Details (expandable, shown when WiFi connected)
                    WiFiDetailsCard()

                    // WiFi Network Comparison
                    WiFiComparisonCard()

                    // Device Count on Network — Port Scanner moved here as a
                    // secondary action ("Scan ports on these devices →")
                    // because port-scanning targets these LAN devices.
                    DeviceCountCard(onScanPorts: { showingPortScanner = true })

                    // Diagnosis Evidence (5-score system with evidence/confidence)
                    if let diagnosis = interpretationEngine.currentDiagnosis {
                        DiagnosisEvidenceCard(diagnosis: diagnosis)
                    }

                    // Section 3: Security Tools
                    securityToolsSection
                }
                .padding()
            }
            .navigationTitle("Network Security")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await privacyService.checkPrivacyShield()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(privacyService.isCheckingPrivacy)
                }
            }
            // Combined check sheet — replaces the two old standalone sheets.
            .sheet(isPresented: $showingFullSecurityCheck) {
                CombinedSecurityCheckSheet()
            }
            .sheet(isPresented: $showingPortScanner) {
                NavigationView {
                    PortScanView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showingPortScanner = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingDeviceHistory) {
                DeviceHistoryView()
            }
            .task {
                // Check privacy on first appear (only if no cached result)
                if privacyService.privacyStatus == nil {
                    await privacyService.checkPrivacyShield()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Section 1: Privacy Shield

    private var privacyShieldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Am I Protected?")
                .font(.headline)
                .padding(.leading, 4)

            CardView {
                VStack(spacing: 16) {
                    // Overall status with shield icon
                    Group {
                        if let status = privacyService.privacyStatus {
                            VStack(spacing: 16) {
                                overallShieldStatus(status.overallStatus)

                                Divider()

                                // Individual checks
                                VStack(spacing: 12) {
                                    privacyCheckRow(status.vpnStatus, term: "VPN")
                                    privacyCheckRow(status.dnsPrivacy, term: "DNS")
                                    privacyCheckRow(status.ipHidden, term: "IP Address")
                                    privacyCheckRow(status.webRTCLeak, term: "WebRTC")
                                    privacyCheckRow(status.httpsIntegrity, term: "HTTPS")
                                    // FIX (Sec Issue 2): 6th row — IPv6 leak.
                                    privacyCheckRow(status.ipv6Leak, term: "IPv6")
                                }

                                // FIX (Sec Issue 2): Recommendation block when
                                // IPv6 leak is the warning state.
                                if status.ipv6Leak.severity == .warning,
                                   let rec = status.ipv6Leak.recommendation {
                                    Divider()
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "wrench.and.screwdriver")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("How to fix")
                                                .font(.caption.bold())
                                                .foregroundColor(.secondary)
                                            Text(rec)
                                                .font(.caption)
                                                .foregroundColor(.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        } else if privacyService.isCheckingPrivacy {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Checking your privacy...")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        } else {
                            // Initial state
                            VStack(spacing: 12) {
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text("Tap refresh to check your privacy status")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    }
                }
            }
        }
    }

    private func overallShieldStatus(_ status: PrivacyShieldStatus.OverallStatus) -> some View {
        HStack(spacing: 16) {
            Image(systemName: status.systemImage)
                .font(.system(size: 40))
                .foregroundColor(shieldColor(status))

            VStack(alignment: .leading, spacing: 4) {
                Text(status.displayText)
                    .font(.title3.bold())
                    .foregroundColor(shieldColor(status))

                Text(shieldExplanation(status))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private func privacyCheckRow(_ check: PrivacyShieldStatus.CheckResult, term: String? = nil) -> some View {
        // FIX (Sec Issue 2): Tri-color icon driven by severity. Old binary
        // rendering would have shown the IPv6 warning as red ✗ — too harsh
        // — or had to be passed=true (lying about partial protection).
        let iconName: String = {
            switch check.severity {
            case .passed: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }()
        let iconColor: Color = {
            switch check.severity {
            case .passed: return .green
            case .warning: return .yellow
            case .failed: return .red
            }
        }()
        return HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                if let term = term {
                    TooltipText(text: check.title, term: term, font: .subheadline.bold())
                } else {
                    Text(check.title)
                        .font(.subheadline.bold())
                }
                Text(check.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    // MARK: - Section 2: Exposure Check

    private var exposureCheckSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What Others Can See")
                .font(.headline)
                .padding(.leading, 4)

            CardView {
                Group {
                    if let exposure = privacyService.exposureInfo {
                        VStack(spacing: 12) {
                            exposureRow(
                                icon: "globe",
                                title: "Your visible IP",
                                value: exposure.publicIP ?? "Hidden",
                                detail: exposure.isRealIP
                                    ? "This is your REAL IP address"
                                    : "This is your VPN server's IP",
                                isWarning: exposure.isRealIP
                            )

                            Divider()

                            exposureRow(
                                icon: "mappin",
                                title: "Your visible location",
                                value: exposure.visibleLocation ?? "Unknown",
                                detail: exposure.locationDetail,
                                isWarning: exposure.isRealIP
                            )

                            Divider()

                            exposureRow(
                                icon: "building.2",
                                title: "Your visible ISP",
                                value: exposure.visibleISP ?? "Unknown",
                                detail: exposure.isRealIP
                                    ? "Your real ISP is visible"
                                    : "Shows as VPN provider",
                                isWarning: exposure.isRealIP
                            )

                            Divider()

                            exposureRow(
                                icon: "server.rack",
                                title: "IP type",
                                value: exposure.ipType,
                                detail: exposure.ipType.contains("Data Center")
                                    ? "Some websites may detect this as VPN"
                                    : "Appears as a normal connection",
                                isWarning: false
                            )
                        }
                    } else {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Run a privacy check to see what's visible")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                }
            }
        }
    }

    private func exposureRow(icon: String, title: String, value: String, detail: String, isWarning: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isWarning ? .yellow : .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }

            Spacer()

            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }

    // MARK: - Section 3: Network Activity
    // Renamed from "Security Tools". The four old buttons have been
    // consolidated:
    //   • "Is This WiFi Safe?" + "VPN Leak Test"  →  single
    //     "Run Full Security Check" (CombinedSecurityCheckSheet)
    //   • "Port Scanner"  →  moved into the Devices on Network card as a
    //     secondary action.
    //   • "Device History"  →  unchanged, lives here under the renamed
    //     section.

    private var securityToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Activity")
                .font(.headline)
                .padding(.leading, 4)

            VStack(spacing: 12) {
                // Combined WiFi Safety + VPN Leak check
                SecurityToolButton(
                    icon: "shield.lefthalf.filled.badge.checkmark",
                    title: "Run Full Security Check",
                    subtitle: "WiFi safety + VPN leak detection",
                    duration: "~20s",
                    isLoading: privacyService.isCheckingWiFi || privacyService.isRunningLeakTest
                ) {
                    showingFullSecurityCheck = true
                }

                // Device History (passive viewer, not a test)
                SecurityToolButton(
                    icon: "desktopcomputer",
                    title: "Device History",
                    subtitle: "Track all devices seen on your network",
                    duration: "",
                    isLoading: false
                ) {
                    showingDeviceHistory = true
                }
            }
        }
    }

    // MARK: - Helpers

    private func shieldColor(_ status: PrivacyShieldStatus.OverallStatus) -> Color {
        switch status {
        case .protected: return .green
        case .partiallyProtected: return .yellow
        case .exposed: return .red
        }
    }

    private func shieldExplanation(_ status: PrivacyShieldStatus.OverallStatus) -> String {
        switch status {
        case .protected:
            return "All privacy checks passed"
        case .partiallyProtected:
            // FIX (Sec Issue 2): mention IPv6 leak by name when that's the
            // specific reason we degraded the verdict.
            if let ipv6 = privacyService.privacyStatus?.ipv6Leak,
               ipv6.severity == .warning {
                return "IPv6 leak detected — VPN protection is incomplete"
            }
            return "Some privacy measures are in place but improvements possible"
        case .exposed:
            return "Your online activity may be visible to others"
        }
    }
}

// MARK: - Security Tool Button

struct SecurityToolButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let duration: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(duration)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - WiFi Safety Result Sheet

struct WiFiSafetyResultSheet: View {
    let result: WiFiSafetyResult?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let result = result {
                    // Overall status
                    VStack(spacing: 12) {
                        Image(systemName: result.overallStatus.systemImage)
                            .font(.system(size: 60))
                            .foregroundColor(statusColor(result.overallStatus))

                        Text(result.overallStatus.displayText)
                            .font(.title.bold())
                            .foregroundColor(statusColor(result.overallStatus))

                        Text(statusExplanation(result.overallStatus))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()

                    // Individual checks
                    VStack(spacing: 0) {
                        ForEach(result.checks.indices, id: \.self) { index in
                            let check = result.checks[index]
                            HStack {
                                Image(systemName: checkStatusIcon(check.status))
                                    .foregroundColor(checkStatusColor(check.status))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(check.title)
                                        .font(.subheadline.bold())
                                    Text(check.detail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))

                            if index < result.checks.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Spacer()
                } else {
                    ProgressView("Checking WiFi safety...")
                }
            }
            .navigationTitle("WiFi Safety")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func statusColor(_ status: WiFiSafetyResult.SafetyStatus) -> Color {
        switch status {
        case .safe: return .green
        case .caution: return .yellow
        case .unsafe: return .red
        }
    }

    private func statusExplanation(_ status: WiFiSafetyResult.SafetyStatus) -> String {
        let vpnActive = SmartVPNDetector.shared.detectionResult?.vpnState.isLikelyOn ?? false

        switch status {
        case .safe:
            return "This network appears safe for general use"
        case .caution:
            return vpnActive
                ? "Some concerns detected — your VPN provides additional protection"
                : "Some concerns detected — consider using a VPN"
        case .unsafe:
            return "Significant security risks detected — avoid sensitive activities"
        }
    }

    private func checkStatusIcon(_ status: WiFiSafetyResult.SafetyCheck.CheckStatus) -> String {
        switch status {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func checkStatusColor(_ status: WiFiSafetyResult.SafetyCheck.CheckStatus) -> Color {
        switch status {
        case .passed: return .green
        case .warning: return .yellow
        case .failed: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    SecurityTabView()
}
