import SwiftUI

struct EncryptedDNSRepairCard: View {
    @ObservedObject private var network = NetworkMonitorService.shared
    @ObservedObject private var detector = SmartVPNDetector.shared

    @State private var preflight: (path: Date, replied: Bool)?
    @State private var operation: Task<Void, Never>?

    private let profileGuide = URL(string: "https://docs.quad9.net/Setup_Guides/iOS/iOS_14_and_later_%28Encrypted%29/")!
    private let resolverCheck = URL(string: "https://on.quad9.net")!

    private var vpnDetected: Bool {
        if let result = detector.detectionResult, !result.isStaleData, result.timestamp >= ExitPath.lastPathChange {
            return result.vpnState.isLikelyOn
        }
        return network.currentStatus.vpn.vpnState.isLikelyOn
    }

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                BriefSectionTitle(title: "Set up encrypted DNS")
                if vpnDetected {
                    Text("Your VPN may choose its own DNS. Open your VPN app, enable the provider’s DNS protection if available, then reconnect and use its resolver check.")
                        .font(.subheadline)
                        .accessibilityIdentifier("privacy.repair.vpn")
                } else {
                    Text("For connections without a VPN or iCloud Private Relay, check whether Quad9 responds here before changing your DNS.")
                        .font(.subheadline)
                    if operation != nil {
                        ProgressView("Checking Quad9 on this connection…")
                    } else if let preflight, preflight.path == ExitPath.lastPathChange, preflight.replied {
                        Text("Quad9 answered. In Safari, choose the HTTPS (.9) profile. Then open Settings → Profile Downloaded → Install.")
                            .font(.subheadline)
                        Link(destination: profileGuide) {
                            Label("Get Quad9’s encrypted DNS profile", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("privacy.repair.profile")
                    } else {
                        if let preflight, preflight.path == ExitPath.lastPathChange {
                            Text("Quad9 didn’t answer this check. Keep your existing DNS and retry from a trusted connection.")
                                .font(.subheadline)
                                .accessibilityIdentifier("privacy.repair.unreachable")
                        }
                        Button("Check Quad9 before installing", action: checkQuad9)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityIdentifier("privacy.repair.preflight")
                    }
                    Link("Check whether Safari uses Quad9", destination: resolverCheck)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("privacy.repair.check")
                    Text("The check confirms Quad9 for that browser request. To undo the change, remove the Quad9 profile in Settings → General → VPN & Device Management.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { operation?.cancel() }
    }

    private func checkQuad9() {
        let path = ExitPath.lastPathChange
        operation = Task { @MainActor in
            defer { operation = nil }
            let reply = await DNSEncryptionChecker.shared.probeQuad9DoH()
            guard !Task.isCancelled, path == ExitPath.lastPathChange else { return }
            preflight = (path, reply)
        }
    }
}
