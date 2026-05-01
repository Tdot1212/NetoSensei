//
//  RemovalProgressView.swift
//  NetoSensei
//
//  Tracks the status of data removal requests across all brokers.
//

import SwiftUI

struct RemovalProgressView: View {
    @StateObject private var scanner = DigitalFootprintScanner.shared

    var pendingItems: [(String, DigitalFootprintScanner.RemovalStatus)] {
        scanner.removalProgress.filter { $0.value.status == .pending }
            .sorted { ($0.value.requestedAt ?? .distantPast) > ($1.value.requestedAt ?? .distantPast) }
    }

    var completedItems: [(String, DigitalFootprintScanner.RemovalStatus)] {
        scanner.removalProgress.filter { $0.value.status == .removed }
            .sorted { ($0.value.completedAt ?? .distantPast) > ($1.value.completedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            if pendingItems.isEmpty && completedItems.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("No Removal Requests")
                            .font(.headline)

                        Text("Start by scanning for your data and requesting removals from data brokers.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }

            if !pendingItems.isEmpty {
                Section("Pending (\(pendingItems.count))") {
                    ForEach(pendingItems, id: \.0) { brokerID, status in
                        RemovalProgressRow(
                            brokerID: brokerID,
                            status: status,
                            onMarkComplete: { scanner.markRemoved(brokerID) }
                        )
                    }
                }
            }

            if !completedItems.isEmpty {
                Section("Completed (\(completedItems.count))") {
                    ForEach(completedItems, id: \.0) { brokerID, status in
                        RemovalProgressRow(
                            brokerID: brokerID,
                            status: status,
                            onMarkComplete: nil
                        )
                    }
                }
            }
        }
        .navigationTitle("Removal Progress")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Progress Row

private struct RemovalProgressRow: View {
    let brokerID: String
    let status: DigitalFootprintScanner.RemovalStatus
    let onMarkComplete: (() -> Void)?

    private var brokerName: String {
        DataBrokerDatabase.shared.brokers.first(where: { $0.id == brokerID })?.name ?? brokerID
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.status.icon)
                .foregroundColor(status.status == .removed ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(brokerName)
                    .font(.subheadline.bold())

                if let date = status.requestedAt {
                    Text("Requested \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let date = status.completedAt {
                    Text("Completed \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            if let action = onMarkComplete {
                Button("Done", action: action)
                    .font(.caption.bold())
                    .foregroundColor(.green)
            }
        }
    }
}
