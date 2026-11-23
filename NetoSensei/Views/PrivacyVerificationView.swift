import Foundation
import Network
import SwiftUI

enum PrivacyVerification: String, Identifiable {
    case dns, ipv6

    var id: Self { self }
    var title: String { self == .dns ? "Verify DNS privacy" : "Verify IPv6 routing" }
    var testTitle: String { self == .dns ? "Test encrypted DNS" : "Measure public IPv6" }

    var steps: [String] {
        switch self {
        case .dns:
            return [
                "If you use a VPN, open its app and look for DNS, DNS leak protection, or automatic DNS. Use the provider’s recommended setting. If you use a separate DNS profile, check Settings → General → VPN & Device Management.",
                "Open your DNS or VPN provider’s verification page in the browser you use. Compare the resolver it reports with the one your provider says to expect. If you configured Cloudflare 1.1.1.1, use the Cloudflare check below and look for DoH or DoT when that is the mode you enabled.",
                "If you see an unexpected resolver, reconnect after changing the provider’s DNS setting. Repeat the same provider check on the same Wi-Fi. Ask the provider which resolver to expect if its instructions are unclear."
            ]
        case .ipv6:
            return [
                "With the VPN connected, run Measure public IPv6. Your VPN provider can tell you whether IPv6 is tunneled or blocked and what an expected result looks like.",
                "If your policy permits a comparison, use trusted Wi-Fi, pause sensitive activity, and record a sample with the VPN off. Reconnect the VPN and sample again from the same Wi-Fi. The same address in both samples is evidence that this request’s visible IPv6 did not change. Different addresses show a different observed exit.",
                "If the VPN-on address matches your direct address when you expect tunnel coverage, enable IPv6 protection or IPv6 blocking in the VPN app if offered. Reconnect, retest, and contact the provider if the address still matches. A timeout also needs a working direct IPv6 baseline and provider guidance to interpret."
            ]
        }
    }
}

enum PublicIPv6Probe {
    static let endpoint = URL(string: "https://api6.ipify.org")!

    static func parse(_ data: Data, status: Int, url: URL?) -> String? {
        guard status == 200, url?.scheme == "https", url?.host == endpoint.host,
              data.count <= 80,
              let address = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let ipv6 = IPv6Address(address), ipv6.rawValue.first.map({ $0 & 0xe0 == 0x20 }) == true
        else { return nil }
        return address
    }

    static func measure() async -> String? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 7
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return parse(data, status: http.statusCode, url: http.url)
    }
}

struct PrivacyVerificationView: View {
    let topic: PrivacyVerification
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var network = NetworkMonitorService.shared
    @State private var dns: DNSEncryptionResult?
    @State private var ipv6: String?
    @State private var previousIPv6: String?
    @State private var measuredPath: Date?
    @State private var measuredAt: Date?
    @State private var notice: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if topic == .dns { EncryptedDNSRepairCard() }
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            BriefSectionTitle(title: "What NetoSensei can check")
                            Text(topic == .dns
                                 ? "Send test queries over DNS over HTTPS and DNS over TLS. The result describes those queries. The provider check below helps confirm the resolver used by your browser or VPN."
                                 : "Ask ipify for the public IPv6 address it sees for one request from NetoSensei. Use a comparison to check whether the visible exit changes with the VPN.")
                                .font(.subheadline)
                            if operation != nil {
                                ProgressView("Checking the current connection…")
                            } else {
                                Button(topic.testTitle, action: test)
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("privacy.verification.run")
                            }
                            if let notice {
                                Text(notice).font(.subheadline)
                            }
                            if let measuredAt {
                                if measuredPath == ExitPath.lastPathChange {
                                    readings
                                    Text(measuredAt, style: .time)
                                        .font(.caption).foregroundStyle(.secondary)
                                } else if let ipv6, topic == .ipv6 {
                                    Text("Previous IPv6 sample: \(ipv6)")
                                        .font(.subheadline).textSelection(.enabled)
                                    Text("The connection changed. Keep this address for comparison and run a new sample.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                } else {
                                    Text("The connection changed. Run the check again for current results.")
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            BriefSectionTitle(title: "Verify or change your settings")
                            ForEach(Array(topic.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).").fontWeight(.semibold).accessibilityHidden(true)
                                    Text(step)
                                }
                                .font(.subheadline)
                            }
                            if topic == .dns, let url = URL(string: "https://1.1.1.1/help") {
                                Link("Open Cloudflare’s DNS check", destination: url)
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                }
                .connectionBriefColumn()
            }
            .background(ConnectionBriefStyle.canvas)
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onDisappear { operation?.cancel() }
        }
    }

    @ViewBuilder private var readings: some View {
        if let dns, topic == .dns {
            Text("DNS over HTTPS: \(dns.dohReachable ? "Validated reply" : "No validated reply")")
            Text("DNS over TLS: \(dns.dotReachable ? "Validated reply" : "No validated reply")")
        } else if topic == .ipv6 {
            if let ipv6 {
                Text("Observed public IPv6").font(.subheadline.weight(.semibold))
                Text(ipv6).font(.subheadline.monospaced()).textSelection(.enabled)
                if let previousIPv6 {
                    let same = IPv6Address(previousIPv6) == IPv6Address(ipv6)
                    Text("Previous IPv6 sample: \(previousIPv6)")
                        .font(.footnote.monospaced()).textSelection(.enabled)
                    Text(same ? "Both samples show the same visible address." : "The visible address changed between samples.")
                        .font(.subheadline)
                    Text("Interpret this comparison only if you sampled the same Wi-Fi with the VPN off and then on.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Text("No IPv6 sample. The endpoint may be unreachable, or IPv6 may be unavailable or blocked on this route.")
                    .font(.subheadline)
            }
        }
    }

    private func test() {
        notice = nil
        let path = ExitPath.lastPathChange
        operation = Task {
            defer { operation = nil }
            switch topic {
            case .dns:
                let value = await DNSEncryptionChecker.shared.checkDNSEncryption()
                guard acceptSample(path) else { return }
                dns = value
            case .ipv6:
                let value = await PublicIPv6Probe.measure()
                guard acceptSample(path) else { return }
                if measuredPath != nil, measuredPath != path, let ipv6 {
                    previousIPv6 = ipv6
                }
                ipv6 = value
            }
            measuredPath = path
            measuredAt = Date()
        }
    }

    private func acceptSample(_ path: Date) -> Bool {
        guard !Task.isCancelled else { return false }
        guard path == ExitPath.lastPathChange else {
            notice = "The connection changed during the test. Try again on the current connection."
            return false
        }
        return true
    }
}
