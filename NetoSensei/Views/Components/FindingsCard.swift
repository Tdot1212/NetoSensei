//
//  FindingsCard.swift
//  NetoSensei
//
//  Diagnosis v2 — renders Findings from the ONE verdict (design §C).
//  Replaces the Issues & Solutions and Smart Recommendations cards on Home
//  and the root-cause card on Diagnose. Every row shows: what's wrong,
//  the measured evidence, why, and exactly one action block.
//

import SwiftUI

struct FindingsCard: View {
    let verdict: NetworkVerdict
    var title: String = "What to do"
    var maxFindings: Int = 4
    @State private var expanded: UUID?

    var body: some View {
        let shown = Array(verdict.findings.prefix(maxFindings))
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundColor(.orange)
                    Text(title)
                        .font(.headline)
                }
                .padding(.leading, 4)

                VStack(spacing: 8) {
                    ForEach(shown) { finding in
                        FindingRow(finding: finding, isExpanded: expanded == finding.id) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                expanded = expanded == finding.id ? nil : finding.id
                            }
                        }
                    }
                }
                if verdict.findings.count > shown.count {
                    Text("+ \(verdict.findings.count - shown.count) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
    }
}

struct FindingRow: View {
    let finding: Finding
    let isExpanded: Bool
    let onTap: () -> Void

    private var tint: Color {
        if finding.byDesign { return .yellow }
        return finding.severity.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .foregroundColor(tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(finding.headline)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        Text(finding.action.categoryWord)
                            .font(.caption2.bold())
                            .foregroundColor(tint)
                        if !isExpanded {
                            Text(finding.cause)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if !finding.evidence.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("What was measured")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            ForEach(Array(finding.evidence.enumerated()), id: \.offset) { _, e in
                                HStack(spacing: 6) {
                                    Circle().fill(e.band?.color ?? .gray).frame(width: 8, height: 8)
                                    Text(e.text).font(.caption)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Why")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text(finding.cause).font(.caption)
                    }
                    actionBlock
                    Text("Confidence: \(finding.confidence.level.rawValue) — \(finding.confidence.reason)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding([.horizontal, .bottom])
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var icon: String {
        switch finding.action {
        case .userFixable: return "wrench.fill"
        case .fixableElsewhere: return "person.2.fill"
        case .notFixable: return "info.circle.fill"
        case .none: return "info.circle"
        }
    }

    @ViewBuilder
    private var actionBlock: some View {
        switch finding.action {
        case .userFixable(let steps):
            VStack(alignment: .leading, spacing: 4) {
                Text("You can fix this").font(.caption.bold()).foregroundColor(.secondary)
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(i + 1).").font(.caption.bold()).foregroundColor(.accentColor)
                        Text(step).font(.caption)
                    }
                }
            }
        case .fixableElsewhere(let who, let what, let meanwhile):
            VStack(alignment: .leading, spacing: 4) {
                Text("Who has to fix it: \(who)").font(.caption.bold())
                Text(what).font(.caption)
                if !meanwhile.isEmpty {
                    Text("Meanwhile").font(.caption.bold()).foregroundColor(.secondary)
                    ForEach(Array(meanwhile.enumerated()), id: \.offset) { _, m in
                        Text("• \(m)").font(.caption)
                    }
                }
            }
        case .notFixable(let why, let expect, let workarounds):
            VStack(alignment: .leading, spacing: 4) {
                Text("Not fixable right now").font(.caption.bold()).foregroundColor(.yellow)
                Text(why).font(.caption)
                Text("What to expect: \(expect)").font(.caption)
                if !workarounds.isEmpty {
                    Text("Workarounds").font(.caption.bold()).foregroundColor(.secondary)
                    ForEach(Array(workarounds.enumerated()), id: \.offset) { _, w in
                        Text("• \(w)").font(.caption)
                    }
                }
            }
        case .none:
            EmptyView()
        }
    }
}

/// The coverage line, rendered identically under every verdict.
struct CoverageLine: View {
    let coverage: Coverage
    var body: some View {
        Text(coverage.line)
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
