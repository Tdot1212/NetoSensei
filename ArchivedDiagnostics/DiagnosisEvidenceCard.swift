import SwiftUI
// MARK: - Diagnosis Evidence Cards

struct DiagnosisEvidenceCard: View {
    let diagnosis: NetworkDiagnosis

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnosis Evidence")
                .font(.headline)
                .padding(.leading, 4)

            CardView {
                VStack(spacing: 0) {
                    // Header with scores summary
                    Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } }) {
                        HStack {
                            Image(systemName: "stethoscope")
                                .foregroundColor(.blue)
                                .font(.title2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(diagnosis.scores.summary)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                if let issue = diagnosis.primaryIssue {
                                    Text(issue)
                                        .font(.caption2)
                                        .foregroundColor(.orange)
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
                        Divider()
                            .padding(.vertical, 8)

                        // 5 Scores
                        VStack(spacing: 8) {
                            scoreRow("Local Network", score: diagnosis.scores.localNetwork)
                            scoreRow("Domestic Internet", score: diagnosis.scores.domesticInternet)
                            scoreRow("International", score: diagnosis.scores.internationalInternet)
                            scoreRow("Privacy", score: diagnosis.scores.privacy)
                            scoreRow("Stability", score: diagnosis.scores.stability)
                        }

                        // Explanation Cards
                        if !diagnosis.cards.isEmpty {
                            Divider()
                                .padding(.vertical, 8)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Evidence")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)

                                ForEach(diagnosis.cards) { card in
                                    evidenceCardRow(card)
                                }
                            }
                        }

                        // Probe Results
                        if !diagnosis.probeResults.isEmpty {
                            Divider()
                                .padding(.vertical, 8)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Probes")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)

                                ForEach(diagnosis.probeResults) { probe in
                                    probeRow(probe)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func scoreRow(_ label: String, score: Int) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(scoreColor(score))
                        .frame(width: max(0, geo.size.width * CGFloat(score) / 100), height: 6)
                }
            }
            .frame(height: 6)

            Text("\(score)")
                .font(.caption.bold())
                .foregroundColor(scoreColor(score))
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .blue }
        if score >= 40 { return .yellow }
        if score >= 20 { return .orange }
        return .red
    }

    private func evidenceCardRow(_ card: ExplanationCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: cardResultIcon(card.result))
                    .font(.caption2)
                    .foregroundColor(cardResultColor(card.result))
                // FIX (Sec Issue 6): Prefer displayLabel when provided so two
                // .internet cards (Domestic / Overseas) don't both render as
                // bare "Internet" with opposite verdicts.
                Text(card.displayLabel ?? card.category.rawValue)
                    .font(.caption.bold())

                Spacer()

                // Confidence badge
                Text(card.confidence.label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confidenceColor(card.confidence).opacity(0.2))
                    .foregroundColor(confidenceColor(card.confidence))
                    .cornerRadius(4)
            }

            Text(card.measured)
                .font(.caption2)
                .foregroundColor(.secondary)

            if let limitation = card.iOSLimitation {
                Text(limitation)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }

            Text(card.nextSteps)
                .font(.caption2)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }

    /// Map InterpretationEngine's SCREAMING_SNAKE_CASE probe names to plain-
    /// English labels for the user-facing Diagnosis Evidence row. Pure
    /// presentation transform — the underlying probe data is unchanged.
    private func displayName(for probeName: String) -> String {
        switch probeName {
        case "LOCAL_NETWORK":      return "Local Network"
        case "DOMESTIC_INTERNET":  return "Domestic Internet"
        case "OVERSEAS_INTERNET":  return "Overseas Internet"
        case "SYSTEM_DNS":         return "System DNS"
        case "VPN_STATE":          return "VPN State"
        case "IP_IDENTITY":        return "IP & Location"
        case "SPEED_TEST":         return "Speed Test"
        default:                   return probeName
        }
    }

    private func probeRow(_ probe: ProbeResult) -> some View {
        HStack(spacing: 6) {
            Image(systemName: probe.passed ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption2)
                .foregroundColor(probe.passed ? .green : .red)

            Text(displayName(for: probe.name))
                .font(.caption)
                .frame(width: 80, alignment: .leading)

            Text(probe.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            if let ms = probe.latencyMs {
                Text("\(Int(ms))ms")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
        }
    }

    private func cardResultIcon(_ result: CardResult) -> String {
        switch result {
        case .good: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.circle.fill"
        case .hidden: return "eye.slash.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func cardResultColor(_ result: CardResult) -> Color {
        switch result {
        case .good: return .green
        case .warning: return .yellow
        case .problem: return .red
        case .hidden: return .gray
        case .unknown: return .gray
        }
    }

    private func confidenceColor(_ confidence: CardConfidence) -> Color {
        switch confidence {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        }
    }
}
