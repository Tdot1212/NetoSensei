//
//  RemovalGuideView.swift
//  NetoSensei
//
//  Step-by-step guide for removing personal data from the internet.
//

import SwiftUI

struct RemovalGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Introduction
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to Remove Your Data")
                        .font(.title2.bold())

                    Text("Follow these steps to minimize your digital footprint and protect your privacy.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Steps
                GuideStep(
                    number: 1,
                    title: "Start with Easy Opt-Outs",
                    description: "Begin with sites that have simple web-form opt-outs. These typically process within 24-48 hours.",
                    icon: "bolt.fill",
                    color: .green
                )

                GuideStep(
                    number: 2,
                    title: "Generate Removal Emails",
                    description: "For sites requiring email requests, use our GDPR/CCPA email generator to create legally compliant requests.",
                    icon: "envelope.fill",
                    color: .blue
                )

                GuideStep(
                    number: 3,
                    title: "Handle Difficult Removals",
                    description: "Some sites require ID verification or physical mail. Set aside time for these harder opt-outs.",
                    icon: "doc.text.fill",
                    color: .orange
                )

                GuideStep(
                    number: 4,
                    title: "Track Your Progress",
                    description: "Mark each request as sent and monitor for confirmations. Re-check after processing times.",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .purple
                )

                GuideStep(
                    number: 5,
                    title: "Repeat Regularly",
                    description: "Data brokers re-collect information. Scan again every 3-6 months to catch new listings.",
                    icon: "arrow.clockwise",
                    color: .red
                )

                // Tips
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tips")
                        .font(.headline)

                    GuideTip(icon: "envelope", text: "Use a dedicated email for opt-out requests so you can track responses")
                    GuideTip(icon: "doc.on.doc", text: "Screenshot your opt-out submissions as proof")
                    GuideTip(icon: "clock", text: "Allow the full processing time before re-checking")
                    GuideTip(icon: "shield", text: "Consider using a VPN when visiting data broker sites")
                }
                .padding()
                .background(Color(UIColor.systemGray6))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Removal Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Guide Step

private struct GuideStep: View {
    let number: Int
    let title: String
    let description: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Step \(number): \(title)")
                    .font(.subheadline.bold())

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Guide Tip

private struct GuideTip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
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
