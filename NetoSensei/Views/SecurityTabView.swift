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
    @ObservedObject private var network = NetworkMonitorService.shared

    private enum Tool: Identifiable {
        case fullCheck, portScanner, deviceHistory, deviceAssistant, uniFi, verifyDNS, verifyIPv6, investigate
        var id: Self { self }
    }

    @State private var tool: Tool?

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if privacyService.privacyStatus != nil, !privacyIsCurrent {
                        stalePrivacyCard
                    }
                    securityActions
                    deviceTools
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
                    DeviceCountCard(onScanPorts: { tool = .portScanner })
                }
                .connectionBriefColumn()
            }
            .background(ConnectionBriefStyle.canvas)
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
            .sheet(item: $tool) { tool in
                switch tool {
                case .uniFi: UniFiClientsView()
                case .deviceAssistant: WiFiAssistantView(guide: .security)
                case .fullCheck: CombinedSecurityCheckSheet()
                case .portScanner:
                    NavigationView {
                        PortScanView()
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Done") { self.tool = nil }
                                }
                            }
                    }
                    .navigationViewStyle(.stack)
                case .deviceHistory: DeviceHistoryView()
                case .verifyDNS: PrivacyVerificationView(topic: .dns)
                case .verifyIPv6: PrivacyVerificationView(topic: .ipv6)
                case .investigate: ConnectionInvestigationView(topic: .privacy)
                }
            }
            .task {
                // Check privacy on first appear (only if no cached result)
                if !privacyIsCurrent {
                    await privacyService.checkPrivacyShield()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var privacyIsCurrent: Bool {
        privacyService.privacyPath == ExitPath.lastPathChange
    }

    private var stalePrivacyCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your connection changed").font(.headline)
                Text("Refresh to see privacy results for the current route.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Refresh privacy checks") {
                    Task { await privacyService.checkPrivacyShield() }
                }
                .buttonStyle(.bordered)
                .disabled(privacyService.isCheckingPrivacy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Section 1: Privacy Shield

    private var privacyShieldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy checks")
                .font(.headline)
                .padding(.leading, 4)

            CardView {
                VStack(spacing: 16) {
                    // Overall status with shield icon
                    Group {
                        if let status = privacyService.privacyStatus, privacyIsCurrent {
                            VStack(spacing: 16) {
                                overallShieldStatus(status.overallStatus)

                                Divider()

                                // Individual checks
                                VStack(spacing: 12) {
                                    privacyCheckRow(status.vpnStatus, term: "VPN")
                                    privacyCheckRow(status.dnsPrivacy, term: "DNS")
                                    verificationButton(.dns, location: "row")
                                    privacyCheckRow(status.ipHidden, term: "IP Address")
                                    privacyCheckRow(status.webRTCLeak, term: "WebRTC")
                                    privacyCheckRow(status.httpsIntegrity, term: "HTTPS")
                                    // FIX (Sec Issue 2): 6th row — IPv6 leak.
                                    privacyCheckRow(status.ipv6Leak, term: "IPv6")
                                    verificationButton(.ipv6, location: "row")
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

    private func verificationButton(_ topic: PrivacyVerification, location: String) -> some View {
        Button(topic.title) { tool = topic == .dns ? .verifyDNS : .verifyIPv6 }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.leading, location == "row" ? 32 : 0)
            .accessibilityIdentifier("privacy.\(location).\(topic.rawValue)")
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
            Text("Public network details")
                .font(.headline)
                .padding(.leading, 4)

            CardView {
                Group {
                    if let exposure = privacyService.exposureInfo, privacyIsCurrent {
                        VStack(spacing: 12) {
                            exposureRow(
                                icon: "globe",
                                title: "Your visible IP",
                                value: exposure.publicIP ?? "Unavailable",
                                detail: "Observed public egress; subscriber identity and VPN coverage unverified",
                                isWarning: false
                            )

                            Divider()

                            exposureRow(
                                icon: "mappin",
                                title: "Your visible location",
                                value: exposure.visibleLocation ?? "Unknown",
                                detail: exposure.locationDetail,
                                isWarning: false
                            )

                            Divider()

                            exposureRow(
                                icon: "building.2",
                                title: "Your visible ISP",
                                value: exposure.visibleISP ?? "Unknown",
                                detail: "Organization reported by the IP metadata provider",
                                isWarning: false
                            )

                            Divider()

                            exposureRow(
                                icon: "server.rack",
                                title: "IP type",
                                value: exposure.ipType,
                                detail: exposure.ipType.contains("Data Center")
                                    ? "Some websites may detect this as VPN"
                                    : "IP type could not be verified",
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

    private var securityActions: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Security check", systemImage: "checkmark.shield")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Check certificates, DNS and VPN observations, or go directly to a privacy check.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    tool = .fullCheck
                } label: {
                    Text("Check security and get next steps")
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                verificationButton(.dns, location: "shortcut")
                verificationButton(.ipv6, location: "shortcut")
                Button("Investigate privacy or security", systemImage: "arrow.triangle.branch") {
                    tool = .investigate
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("investigation.openSecurity")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var deviceTools: some View {
        CardView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Network devices")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 6)
                Button {
                    tool = .deviceAssistant
                } label: {
                    BriefActionLabel(title: "Match and save device names", icon: "person.text.rectangle")
                }
                .accessibilityIdentifier("security.deviceAssistant")
                Divider()
                Button {
                    tool = .uniFi
                } label: {
                    BriefActionLabel(title: "View UniFi connected clients", icon: "wifi.router")
                }
                .accessibilityIdentifier("security.uniFi")
                Divider()
                Button {
                    tool = .deviceHistory
                } label: {
                    BriefActionLabel(title: "Device History", icon: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("security.deviceHistory")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            return "Several privacy checks are unverified. Review the evidence below; this is not a network safety certification."
        case .exposed:
            return "One or more checks could not complete successfully. Review the endpoint evidence; the cause may be a connection failure."
        }
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
