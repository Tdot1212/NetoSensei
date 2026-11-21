//
//  CombinedSecurityCheckView.swift
//  NetoSensei
//
//  "Run Full Security Check" — single button that fires WiFi Safety and VPN
//  Leak Test in parallel, merges them into one verdict screen.
//
//  Why this exists:
//   • WiFi Safety and VPN Leak Test answer overlapping questions ("is my
//     traffic protected?"). Two separate buttons meant users got partial
//     answers or never ran both.
//   • This wrapper is a thin orchestration layer — it does NOT reimplement
//     either check. It calls the existing PrivacyShieldService methods.
//   • The standalone sheets (WiFiSafetyResultSheet / VPNLeakTestResultSheet)
//     are kept untouched so we can repurpose them later if needed.
//

import SwiftUI

// MARK: - Combined Verdict

enum CombinedSecurityVerdict {
    case unknown
    case secure          // assessed checks passed
    case partial         // exactly one issue, or low/warning-level only
    case unsafe          // multiple issues OR a critical leak

    var displayText: String {
        switch self {
        case .unknown: return "Checks Incomplete"
        case .secure: return "Assessed Checks Passed"
        case .partial: return "Check needs attention"
        case .unsafe: return "Critical Check Finding"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: return "questionmark.shield"
        case .secure: return "checkmark.shield.fill"
        case .partial: return "exclamationmark.shield.fill"
        case .unsafe: return "xmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .secure: return .green
        case .partial: return .yellow
        case .unsafe: return .red
        }
    }

    var explanation: String {
        switch self {
        case .unknown: return "Some checks could not assess protection. Review the available evidence below."
        case .secure: return "The assessed checks found no issue. This is not a guarantee of network security."
        case .partial: return "At least one check needs review. Coverage and protection may be incomplete."
        case .unsafe: return "Follow the first step below, then rerun the checks."
        }
    }
}

struct CombinedSecurityResult {
    let verdict: CombinedSecurityVerdict
    let wifiSafety: WiFiSafetyResult?
    let vpnLeak: VPNLeakTestResult?
    /// IPv6 leak surfaced from SmartVPNDetector — same finding as the Privacy
    /// Shield "IPv6 Leak" row, included here so the combined verdict accounts
    /// for it consistently.
    let ipv6LeakDetected: Bool
    // The four new checks (built as separate self-contained services). Each
    // is optional so the sheet can render gracefully if a probe failed.
    let captivePortal: CaptivePortalResult?
    let dnsEncryption: DNSEncryptionResult?
    let killSwitch: KillSwitchAdvice?
    let certificateInspections: [CertificateInspection]
    /// Deduplicated, ordered actionable items pulled from both engines.
    let recommendations: [String]
    let timestamp: Date
}

// MARK: - View Model

