//
//  NetworkAlertsView.swift
//  NetoSensei
//
//  Displays network alerts (new devices, unknown devices, etc.)
//  with read/unread state, mark all read, and clear.
//

import SwiftUI

struct NetworkAlertsView: View {
    @ObservedObject private var historyManager = DeviceHistoryManager.shared

    var body: some View {
        Group {
            if historyManager.alerts.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(historyManager.alerts) { alert in
                            DeviceHistoryAlertRow(alert: alert)
                                .onTapGesture {
                                    if !alert.isRead {
                                        historyManager.markAlertRead(alert.id)
                                    }
                                }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !historyManager.alerts.isEmpty {
                    Menu {
                        Button(action: { historyManager.markAllAlertsRead() }) {
                            Label("Mark All as Read", systemImage: "envelope.open")
                        }
                        Button(role: .destructive, action: { historyManager.clearAlerts() }) {
                            Label("Clear All Alerts", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))
            Text("No Alerts")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("You'll be notified when new or unknown devices join your network.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - Alert Row

private struct DeviceHistoryAlertRow: View {
    let alert: NetworkAlert

    var body: some View {
        HStack(spacing: 12) {
            // Alert type icon
            ZStack {
                Circle()
                    .fill(alertColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: alertIcon)
                    .font(.system(size: 14))
                    .foregroundColor(alertColor)
            }

            // Alert content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(alert.type.rawValue)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)

                    if !alert.isRead {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 7, height: 7)
                    }
                }

                Text(alert.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Text(timeAgo(alert.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(alert.isRead ? 0.7 : 1.0)
    }

    private var alertIcon: String {
        switch alert.type {
        case .newDevice: return "plus.circle.fill"
        case .unknownDevice: return "questionmark.circle.fill"
        case .suspiciousActivity: return "exclamationmark.triangle.fill"
        case .deviceReturned: return "arrow.uturn.left.circle.fill"
        }
    }

    private var alertColor: Color {
        switch alert.type {
        case .newDevice: return .blue
        case .unknownDevice: return .orange
        case .suspiciousActivity: return .red
        case .deviceReturned: return .green
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h ago" }
        let days = Int(elapsed / 86400)
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        NetworkAlertsView()
    }
}
