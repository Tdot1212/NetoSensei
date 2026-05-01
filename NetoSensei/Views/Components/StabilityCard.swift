//
//  StabilityCard.swift
//  NetoSensei
//
//  Connection stability display card for Dashboard
//

import SwiftUI

struct StabilityCard: View {
    @ObservedObject var stabilityMonitor: ConnectionStabilityMonitor

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                // Header
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: UIConstants.iconSizeM))
                        .foregroundColor(AppColors.textSecondary)
                    Text("Connection Stability")
                        .font(.headline)
                }

                // Stats row
                HStack(spacing: UIConstants.spacingL) {
                    // Uptime streak
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Uptime")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Text(stabilityMonitor.uptimeStreakFormatted)
                            .font(.subheadline.bold())
                            .foregroundColor(AppColors.green)
                    }

                    // Drops in last 24h
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drops (24h)")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Text("\(stabilityMonitor.dropsLast24h)")
                            .font(.subheadline.bold())
                            .foregroundColor(dropColor)
                    }

                    // Average latency
                    if let avgLatency = stabilityMonitor.averageLatency {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avg Latency")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Text("\(Int(avgLatency))ms")
                                .font(.subheadline.bold())
                                .foregroundColor(latencyColor(avgLatency))
                        }
                    }

                    Spacer()
                }

                // Timeline dots
                if !stabilityMonitor.events.isEmpty {
                    timelineRow
                }
            }
        }
    }

    private var timelineRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                let buckets = stabilityMonitor.timelineBuckets(hours: 24)

                ForEach(0..<buckets.count, id: \.self) { index in
                    Circle()
                        .fill(buckets[index] ? AppColors.green : AppColors.red)
                        .frame(width: 6, height: 6)
                }
            }

            // Drop annotations
            if stabilityMonitor.dropsLast24h > 0 {
                let drops = findDropTimes()
                if !drops.isEmpty {
                    Text("↑ drops: \(drops.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    private func findDropTimes() -> [String] {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        let dayAgo = Date().addingTimeInterval(-86400)
        let disconnects = stabilityMonitor.events
            .filter { $0.timestamp > dayAgo && $0.type == .disconnected }
            .prefix(3)

        return disconnects.map { formatter.string(from: $0.timestamp) }
    }

    private var dropColor: Color {
        NetworkColors.forDrops(stabilityMonitor.dropsLast24h)
    }

    private func latencyColor(_ latency: Double) -> Color {
        NetworkColors.forLatency(latency)
    }
}

// MARK: - Compact Stability Row (for inline display)

struct CompactStabilityRow: View {
    @ObservedObject var stabilityMonitor: ConnectionStabilityMonitor

    var body: some View {
        HStack(spacing: UIConstants.spacingM) {
            // Uptime
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundColor(AppColors.green)
                Text(stabilityMonitor.uptimeStreakFormatted)
                    .font(.caption.bold())
            }

            // Drops
            if stabilityMonitor.dropsLast24h > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(AppColors.yellow)
                    Text("\(stabilityMonitor.dropsLast24h) drops")
                        .font(.caption)
                }
            }

            Spacer()
        }
        .foregroundColor(AppColors.textSecondary)
    }
}

// MARK: - Preview

struct StabilityCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            StabilityCard(stabilityMonitor: ConnectionStabilityMonitor.shared)
            CompactStabilityRow(stabilityMonitor: ConnectionStabilityMonitor.shared)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}
