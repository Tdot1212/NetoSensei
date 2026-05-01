//
//  DNSAnalyzerView.swift
//  NetoSensei
//
//  DNS security & privacy analysis UI — shows DNS provider,
//  encryption status, leak test, latency, and recommendations.
//

import SwiftUI

struct DNSAnalyzerView: View {
    @StateObject private var analyzer = DNSAnalyzer.shared

    private var vpnActive: Bool {
        SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                actionButton

                if analyzer.isAnalyzing {
                    progressSection
                }

                if let result = analyzer.result, !analyzer.isAnalyzing {
                    resultsSection(result)
                }

                if analyzer.result == nil && !analyzer.isAnalyzing {
                    explanationCard
                }
            }
            .padding()
        }
        .refreshable {
            _ = await analyzer.runFullAnalysis()
        }
        .navigationTitle("DNS Analyzer")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("DNS Analysis")
                    .font(.headline)
                Text("Check your DNS security & privacy")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if vpnActive {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .font(.caption)
                    Text("VPN")
                        .font(.caption.bold())
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button(action: { Task { await analyzer.runFullAnalysis() } }) {
            HStack {
                if analyzer.isAnalyzing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 20, height: 20)
                    Text("Analyzing...")
                } else {
                    Image(systemName: "magnifyingglass")
                    Text(analyzer.result != nil ? "Run Again" : "Analyze DNS")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(analyzer.isAnalyzing ? Color.gray : Color.blue)
            .cornerRadius(12)
        }
        .disabled(analyzer.isAnalyzing)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: analyzer.progress)
                .progressViewStyle(.linear)

            Text(analyzer.currentStep)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Results

    private func resultsSection(_ result: DNSAnalysisResult) -> some View {
        // FIX (Phase 6.1): "Detected DNS Servers" and "Resolution Speed" removed.
        // Their per-server "1ms" numbers were measuring local UDP socket setup,
        // not server RTT, so they disagreed with DNS Benchmark and confused
        // users. DNS Analyzer now focuses on privacy/security; performance
        // comparisons live in DNS Benchmark.
        VStack(alignment: .leading, spacing: 16) {
            securityRatingCard(result)

            if !result.systemDNS.isEmpty {
                dnsServersCard(title: "Current Resolver", servers: result.systemDNS)
            }

            encryptionCard(result)

            if vpnActive {
                leakTestCard(result)
            }

            recommendationsCard(result)
        }
    }

    // MARK: - Security Rating

    private func securityRatingCard(_ result: DNSAnalysisResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("DNS Security")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(result.securityRating.rawValue)
                    .font(.title.bold())
                    .foregroundColor(ratingColor(result.securityRating))
            }

            Spacer()

            Image(systemName: result.securityRating.icon)
                .font(.system(size: 40))
                .foregroundColor(ratingColor(result.securityRating))
        }
        .padding()
        .background(ratingColor(result.securityRating).opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - DNS Servers Card

    private func dnsServersCard(title: String, servers: [DNSServerInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
                    DNSAnalyzerServerRow(server: server)

                    if index < servers.count - 1 {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Encryption Card

    private func encryptionCard(_ result: DNSAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Encryption")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                Image(systemName: result.isEncryptedDNS ? "lock.fill" : "lock.open")
                    .foregroundColor(result.isEncryptedDNS ? .green : .orange)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.isEncryptedDNS ? "Encrypted DNS Active" : "Unencrypted DNS")
                        .font(.subheadline.bold())

                    if let type = result.encryptedDNSType {
                        Text(type.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if !result.isEncryptedDNS {
                        Text("DNS queries are visible to your network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Leak Test Card

    private func leakTestCard(_ result: DNSAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DNS Leak Test")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: result.hasLeak ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(result.hasLeak ? .red : .green)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.hasLeak ? "DNS Leak Detected!" : "No DNS Leaks")
                            .font(.subheadline.bold())
                            .foregroundColor(result.hasLeak ? .red : .green)

                        Text(result.hasLeak
                            ? "Some DNS queries are bypassing your VPN"
                            : "All DNS queries are going through VPN")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                if !result.leakTestResults.isEmpty {
                    Divider()

                    ForEach(result.leakTestResults) { leak in
                        HStack {
                            Circle()
                                .fill(leak.isLeak ? Color.red : Color.green)
                                .frame(width: 8, height: 8)

                            Text(leak.provider.rawValue)
                                .font(.caption)

                            Spacer()

                            Text(leak.respondingIP)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)

                            if leak.isLeak {
                                Text("LEAK")
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .cornerRadius(3)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(result.hasLeak ? Color.red.opacity(0.1) : Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // FIX (Phase 6.1): "Resolution Speed" card removed. The number it displayed
    // came from getaddrinfo through the system resolver, which goes through
    // proxy/VPN local fake DNS (~1ms). Real DNS performance is in DNS Benchmark.

    // MARK: - Recommendations

    private func recommendationsCard(_ result: DNSAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 12) {
                if !result.isEncryptedDNS {
                    DNSAnalyzerRecommendation(
                        icon: "lock.shield",
                        title: "Enable Encrypted DNS",
                        description: "Use DNS over HTTPS in iOS Settings > Wi-Fi > Configure DNS",
                        color: .red
                    )
                }

                if result.hasLeak {
                    DNSAnalyzerRecommendation(
                        icon: "shield.slash",
                        title: "Fix DNS Leak",
                        description: "Configure your VPN to use its own DNS servers",
                        color: .red
                    )
                }

                // FIX (Phase 6.1): use systemDNS now that detectedDNS is gone.
                if !result.systemDNS.contains(where: { $0.provider.isPrivacyFocused })
                    && !result.isEncryptedDNS
                {
                    DNSAnalyzerRecommendation(
                        icon: "hand.raised",
                        title: "Consider Privacy DNS",
                        description: "Try Cloudflare (1.1.1.1) or Quad9 (9.9.9.9) for better privacy",
                        color: .orange
                    )
                }

                if result.securityRating == .excellent {
                    DNSAnalyzerRecommendation(
                        icon: "checkmark.seal",
                        title: "Great Setup!",
                        description: "Your DNS configuration is secure and private",
                        color: .green
                    )
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Explanation Card

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("What is DNS?")
                    .font(.subheadline.bold())
            }

            Text("DNS (Domain Name System) translates website names into IP addresses. Your DNS queries reveal every site you visit to your DNS provider.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                DNSAnalyzerFeatureRow(icon: "server.rack", text: "Identify your DNS provider")
                DNSAnalyzerFeatureRow(icon: "lock", text: "Check if DNS is encrypted")
                DNSAnalyzerFeatureRow(icon: "shield", text: "Detect DNS leaks when using VPN")
                DNSAnalyzerFeatureRow(icon: "speedometer", text: "Measure DNS resolution speed")
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func ratingColor(_ rating: DNSAnalysisResult.SecurityRating) -> Color {
        switch rating {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }

    // FIX (Phase 6.1): latencyColor / latencyDescription helpers removed —
    // the latency card they served was bogus (see comment on resultsSection).
}

// MARK: - DNS Server Row

private struct DNSAnalyzerServerRow: View {
    let server: DNSServerInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: server.provider.icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.subheadline.bold())
                Text(server.ipAddress)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }

            Spacer()

            if server.isEncrypted {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if let latency = server.latencyMs {
                Text("\(Int(latency))ms")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }

            if server.provider.isPrivacyFocused {
                Text("Privacy")
                    .font(.caption2.bold())
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Recommendation Row

private struct DNSAnalyzerRecommendation: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Feature Row

private struct DNSAnalyzerFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        DNSAnalyzerView()
    }
}
