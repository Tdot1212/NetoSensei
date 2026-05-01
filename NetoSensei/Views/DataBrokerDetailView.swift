//
//  DataBrokerDetailView.swift
//  NetoSensei
//
//  Detailed view for a single data broker — shows opt-out instructions,
//  removal status, difficulty rating, and action buttons.
//

import SwiftUI

struct DataBrokerDetailView: View {
    let broker: DataBroker

    @StateObject private var scanner = DigitalFootprintScanner.shared
    @State private var showingRemovalEmail = false

    var removalStatus: DigitalFootprintScanner.RemovalStatus? {
        scanner.removalProgress[broker.id]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                statusCard
                detailsCard
                instructionsCard
                actionsSection
            }
            .padding()
        }
        .navigationTitle(broker.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingRemovalEmail) {
            RemovalEmailView(broker: broker)
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: broker.category.icon)
                    .font(.title)
                    .foregroundColor(categoryColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(broker.name)
                        .font(.headline)
                    Text(broker.category.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(broker.difficulty.rawValue)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(difficultyColor)
                    .cornerRadius(6)
            }

            Text(broker.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Removal Status")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            HStack {
                if let status = removalStatus {
                    Image(systemName: status.status.icon)
                        .foregroundColor(statusColor(status.status))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.status.rawValue)
                            .font(.subheadline.bold())

                        if let date = status.requestedAt {
                            Text("Requested: \(date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.gray)

                    Text("Not started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if removalStatus?.status == .pending {
                    Button("Mark Removed") {
                        scanner.markRemoved(broker.id)
                    }
                    .font(.caption.bold())
                    .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Details Card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                BrokerDetailRow(label: "Opt-Out Method", value: broker.optOutMethod.rawValue)
                Divider()
                BrokerDetailRow(label: "Processing Time", value: broker.processingTime)
                Divider()
                BrokerDetailRow(label: "Estimated Time", value: "\(broker.difficulty.estimatedMinutes) min")
                Divider()
                BrokerDetailRow(label: "Requires ID", value: broker.requiresID ? "Yes" : "No")
                Divider()
                BrokerDetailRow(label: "Requires Email", value: broker.requiresEmail ? "Yes" : "No")
                Divider()
                BrokerDetailRow(label: "CCPA Support", value: broker.supportsCCPA ? "Yes" : "No")
                Divider()
                BrokerDetailRow(label: "GDPR Support", value: broker.supportsGDPR ? "Yes" : "No")
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Instructions Card

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to Opt Out")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(broker.instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.blue)
                            .clipShape(Circle())

                        Text(instruction)
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            if let optOutURL = broker.optOutURL, let url = URL(string: optOutURL) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("Go to Opt-Out Page")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }

            if broker.optOutMethod == .email || broker.supportsGDPR || broker.supportsCCPA {
                Button(action: { showingRemovalEmail = true }) {
                    HStack {
                        Image(systemName: "envelope")
                        Text("Generate Removal Email")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
                }
            }

            if removalStatus == nil {
                Button(action: { scanner.markRemovalRequested(broker.id) }) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Mark as Requested")
                    }
                    .font(.headline)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
            }

            if let url = URL(string: broker.websiteURL) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "globe")
                        Text("Visit Website")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - Helpers

    private var categoryColor: Color {
        switch broker.category {
        case .peopleSearch: return .blue
        case .dataAggregator: return .purple
        case .marketingList: return .orange
        case .backgroundCheck: return .red
        case .socialMedia: return .green
        case .publicRecords: return .gray
        case .advertising: return .yellow
        case .other: return .secondary
        }
    }

    private var difficultyColor: Color {
        switch broker.difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        case .veryHard: return .purple
        }
    }

    private func statusColor(_ status: FootprintScanResult.Status) -> Color {
        switch status {
        case .found: return .red
        case .notFound: return .green
        case .unknown: return .gray
        case .removed: return .blue
        case .pending: return .orange
        }
    }
}

// MARK: - Detail Row

private struct BrokerDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
        .padding(.vertical, 8)
    }
}
