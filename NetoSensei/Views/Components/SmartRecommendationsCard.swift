//
//  SmartRecommendationsCard.swift
//  NetoSensei
//
//  Data-driven recommendations card based on measured diagnostic data
//

import SwiftUI

// MARK: - Smart Recommendations Card

struct SmartRecommendationsCard: View {
    let recommendations: [Recommendation]
    @State private var isExpanded = true

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                // Header
                Button(action: { isExpanded.toggle() }) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(AppColors.accent)
                        Text("Smart Recommendations")
                            .font(.headline)
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(Array(recommendations.prefix(5).enumerated()), id: \.element.id) { index, rec in
                        if index > 0 {
                            Divider()
                        }
                        recommendationRow(rec, index: index)
                    }

                    if recommendations.count > 5 {
                        Text("+ \(recommendations.count - 5) more")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
        }
    }

    private func recommendationRow(_ rec: Recommendation, index: Int) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.spacingS) {
            HStack(alignment: .top) {
                // Priority badge
                Text("#\(index + 1)")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor(rec.priority))
                    .foregroundColor(.white)
                    .cornerRadius(4)

                // Category icon
                Image(systemName: rec.category.icon)
                    .foregroundColor(categoryColor(rec.category))

                VStack(alignment: .leading, spacing: 4) {
                    Text(rec.title)
                        .font(.subheadline.bold())

                    Text(rec.description)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let action = rec.action {
                        Text(action)
                            .font(.caption)
                            .foregroundColor(AppColors.accent)
                            .padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 1: return AppColors.red
        case 2: return .orange
        case 3: return AppColors.yellow
        case 4, 5: return .blue
        default: return AppColors.green
        }
    }

    private func categoryColor(_ category: Recommendation.Category) -> Color {
        switch category {
        case .vpn: return .purple
        case .router: return .blue
        case .dns: return .cyan
        case .isp: return .orange
        case .general: return AppColors.green
        }
    }
}

// MARK: - Compact Recommendation Row (for Dashboard)

struct CompactRecommendationRow: View {
    let recommendation: Recommendation

    var body: some View {
        HStack(alignment: .top, spacing: UIConstants.spacingS) {
            Image(systemName: recommendation.category.icon)
                .foregroundColor(categoryColor(recommendation.category))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(recommendation.title)
                    .font(.subheadline.bold())

                Text(recommendation.description)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func categoryColor(_ category: Recommendation.Category) -> Color {
        switch category {
        case .vpn: return .purple
        case .router: return .blue
        case .dns: return .cyan
        case .isp: return .orange
        case .general: return AppColors.green
        }
    }
}

// MARK: - Diagnostic Tools Card

struct DiagnosticToolsCard: View {
    @Binding var showingDNSBenchmark: Bool
    @Binding var showingThrottleTest: Bool

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                Text("Diagnostic Tools")
                    .font(.headline)

                HStack(spacing: UIConstants.spacingM) {
                    // DNS Benchmark Button
                    Button(action: { showingDNSBenchmark = true }) {
                        VStack(spacing: UIConstants.spacingS) {
                            Image(systemName: "server.rack")
                                .font(.title2)
                                .foregroundColor(AppColors.accent)

                            Text("DNS Benchmark")
                                .font(.caption.bold())
                                .foregroundColor(AppColors.textPrimary)

                            Text("Find fastest DNS")
                                .font(.caption2)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.card)
                        .cornerRadius(UIConstants.cornerRadiusM)
                        .overlay(
                            RoundedRectangle(cornerRadius: UIConstants.cornerRadiusM)
                                .stroke(AppColors.accent.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // Throttle Test Button
                    Button(action: { showingThrottleTest = true }) {
                        VStack(spacing: UIConstants.spacingS) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "gauge.with.dots.needle.67percent")
                                    .font(.title2)
                                    .foregroundColor(AppColors.accent)

                                Text("NEW")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(AppColors.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                                    .offset(x: 8, y: -8)
                            }

                            Text("Throttle Test")
                                .font(.caption.bold())
                                .foregroundColor(AppColors.textPrimary)

                            Text("Detect ISP throttling")
                                .font(.caption2)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.card)
                        .cornerRadius(UIConstants.cornerRadiusM)
                        .overlay(
                            RoundedRectangle(cornerRadius: UIConstants.cornerRadiusM)
                                .stroke(AppColors.accent.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Preview

struct SmartRecommendationsCard_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                SmartRecommendationsCard(recommendations: [
                    Recommendation(
                        priority: 1,
                        title: "Switch VPN Server",
                        description: "Your VPN server in Ashburn is adding 209ms latency.",
                        action: "Try a server in Hong Kong or Singapore.",
                        deepLink: nil,
                        category: .vpn
                    ),
                    Recommendation(
                        priority: 2,
                        title: "Switch to Faster DNS",
                        description: "Your DNS takes 85ms to resolve.",
                        action: "Settings → Wi-Fi → Configure DNS → Add 1.1.1.1",
                        deepLink: "App-Prefs:WIFI",
                        category: .dns
                    ),
                    Recommendation(
                        priority: 3,
                        title: "WiFi Could Be Better",
                        description: "Gateway latency is 25ms — acceptable but not ideal.",
                        action: nil,
                        deepLink: nil,
                        category: .router
                    ),
                ])

                DiagnosticToolsCard(
                    showingDNSBenchmark: .constant(false),
                    showingThrottleTest: .constant(false)
                )
            }
            .padding()
        }
        .background(Color.gray.opacity(0.1))
    }
}
