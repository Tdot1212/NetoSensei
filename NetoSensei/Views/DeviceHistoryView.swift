//
//  DeviceHistoryView.swift
//  NetoSensei
//
//  Main device history list — shows all devices ever seen on the network
//  with stats header, filter/search, and device list.
//

import SwiftUI

// MARK: - Device History View

struct DeviceHistoryView: View {
    @ObservedObject private var historyManager = DeviceHistoryManager.shared
    @ObservedObject private var discovery = NetworkDeviceDiscovery.shared

    @State private var searchText = ""
    @State private var selectedFilter: DeviceFilter = .all
    @State private var showingAlerts = false
    @State private var showingClearConfirmation = false

    enum DeviceFilter: String, CaseIterable {
        case all = "All"
        case connected = "Connected"
        case new = "New"
        case untrusted = "Untrusted"
        case trusted = "Trusted"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Stats header
                    deviceStatsHeader

                    // Filter pills
                    filterBar

                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search devices...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(10)

                    // Device list
                    if filteredDevices.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredDevices) { device in
                                NavigationLink(destination: DeviceDetailView(deviceId: device.id)) {
                                    DeviceHistoryRow(device: device)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Device History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingAlerts = true }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                            if historyManager.unreadAlertCount > 0 {
                                Text("\(historyManager.unreadAlertCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(3)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 8, y: -6)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: {
                            Task { await discovery.scanNetwork() }
                        }) {
                            if discovery.isScanning {
                                ProgressView()
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(discovery.isScanning)

                        Menu {
                            Button(role: .destructive, action: { showingClearConfirmation = true }) {
                                Label("Clear All History", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAlerts) {
                NavigationView {
                    NetworkAlertsView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showingAlerts = false }
                            }
                        }
                }
            }
            .alert("Clear All History?", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    historyManager.clearAllHistory()
                }
            } message: {
                Text("This will permanently delete all device history, events, and alerts.")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Stats Header

    private var deviceStatsHeader: some View {
        HStack(spacing: 8) {
            DeviceHistoryStatBox(
                title: "Total",
                value: "\(historyManager.devices.count)",
                color: .blue
            )
            DeviceHistoryStatBox(
                title: "Connected",
                value: "\(historyManager.connectedDevices.count)",
                color: .green
            )
            DeviceHistoryStatBox(
                title: "New (24h)",
                value: "\(historyManager.newDevices.count)",
                color: .orange
            )
            DeviceHistoryStatBox(
                title: "Untrusted",
                value: "\(historyManager.untrustedDevices.count)",
                color: historyManager.untrustedDevices.isEmpty ? .secondary : .red
            )
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DeviceFilter.allCases, id: \.self) { filter in
                    DeviceHistoryFilterPill(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter,
                        count: countForFilter(filter)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))

            if historyManager.devices.isEmpty {
                Text("No devices discovered yet")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Run a network scan to discover devices")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("No devices match your filter")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 40)
    }

    // MARK: - Filtering

    private var filteredDevices: [HistoricalDevice] {
        var result = historyManager.devices

        switch selectedFilter {
        case .all: break
        case .connected: result = result.filter { $0.isCurrentlyConnected }
        case .new: result = result.filter { $0.isNew }
        case .untrusted: result = result.filter { !$0.isTrusted }
        case .trusted: result = result.filter { $0.isTrusted }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.displayName.lowercased().contains(query)
                || $0.ipAddress.lowercased().contains(query)
                || ($0.hostname?.lowercased().contains(query) ?? false)
                || ($0.vendor?.lowercased().contains(query) ?? false)
            }
        }

        return result.sorted { $0.lastSeen > $1.lastSeen }
    }

    private func countForFilter(_ filter: DeviceFilter) -> Int {
        switch filter {
        case .all: return historyManager.devices.count
        case .connected: return historyManager.connectedDevices.count
        case .new: return historyManager.newDevices.count
        case .untrusted: return historyManager.untrustedDevices.count
        case .trusted: return historyManager.devices.filter { $0.isTrusted }.count
        }
    }
}

// MARK: - Stat Box

private struct DeviceHistoryStatBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

// MARK: - Filter Pill

private struct DeviceHistoryFilterPill: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.bold())
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(UIColor.secondarySystemGroupedBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

// MARK: - Device Row

private struct DeviceHistoryRow: View {
    let device: HistoricalDevice

    var body: some View {
        HStack(spacing: 12) {
            // Device icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: device.deviceType.icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconBackgroundColor)
            }

            // Device info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if device.isNew {
                        Text("NEW")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .cornerRadius(3)
                    }

                    if device.isTrusted {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                HStack(spacing: 8) {
                    Text(device.ipAddress)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)

                    Text(device.deviceType.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(device.connectionHistory)
                    .font(.caption2)
                    .foregroundColor(device.isCurrentlyConnected ? .green : .secondary)
            }

            Spacer()

            // Connection status dot
            Circle()
                .fill(device.isCurrentlyConnected ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var iconBackgroundColor: Color {
        if device.isCurrentlyConnected { return .blue }
        if !device.isTrusted { return .orange }
        return .gray
    }
}

// MARK: - Preview

#Preview {
    DeviceHistoryView()
}
