//
//  TLSAnalyzerView.swift
//  NetoSensei
//
//  TLS/Certificate analysis UI — host input, security rating,
//  TLS version, certificate chain, issues, and quick-test buttons.
//

import SwiftUI

struct TLSAnalyzerView: View {
    @StateObject private var analyzer = TLSAnalyzer.shared

    @State private var hostInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                hostInputSection
                quickTestSection

                if analyzer.isAnalyzing {
                    progressSection
                }

                if let result = analyzer.result, !analyzer.isAnalyzing {
                    resultsSection(result)
                }

                if !analyzer.recentResults.isEmpty && analyzer.result == nil && !analyzer.isAnalyzing {
                    recentResultsSection
                }

                if analyzer.result == nil && !analyzer.isAnalyzing && analyzer.recentResults.isEmpty {
                    explanationCard
                }
            }
            .padding()
        }
        .refreshable {
            if !hostInput.isEmpty {
                _ = await analyzer.analyzeHost(hostInput)
            }
        }
        .navigationTitle("TLS Analyzer")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("TLS/Certificate Analyzer")
                    .font(.headline)
                Text("Check connection security")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Host Input

    private var hostInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter Website")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.secondary)

                TextField("example.com", text: $hostInput)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)

                if !hostInput.isEmpty {
                    Button(action: { hostInput = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(10)

            Button(action: { Task { await analyzer.analyzeHost(hostInput) } }) {
                HStack {
                    if analyzer.isAnalyzing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                        Text("Analyzing...")
                    } else {
                        Image(systemName: "magnifyingglass")
                        Text("Analyze")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(analyzer.isAnalyzing || hostInput.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(analyzer.isAnalyzing || hostInput.isEmpty)
        }
    }

    // MARK: - Quick Test

    private var quickTestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Test")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(analyzer.commonTestSites.enumerated()), id: \.offset) { _, site in
                        Button(action: { Task { await analyzer.analyzeHost(site.0) } }) {
                            Text(site.1)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(20)
                        }
                        .disabled(analyzer.isAnalyzing)
                    }
                }
            }
        }
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

    private func resultsSection(_ result: TLSAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            securityRatingCard(result)
            tlsVersionCard(result)

            if !result.issues.isEmpty {
                issuesCard(result.issues)
            }

            if !result.certificateChain.isEmpty {
                certificateChainCard(result.certificateChain)
            }

            technicalDetailsCard(result)
        }
    }

    // MARK: - Security Rating

    private func securityRatingCard(_ result: TLSAnalysisResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.host)
                    .font(.headline)
                Text("Security Rating")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(result.securityRating.rawValue)
                    .font(.title.bold())
                    .foregroundColor(ratingColor(result.securityRating))
            }

            Spacer()

            Image(systemName: result.securityRating.icon)
                .font(.system(size: 50))
                .foregroundColor(ratingColor(result.securityRating))
        }
        .padding()
        .background(ratingColor(result.securityRating).opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - TLS Version

    private func tlsVersionCard(_ result: TLSAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TLS Version")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: result.tlsVersion.icon)
                        .foregroundColor(result.tlsVersion.isSecure ? .green : .orange)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.tlsVersion.version)
                            .font(.headline)
                        Text(result.tlsVersion.isModern ? "Modern and secure" : result.tlsVersion.isSecure ? "Secure" : "Outdated protocol")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if result.tlsVersion.isSecure {
                        Text("SECURE")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                }

                if let cipher = result.cipherSuite {
                    Divider()
                    HStack {
                        Text("Cipher Suite")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(cipher)
                            .font(.caption.monospaced())
                    }
                }

                if let latency = result.handshakeLatencyMs {
                    Divider()
                    HStack {
                        Text("Handshake")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.0f ms", latency))
                            .font(.caption.monospaced())
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Issues

    private func issuesCard(_ issues: [TLSIssue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Security Analysis")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
                    TLSAnalyzerIssueRow(issue: issue)

                    if index < issues.count - 1 {
                        Divider().padding(.leading, 30)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Certificate Chain

    private func certificateChainCard(_ chain: [CertificateInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Certificate Chain")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(chain.count) certificate\(chain.count > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(chain.enumerated()), id: \.element.id) { index, cert in
                    TLSAnalyzerCertRow(cert: cert, index: index, isLast: index == chain.count - 1)

                    if index < chain.count - 1 {
                        HStack {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 2, height: 16)
                                .padding(.leading, 19)
                            Spacer()
                        }
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Technical Details

    private func technicalDetailsCard(_ result: TLSAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Technical Details")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                TLSAnalyzerDetailRow(label: "Host", value: result.host)
                Divider()
                TLSAnalyzerDetailRow(label: "Port", value: "\(result.port)")
                Divider()
                TLSAnalyzerDetailRow(label: "TLS Version", value: result.tlsVersion.version)

                if let cipher = result.cipherSuite {
                    Divider()
                    TLSAnalyzerDetailRow(label: "Cipher", value: cipher)
                }

                Divider()

                let formatter = DateFormatter()
                let _ = formatter.dateStyle = .medium
                let _ = formatter.timeStyle = .short
                TLSAnalyzerDetailRow(label: "Analyzed", value: formatter.string(from: result.timestamp))
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Recent Results

    private var recentResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Analyses")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                ForEach(analyzer.recentResults) { result in
                    Button(action: { Task { await analyzer.analyzeHost(result.host) } }) {
                        HStack {
                            Image(systemName: result.securityRating.icon)
                                .foregroundColor(ratingColor(result.securityRating))

                            Text(result.host)
                                .font(.subheadline)
                                .foregroundColor(.primary)

                            Spacer()

                            Text(result.tlsVersion.version)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    // MARK: - Explanation

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("What does this check?")
                    .font(.subheadline.bold())
            }

            Text("The TLS Analyzer checks the security of HTTPS connections by examining the TLS protocol version and certificate validity.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                TLSAnalyzerFeatureRow(icon: "lock.shield", title: "TLS Version", description: "Checks for modern encryption (TLS 1.2/1.3)")
                TLSAnalyzerFeatureRow(icon: "checkmark.seal", title: "Certificate Validity", description: "Verifies certificate is not expired")
                TLSAnalyzerFeatureRow(icon: "link", title: "Certificate Chain", description: "Validates trust chain to root CA")
                TLSAnalyzerFeatureRow(icon: "shield.slash", title: "Security Issues", description: "Detects weak encryption or misconfigurations")
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("Important for detecting MITM attacks, especially on public Wi-Fi or in network environments where connections may be intercepted.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func ratingColor(_ rating: TLSAnalysisResult.SecurityRating) -> Color {
        switch rating {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor, .critical: return .red
        }
    }
}

// MARK: - Issue Row

private struct TLSAnalyzerIssueRow: View {
    let issue: TLSIssue
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: issue.severity.icon)
                        .foregroundColor(severityColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        if !isExpanded {
                            Text(issue.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(issue.description)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(issue.recommendation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
                .padding(.leading, 30)
            }
        }
        .padding(.vertical, 8)
    }

    private var severityColor: Color {
        switch issue.severity {
        case .critical, .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        case .info: return .blue
        }
    }
}

// MARK: - Certificate Row

private struct TLSAnalyzerCertRow: View {
    let cert: CertificateInfo
    let index: Int
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(circleColor.opacity(0.2))
                    .frame(width: 28, height: 28)

                if index == 0 {
                    Image(systemName: "leaf.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if isLast {
                    Image(systemName: "building.columns")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(cert.displaySubject)
                        .font(.subheadline.bold())
                        .lineLimit(1)

                    if cert.isExpired {
                        Text("EXPIRED")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(3)
                    } else if cert.isExpiringSoon {
                        Text("EXPIRING")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(3)
                    }
                }

                Text(certTypeLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Text(cert.publicKeyInfo)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let validTo = cert.validTo {
                        Text("Expires: \(formatDate(validTo))")
                            .font(.caption2)
                            .foregroundColor(cert.isExpired ? .red : .secondary)
                    }
                }

                Text("Issuer: \(cert.issuer)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }

    private var circleColor: Color {
        if cert.isExpired { return .red }
        if index == 0 { return .green }
        if isLast { return .blue }
        return .orange
    }

    private var certTypeLabel: String {
        if index == 0 { return "Leaf Certificate (Server)" }
        if isLast { return "Root CA" }
        return "Intermediate CA"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Detail Row

private struct TLSAnalyzerDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Feature Row

private struct TLSAnalyzerFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.bold())
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        TLSAnalyzerView()
    }
}