@MainActor
final class CombinedSecurityCheckViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var result: CombinedSecurityResult?
    @Published var error: String?

    private let privacy = PrivacyShieldService.shared

    func runFullCheck(hosts: [String] = CertificateInspector.defaultHosts, refreshVPN: Bool = true) async {
        guard !isRunning else { return }
        isRunning = true
        result = nil
        error = nil
        let path = ExitPath.lastPathChange
        AppLoadTracker.shared.begin("securityCheck")         // Commit 7: cert fetches to blocked hosts are self-load
        defer { isRunning = false; AppLoadTracker.shared.end("securityCheck") }

        let vpnSnapshot = await SmartVPNDetector.shared.detectVPN(forceRefresh: refreshVPN)
        async let leakTask = privacy.runVPNLeakTest(prefetchedVPNResult: vpnSnapshot)
        async let captiveTask = CaptivePortalDetector.shared.detectCaptivePortal(
            vpnLikelyActive: vpnSnapshot.vpnState.isLikelyOn
        )
        async let dnsEncTask = DNSEncryptionChecker.shared.checkDNSEncryption()
        async let certTask = CertificateInspector.shared.inspectCertificates(hosts: hosts)

        let captive = await captiveTask
        async let wifiTask = privacy.checkWiFiSafety(portal: captive, vpn: vpnSnapshot)
        let leak = await leakTask
        let wifi = await wifiTask
        let dnsEnc = await dnsEncTask
        let certs = await certTask

        // Kill-switch advisor is synchronous — no point in awaiting.
        let killSwitch = KillSwitchAdvisor.shared.checkKillSwitchGuidance()

        // IPv6 leak signal comes from SmartVPNDetector method results — same
        // signal the Privacy Shield "IPv6 Leak" row uses. Including it here
        // keeps the verdict consistent with the rest of the Security tab.
        let ipv6Leak = false // No end-to-end IPv6 bypass probe was completed.

        let verdict = Self.computeVerdict(
            wifi: wifi, leak: leak, ipv6Leak: ipv6Leak,
            captive: captive, certs: certs
        )
        let recs = Self.recommendedSteps(
            leak: leak, captive: captive, certs: certs, vpnLikelyActive: vpnSnapshot.vpnState.isLikelyOn
        )

        guard !Task.isCancelled else { return }
        guard path == ExitPath.lastPathChange else {
            error = "The connection changed. Run the security check again."
            return
        }

        result = CombinedSecurityResult(
            verdict: verdict,
            wifiSafety: wifi,
            vpnLeak: leak,
            ipv6LeakDetected: ipv6Leak,
            captivePortal: captive,
            dnsEncryption: dnsEnc,
            killSwitch: killSwitch,
            certificateInspections: certs,
            recommendations: recs,
            timestamp: Date()
        )
    }

    // MARK: - Verdict & Recommendations

    nonisolated static func computeVerdict(
        wifi: WiFiSafetyResult?,
        leak: VPNLeakTestResult?,
        ipv6Leak: Bool,
        captive: CaptivePortalResult?,
        certs: [CertificateInspection]
    ) -> CombinedSecurityVerdict {
        // Critical signals first.
        let leakCritical = leak?.overallVerdict == .majorLeaks
        let wifiUnsafe = wifi?.overallStatus == .unsafe
        // Cert inspector .critical means trust-evaluation failed for a reason
        // OTHER than the user's own proxy CA — that's a real concern.
        let certCritical = certs.contains { $0.severity == .critical }
        if leakCritical || wifiUnsafe || certCritical {
            return .unsafe
        }

        // Count moderate issues across all surfaces.
        var issueCount = 0
        if leak?.overallVerdict == .minorLeaks { issueCount += 1 }
        if ipv6Leak { issueCount += 1 }
        // A confirmed captive portal blocks VPN setup, which downstreams to
        // every other check. Count it as one moderate issue. Inconclusive /
        // probe-failed states don't count.
        if captive?.verdict == .portalDetected { issueCount += 1 }
        // Certificate inspector .warning (unknown issuer) counts as one
        // moderate issue total, no matter how many hosts trip it — the user
        // sees the per-host detail in the section.
        if certs.contains(where: { $0.severity == .warning }) { issueCount += 1 }
        // Proxy MITM (.info severity) is NOT an issue — it's expected when
        // the user installed the proxy CA themselves.

        if issueCount == 0 {
            guard wifi != nil, leak?.overallVerdict == .noLeaks,
                  captive?.verdict == .noPortal, !certs.isEmpty,
                  !certs.contains(where: { $0.severity == .unavailable }) else { return .unknown }
            return .secure
        }
        return .partial // Multiple warnings do not establish an unsafe network.
    }

    nonisolated static func recommendedSteps(
        leak: VPNLeakTestResult?,
        captive: CaptivePortalResult?,
        certs: [CertificateInspection],
        vpnLikelyActive: Bool
    ) -> [String] {
        var steps: [String] = []
        if let cert = certs.first(where: { $0.severity == .critical }) {
            steps.append("Certificate trust failed for \(cert.hostname). Avoid entering credentials there. Check that Settings → General → Date & Time is set automatically, then run the check again on a trusted connection.")
        }
        if captive?.verdict == .portalDetected {
            steps.append("On a network you recognize, open Settings → Wi-Fi and tap the network to open its sign-in page. Confirm the page belongs to the venue, sign in, then run this check again.")
        }
        if let leak {
            steps += [leak.dnsLeak, leak.ipLeak, leak.webRTCLeak].compactMap {
                $0.isLeaking ? $0.solution : nil
            }
        }
        if vpnLikelyActive {
            steps.append("Open the VPN app you use. Confirm the expected server and review split tunneling, DNS protection and kill-switch settings there. The checks below show what this phone observed on its current route.")
        }
        if steps.isEmpty {
            steps.append("If a site showed a security warning, open it again on a trusted connection and rerun this check. If you are checking who has access to your network, open your router’s Connected Devices list and review unfamiliar entries.")
        }
        return steps
    }

}

// MARK: - Sheet

