//
//  ConnectionComparisonView.swift
//  NetoSensei
//
//  Wi-Fi vs Cellular comparison UI — side-by-side results,
//  winner card, detailed metrics, and use-case recommendations.
//

import SwiftUI

struct ConnectionComparisonView: View {
    @StateObject private var comparator = ConnectionComparator.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                actionButton

                if comparator.isRunning {
                    progressSection
                }

                if let comparison = comparator.comparisonResult, !comparator.isRunning {
                    resultsSection(comparison)
                }

                if comparator.comparisonResult == nil && !comparator.isRunning {
                    explanationCard
                }
            }
            .padding()
        }
        .refreshable {
            _ = await comparator.runComparison()
        }
        .navigationTitle("Compare Connections")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack {
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wi-Fi vs Cellular")
                    .font(.headline)
                Text("Find your best connection")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let info = comparator.cellularInfo {
                VStack(alignment: .trailing, spacing: 2) {
                    if let tech = info.radioTechnology {
                        Text(tech)
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                    if let carrier = info.carrierName {
                        Text(carrier)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button(action: { Task { _ = await comparator.runComparison() } }) {
            HStack {
                if comparator.isRunning {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 20, height: 20)
                    Text("Testing \(comparator.currentTest?.rawValue ?? "")...")
                } else {
                    Image(systemName: "speedometer")
                    Text(comparator.comparisonResult != nil ? "Test Again" : "Compare Connections")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(comparator.isRunning ? Color.gray : Color.blue)
            .cornerRadius(12)
        }
        .disabled(comparator.isRunning)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: comparator.progress)
                .progressViewStyle(.linear)

            HStack(spacing: 20) {
                ComparisonStatusBadge(
                    type: .wifi,
                    isActive: comparator.currentTest == .wifi,
                    isComplete: comparator.wifiResult != nil
                )
                ComparisonStatusBadge(
                    type: .cellular,
                    isActive: comparator.currentTest == .cellular,
                    isComplete: comparator.cellularResult != nil
                )
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Results

    private func resultsSection(_ comparison: ComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            winnerCard(comparison)
            comparisonCards(comparison)

            // FIX (Issue 6): Surface manual-toggle instructions when the
            // cellular test couldn't actually run (WiFi was primary, or
            // NWConnection couldn't reach .ready over cellular within 5s).
            if comparison.cellularResult.error == ConnectionComparator.manualToggleError {
                manualToggleCard
            }

            metricsComparison(comparison)

            if !comparison.useCases.isEmpty {
                useCaseCard(comparison)
            }
        }
    }

    /// FIX (Issue 6): iOS does not let third-party apps toggle Wi-Fi or force
    /// URLSession onto a non-primary interface. Tell the user the actionable
    /// path instead of leaving them with an unexplained "Unavailable".
    private var manualToggleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.orange)
                Text("Cellular test requires manual toggle")
                    .font(.subheadline.bold())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("1. Open Settings → Wi-Fi → toggle off")
                Text("2. Return to NetoSensei → tap Run Again")
                Text("3. After test completes, turn Wi-Fi back on")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text("iOS doesn't allow apps to control Wi-Fi automatically.")
                .font(.caption2)
                .italic()
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    // MARK: - Winner Card

    private func winnerCard(_ comparison: ComparisonResult) -> some View {
        VStack(spacing: 12) {
            if let winner = comparison.winner {
                Image(systemName: winner.icon)
                    .font(.system(size: 40))
                    .foregroundColor(winner == .wifi ? .blue : .green)

                Text(comparison.recommendation.title)
                    .font(.title3.bold())

                Text(comparison.recommendation.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)

                Text("Connection Issue")
                    .font(.title3.bold())

                Text("Unable to test both connections")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Side-by-Side Cards

    private func comparisonCards(_ comparison: ComparisonResult) -> some View {
        HStack(spacing: 12) {
            ComparisonResultCard(
                result: comparison.wifiResult,
                isWinner: comparison.winner == .wifi
            )

            VStack {
                Text("VS")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
            .frame(width: 30)

            ComparisonResultCard(
                result: comparison.cellularResult,
                isWinner: comparison.winner == .cellular
            )
        }
    }

    // MARK: - Detailed Metrics

    private func metricsComparison(_ comparison: ComparisonResult) -> some View {
        // FIX (Issue 3): a "winner crown" only makes sense when both sides have
        // a real measurement. With cellular Unavailable, crowns next to every
        // WiFi metric implied a comparison that wasn't actually performed.
        let canCompareDownload = comparison.wifiResult.downloadSpeedMbps != nil
            && comparison.cellularResult.downloadSpeedMbps != nil
        let canCompareUpload = comparison.wifiResult.uploadSpeedMbps != nil
            && comparison.cellularResult.uploadSpeedMbps != nil
        let canCompareLatency = comparison.wifiResult.latencyMs != nil
            && comparison.cellularResult.latencyMs != nil
        let canCompareJitter = comparison.wifiResult.jitterMs != nil
            && comparison.cellularResult.jitterMs != nil

        return VStack(alignment: .leading, spacing: 8) {
            Text("Detailed Comparison")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ComparisonMetricRow(
                    metric: "Download",
                    wifiValue: formatSpeed(comparison.wifiResult.downloadSpeedMbps),
                    cellularValue: formatSpeed(comparison.cellularResult.downloadSpeedMbps),
                    wifiWins: (comparison.wifiResult.downloadSpeedMbps ?? 0) > (comparison.cellularResult.downloadSpeedMbps ?? 0),
                    showWinnerCrown: canCompareDownload
                )
                Divider()

                ComparisonMetricRow(
                    metric: "Upload",
                    wifiValue: formatSpeed(comparison.wifiResult.uploadSpeedMbps),
                    cellularValue: formatSpeed(comparison.cellularResult.uploadSpeedMbps),
                    wifiWins: (comparison.wifiResult.uploadSpeedMbps ?? 0) > (comparison.cellularResult.uploadSpeedMbps ?? 0),
                    showWinnerCrown: canCompareUpload
                )
                Divider()

                ComparisonMetricRow(
                    metric: "Latency",
                    wifiValue: formatLatency(comparison.wifiResult.latencyMs),
                    cellularValue: formatLatency(comparison.cellularResult.latencyMs),
                    wifiWins: (comparison.wifiResult.latencyMs ?? 999) < (comparison.cellularResult.latencyMs ?? 999),
                    showWinnerCrown: canCompareLatency
                )
                Divider()

                ComparisonMetricRow(
                    metric: "Jitter",
                    wifiValue: formatLatency(comparison.wifiResult.jitterMs),
                    cellularValue: formatLatency(comparison.cellularResult.jitterMs),
                    wifiWins: (comparison.wifiResult.jitterMs ?? 999) < (comparison.cellularResult.jitterMs ?? 999),
                    showWinnerCrown: canCompareJitter
                )
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Use Case Card

    private func useCaseCard(_ comparison: ComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Best For")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(comparison.useCases.enumerated()), id: \.element.id) { index, useCase in
                    ComparisonUseCaseRow(useCase: useCase)

                    if index < comparison.useCases.count - 1 {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Explanation

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("How it works")
                    .font(.subheadline.bold())
            }

            Text("This test measures both your Wi-Fi and cellular connections to help you choose the best one for your current situation.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                ComparisonFeatureRow(icon: "arrow.down", text: "Download speed test")
                ComparisonFeatureRow(icon: "arrow.up", text: "Upload speed test")
                ComparisonFeatureRow(icon: "timer", text: "Latency measurement")
                ComparisonFeatureRow(icon: "waveform.path", text: "Jitter analysis")
                ComparisonFeatureRow(icon: "checkmark.circle", text: "Use case recommendations")
            }

            Divider()

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("Note: This test uses data from both connections. Each test uses approximately 10MB.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Formatters

    private func formatSpeed(_ mbps: Double?) -> String {
        guard let speed = mbps else { return "—" }
        if speed >= 100 { return String(format: "%.0f Mbps", speed) }
        return String(format: "%.1f Mbps", speed)
    }

    private func formatLatency(_ ms: Double?) -> String {
        guard let latency = ms else { return "—" }
        return String(format: "%.0f ms", latency)
    }
}

// MARK: - Status Badge

private struct ComparisonStatusBadge: View {
    let type: ConnectionTestResult.ConnectionType
    let isActive: Bool
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 36, height: 36)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                } else {
                    Image(systemName: type.icon)
                        .font(.caption)
                        .foregroundColor(isActive ? .blue : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(type.rawValue)
                    .font(.caption.bold())
                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var backgroundColor: Color {
        if isComplete { return .green }
        if isActive { return Color.blue.opacity(0.2) }
        return Color(UIColor.systemGray5)
    }

    private var statusText: String {
        if isComplete { return "Complete" }
        if isActive { return "Testing..." }
        return "Waiting"
    }
}

// MARK: - Result Card

private struct ComparisonResultCard: View {
    let result: ConnectionTestResult
    let isWinner: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 50, height: 50)
                Image(systemName: result.connectionType.icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
            }

            Text(result.connectionType.rawValue)
                .font(.subheadline.bold())

            if let speed = result.downloadSpeedMbps {
                Text(String(format: "%.1f", speed))
                    .font(.title2.bold())
                    .foregroundColor(isWinner ? .green : .primary)
                Text("Mbps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("—")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: result.qualityRating.icon)
                    .font(.caption2)
                Text(result.qualityRating.rawValue)
                    .font(.caption)
            }
            .foregroundColor(ratingColor)

            if isWinner {
                Text("BEST")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(isWinner ? Color.green.opacity(0.1) : Color(UIColor.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isWinner ? Color.green : Color.clear, lineWidth: 2)
        )
        .cornerRadius(12)
    }

    private var iconBackground: Color {
        if isWinner { return Color.green.opacity(0.2) }
        if result.isSuccessful { return Color.blue.opacity(0.2) }
        return Color(UIColor.systemGray5)
    }

    private var iconColor: Color {
        if isWinner { return .green }
        if result.isSuccessful { return .blue }
        return .secondary
    }

    private var ratingColor: Color {
        switch result.qualityRating {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        case .veryPoor: return .red
        case .unavailable: return .gray
        }
    }
}

// MARK: - Metric Row

private struct ComparisonMetricRow: View {
    let metric: String
    let wifiValue: String
    let cellularValue: String
    let wifiWins: Bool
    /// FIX (Issue 3): only render the winner crown / green highlight when the
    /// caller has confirmed BOTH sides produced a real measurement. Otherwise
    /// "winner" is meaningless — there's no comparison.
    var showWinnerCrown: Bool = true

    var body: some View {
        HStack {
            HStack {
                if showWinnerCrown && wifiWins && wifiValue != "—" {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                Text(wifiValue)
                    .font(.subheadline.monospaced())
                    .foregroundColor(showWinnerCrown && wifiWins && wifiValue != "—" ? .green : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text(metric)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70)

            HStack {
                Text(cellularValue)
                    .font(.subheadline.monospaced())
                    .foregroundColor(showWinnerCrown && !wifiWins && cellularValue != "—" ? .green : .primary)
                if showWinnerCrown && !wifiWins && cellularValue != "—" {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Use Case Row

private struct ComparisonUseCaseRow: View {
    let useCase: ComparisonResult.UseCase

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: useCase.icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(useCase.activity)
                    .font(.subheadline)
                Text(useCase.reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: useCase.recommended.icon)
                    .font(.caption)
                Text(useCase.recommended.rawValue)
                    .font(.caption.bold())
            }
            .foregroundColor(useCase.recommended == .wifi ? .blue : .green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(useCase.recommended == .wifi ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
            .cornerRadius(6)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Feature Row

private struct ComparisonFeatureRow: View {
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
        ConnectionComparisonView()
    }
}