struct CombinedSecurityCheckSheet: View {
    @StateObject private var vm = CombinedSecurityCheckViewModel()
    @State private var followUp: WiFiRepairGuide?
    @State private var verification: PrivacyVerification?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if vm.isRunning {
                        runningView
                    } else if let result = vm.result {
                        verdictHeader(result)
                        recommendationsSection(result)
                        CardView {
                            VStack(alignment: .leading, spacing: 8) {
                                BriefSectionTitle(title: "Verify privacy settings")
                                Button(PrivacyVerification.dns.title) { verification = .dns }
                                Button(PrivacyVerification.ipv6.title) { verification = .ipv6 }
                            }
                            .buttonStyle(.bordered)
                        }
                        if result.certificateInspections.contains(where: { $0.severity == .critical }) {
                            Button("Retest a website security warning") { followUp = .certificate }
                                .buttonStyle(.bordered)
                        }
                        if result.vpnLeak?.overallVerdict == .unverified {
                            Button("Verify VPN privacy with your provider") { followUp = .vpnPrivacy }
                                .buttonStyle(.bordered)
                        }
                        wifiSection(result)
                        vpnSection(result)
                        // The four new self-contained checks. Each rendered
                        // only when the corresponding service produced a
                        // result — so a probe failure degrades silently.
                        if let captive = result.captivePortal {
                            captivePortalSection(captive)
                        }
                        if let dnsEnc = result.dnsEncryption {
                            dnsEncryptionSection(dnsEnc)
                        }
                        if !result.certificateInspections.isEmpty {
                            certificateSection(result.certificateInspections)
                        }
                        if let killSwitch = result.killSwitch {
                            killSwitchSection(killSwitch)
                        }

                    } else {
                        idleView
                    }
                }
                .padding()
            }
            .sheet(item: $followUp) { WiFiAssistantView(guide: $0) }
            .sheet(item: $verification) { PrivacyVerificationView(topic: $0) }
            .navigationTitle("Full Security Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
                if vm.result != nil && !vm.isRunning {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { Task { await vm.runFullCheck() } }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task {
                if vm.result == nil { await vm.runFullCheck() }
            }
        }
    }

    // MARK: - Subviews

    private var runningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Running WiFi safety and VPN leak checks…")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text("This usually takes about 20 seconds.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))
            Text("Tap retry to run the check")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 60)
    }

    private func verdictHeader(_ result: CombinedSecurityResult) -> some View {
        HStack(spacing: 16) {
            Image(systemName: result.verdict.systemImage)
                .font(.system(size: 44))
                .foregroundColor(result.verdict.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.verdict.displayText)
                    .font(.title3.bold())
                    .foregroundColor(result.verdict.color)
                Text(result.verdict.explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding()
        .background(result.verdict.color.opacity(0.1))
        .cornerRadius(12)
    }

    // ------- WiFi Safety Section -------

    private func wifiSection(_ result: CombinedSecurityResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WiFi Safety")
                .font(.headline)
                .padding(.leading, 4)

            if let wifi = result.wifiSafety {
                VStack(spacing: 0) {
                    ForEach(wifi.checks.indices, id: \.self) { i in
                        let check = wifi.checks[i]
                        HStack(spacing: 12) {
                            Image(systemName: wifiCheckIcon(check.status))
                                .foregroundColor(wifiCheckColor(check.status))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.title)
                                    .font(.subheadline.bold())
                                Text(check.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        if i < wifi.checks.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            } else {
                placeholderRow("WiFi safety check not available")
            }
        }
    }

    // ------- VPN Leak Section -------

    private func vpnSection(_ result: CombinedSecurityResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VPN Leaks")
                .font(.headline)
                .padding(.leading, 4)

            if let leak = result.vpnLeak {
                VStack(spacing: 0) {
                    leakRow(leak.dnsLeak)
                    Divider().padding(.leading, 44)
                    leakRow(leak.ipLeak)
                    Divider().padding(.leading, 44)
                    leakRow(leak.webRTCLeak)
                    // IPv6 leak surfaced from SmartVPNDetector (consistent
                    // with the Privacy Shield "IPv6 Leak" row).
                    Divider().padding(.leading, 44)
                    ipv6Row(detected: result.ipv6LeakDetected,
                            vpnConnected: leak.overallVerdict != .noVPN)
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            } else {
                placeholderRow("VPN leak test not available")
            }
        }
    }

    private func leakRow(_ check: VPNLeakTestResult.LeakCheck) -> some View {
        HStack(spacing: 12) {
            Image(systemName: leakIcon(check))
                .foregroundColor(leakColor(check))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.name)
                    .font(.subheadline.bold())
                Text(check.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private func ipv6Row(detected: Bool, vpnConnected: Bool) -> some View {
        let detail: String
        let color: Color
        let icon: String
        if !vpnConnected {
            detail = "Not applicable — no VPN active"
            color = .gray
            icon = "info.circle"
        } else if detected {
            detail = "Native ISP IPv6 routes outside the VPN tunnel — partial leak"
            color = .yellow
            icon = "exclamationmark.triangle.fill"
        } else {
            detail = "Unverified — no end-to-end IPv6 bypass test completed"
            color = .gray
            icon = "questionmark.circle"
        }
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("IPv6 Leak")
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    // ------- Captive Portal Section -------

    private func captivePortalSection(_ result: CaptivePortalResult) -> some View {
        let icon: String
        let color: Color
        let title: String
        switch result.verdict {
        case .noPortal:
            icon = "checkmark.circle.fill"; color = .green
            title = "Captive Portal: None detected"
        case .portalDetected:
            icon = "exclamationmark.triangle.fill"; color = .yellow
            title = "Captive Portal: Login required"
        case .inconclusiveVPNActive:
            icon = "info.circle"; color = .gray
            title = "Captive Portal: Check skipped (VPN active)"
        case .probeFailed:
            icon = "info.circle"; color = .gray
            title = "Captive Portal: Probe failed"
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Captive Portal").font(.headline).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: icon).foregroundColor(color).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline.bold())
                        Text(result.recommendation)
                            .font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let portal = result.portalURL {
                            Text(portal)
                                .font(.caption2.monospaced())
                                .foregroundColor(.blue)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // ------- DNS Encryption Section -------

    private func dnsEncryptionSection(_ result: DNSEncryptionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DNS Encryption").font(.headline).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 8) {
                dnsRow(label: "DoH (port 443)", reachable: result.dohReachable)
                Divider().padding(.leading, 32)
                dnsRow(label: "DoT (port 853)", reachable: result.dotReachable)
                Divider().padding(.leading, 32)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .frame(width: 22)
                    Text(result.recommendation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    private func dnsRow(label: String, reachable: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: reachable ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(reachable ? .green : .gray)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.bold())
                Text(reachable ? "Validated DNS reply over the tested encrypted transport" : "No validated reply; cause and configured transport unverified")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // ------- Certificate Inspection Section -------

    private func certificateSection(_ inspections: [CertificateInspection]) -> some View {
        let counts = CertificateInspection.counts(inspections)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Certificate Inspection").font(.headline)
                Spacer()
                Text("\(inspections.count) checked · \(counts.proxyLike) proxy-like issuers · \(counts.otherTrusted) other trusted · \(counts.untrusted) untrusted · \(counts.unavailable) unavailable")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(inspections.indices, id: \.self) { i in
                    let cert = inspections[i]
                    HStack(spacing: 12) {
                        Image(systemName: certIcon(cert.severity))
                            .foregroundColor(certColor(cert.severity))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cert.hostname).font(.subheadline.bold())
                            Text(cert.summary)
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Issuer: \(cert.realIssuer)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    if i < inspections.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    private func certIcon(_ severity: CertificateInspection.Severity) -> String {
        switch severity {
        case .info: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        case .unavailable: return "minus.circle"
        }
    }

    private func certColor(_ severity: CertificateInspection.Severity) -> Color {
        switch severity {
        case .info: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unavailable: return .yellow   // neutral: the network is not at fault
        }
    }

    // ------- Kill-Switch Advisor Section -------

    private func killSwitchSection(_ advice: KillSwitchAdvice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Kill-Switch Guidance").font(.headline)
                Spacer()
                if let app = advice.detectedProxyApp {
                    Text(app)
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue).cornerRadius(4)
                }
            }
            .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text(advice.guidance)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text("Manual test")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                ForEach(Array(advice.manualTestSteps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(i + 1).")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(step)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .font(.caption2)
                    Text(advice.disclaimer)
                        .font(.caption2)
                        .italic()
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // ------- Recommendations Section -------

    private func recommendationsSection(_ result: CombinedSecurityResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What to do next")
                .font(.headline)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(result.recommendations.enumerated()), id: \.offset) { _, rec in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundColor(.yellow)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(rec)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    private func placeholderRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
    }

    // MARK: - Icon/color helpers

    private func wifiCheckIcon(_ status: WiFiSafetyResult.SafetyCheck.CheckStatus) -> String {
        switch status {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func wifiCheckColor(_ status: WiFiSafetyResult.SafetyCheck.CheckStatus) -> Color {
        switch status {
        case .passed: return .green
        case .warning: return .yellow
        case .failed: return .red
        }
    }

    private func leakIcon(_ check: VPNLeakTestResult.LeakCheck) -> String {
        switch check.severity {
        case .safe: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }

    private func leakColor(_ check: VPNLeakTestResult.LeakCheck) -> Color {
        switch check.severity {
        case .safe: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}
