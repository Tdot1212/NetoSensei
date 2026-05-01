//
//  DeviceDetailView.swift
//  NetoSensei
//
//  Detail view for a single historical device — editable name,
//  trust management, event timeline, port scan link.
//

import SwiftUI

struct DeviceDetailView: View {
    let deviceId: String

    @ObservedObject private var historyManager = DeviceHistoryManager.shared
    @ObservedObject private var portScanner = PortScanner.shared

    @State private var showingNameEditor = false
    @State private var showingNotesEditor = false
    @State private var showingTypeSelector = false
    @State private var showingPortScan = false
    @State private var showingDeleteConfirmation = false
    @State private var editName = ""
    @State private var editNotes = ""

    @Environment(\.dismiss) private var dismiss

    private var device: HistoricalDevice? {
        historyManager.devices.first { $0.id == deviceId }
    }

    var body: some View {
        Group {
            if let device = device {
                ScrollView {
                    VStack(spacing: 16) {
                        // Device header
                        deviceHeader(device)

                        // Quick actions
                        quickActions(device)

                        // Device info card
                        deviceInfoCard(device)

                        // Event timeline
                        eventTimeline(device)

                        // Danger zone
                        dangerZone(device)
                    }
                    .padding()
                }
                .navigationTitle(device.displayName)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Device not found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingNameEditor) {
            DeviceHistoryNameEditor(
                title: "Custom Name",
                text: $editName,
                onSave: {
                    historyManager.setCustomName(deviceId, name: editName.isEmpty ? nil : editName)
                }
            )
        }
        .sheet(isPresented: $showingNotesEditor) {
            DeviceHistoryNameEditor(
                title: "Notes",
                text: $editNotes,
                onSave: {
                    historyManager.setNotes(deviceId, notes: editNotes.isEmpty ? nil : editNotes)
                }
            )
        }
        .sheet(isPresented: $showingTypeSelector) {
            DeviceHistoryTypeSelector(deviceId: deviceId)
        }
        .sheet(isPresented: $showingPortScan) {
            NavigationView {
                PortScanView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showingPortScan = false }
                        }
                    }
            }
        }
        .alert("Delete Device?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                historyManager.deleteDevice(deviceId)
                dismiss()
            }
        } message: {
            Text("This will permanently remove this device and all its events.")
        }
    }

    // MARK: - Device Header

    private func deviceHeader(_ device: HistoricalDevice) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(headerColor(device).opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: device.deviceType.icon)
                    .font(.system(size: 32))
                    .foregroundColor(headerColor(device))
            }

            VStack(spacing: 4) {
                Text(device.displayName)
                    .font(.title2.bold())

                HStack(spacing: 6) {
                    Circle()
                        .fill(device.isCurrentlyConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(device.isCurrentlyConnected ? "Connected" : "Offline")
                        .font(.subheadline)
                        .foregroundColor(device.isCurrentlyConnected ? .green : .secondary)
                }

                if device.isTrusted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.caption)
                        Text("Trusted")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Quick Actions

    private func quickActions(_ device: HistoricalDevice) -> some View {
        HStack(spacing: 12) {
            DeviceHistoryActionButton(
                icon: device.isTrusted ? "shield.slash" : "checkmark.shield",
                title: device.isTrusted ? "Untrust" : "Trust",
                color: device.isTrusted ? .orange : .green
            ) {
                if device.isTrusted {
                    historyManager.untrustDevice(deviceId)
                } else {
                    historyManager.trustDevice(deviceId)
                }
            }

            DeviceHistoryActionButton(
                icon: "pencil",
                title: "Rename",
                color: .blue
            ) {
                editName = device.customName ?? ""
                showingNameEditor = true
            }

            DeviceHistoryActionButton(
                icon: "network.badge.shield.half.filled",
                title: "Scan Ports",
                color: .purple
            ) {
                showingPortScan = true
            }

            DeviceHistoryActionButton(
                icon: "square.and.pencil",
                title: "Notes",
                color: .indigo
            ) {
                editNotes = device.notes ?? ""
                showingNotesEditor = true
            }
        }
    }

    // MARK: - Device Info Card

    private func deviceInfoCard(_ device: HistoricalDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Information")
                .font(.headline)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                DeviceHistoryInfoRow(label: "IP Address", value: device.ipAddress, icon: "number")

                Divider().padding(.leading, 36)

                if let hostname = device.hostname {
                    DeviceHistoryInfoRow(label: "Hostname", value: hostname, icon: "server.rack")
                    Divider().padding(.leading, 36)
                }

                if let vendor = device.vendor {
                    DeviceHistoryInfoRow(label: "Vendor", value: vendor, icon: "building.2")
                    Divider().padding(.leading, 36)
                }

                Button(action: { showingTypeSelector = true }) {
                    DeviceHistoryInfoRow(
                        label: "Type",
                        value: device.deviceType.rawValue,
                        icon: device.deviceType.icon,
                        showChevron: true
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 36)

                DeviceHistoryInfoRow(
                    label: "First Seen",
                    value: formatDate(device.firstSeen),
                    icon: "calendar"
                )

                Divider().padding(.leading, 36)

                DeviceHistoryInfoRow(
                    label: "Last Seen",
                    value: formatDate(device.lastSeen),
                    icon: "clock"
                )

                Divider().padding(.leading, 36)

                DeviceHistoryInfoRow(
                    label: "Times Seen",
                    value: "\(device.seenCount)",
                    icon: "eye"
                )

                if let ssid = device.networkSSID {
                    Divider().padding(.leading, 36)
                    DeviceHistoryInfoRow(label: "Network", value: ssid, icon: "wifi")
                }

                if let notes = device.notes, !notes.isEmpty {
                    Divider().padding(.leading, 36)
                    DeviceHistoryInfoRow(label: "Notes", value: notes, icon: "note.text")
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Event Timeline

    private func eventTimeline(_ device: HistoricalDevice) -> some View {
        let events = historyManager.eventsForDevice(deviceId)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity Timeline")
                    .font(.headline)
                Spacer()
                Text("\(events.count) events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 4)

            if events.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No events recorded yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    Spacer()
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.prefix(20).enumerated()), id: \.element.id) { index, event in
                        DeviceHistoryTimelineRow(event: event)
                        if index < min(events.count, 20) - 1 {
                            Divider().padding(.leading, 36)
                        }
                    }

                    if events.count > 20 {
                        HStack {
                            Spacer()
                            Text("+ \(events.count - 20) more events")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                            Spacer()
                        }
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Danger Zone

    private func dangerZone(_ device: HistoricalDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { showingDeleteConfirmation = true }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Device")
                }
                .font(.subheadline.bold())
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func headerColor(_ device: HistoricalDevice) -> Color {
        if device.isCurrentlyConnected { return .blue }
        if !device.isTrusted { return .orange }
        return .gray
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Action Button

private struct DeviceHistoryActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
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
        .buttonStyle(.plain)
    }
}

// MARK: - Info Row

private struct DeviceHistoryInfoRow: View {
    let label: String
    let value: String
    let icon: String
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Timeline Row

private struct DeviceHistoryTimelineRow: View {
    let event: DeviceEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: eventIcon)
                .font(.caption)
                .foregroundColor(eventColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.eventType.rawValue)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Text(event.ipAddress)
                        .font(.caption.monospaced())

                    if let ssid = event.networkSSID {
                        Text("on \(ssid)")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            Text(timeAgo(event.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var eventIcon: String {
        switch event.eventType {
        case .joined: return "arrow.right.circle.fill"
        case .left: return "arrow.left.circle.fill"
        case .firstSeen: return "star.circle.fill"
        case .ipChanged: return "arrow.triangle.2.circlepath"
        }
    }

    private var eventColor: Color {
        switch event.eventType {
        case .joined: return .green
        case .left: return .red
        case .firstSeen: return .orange
        case .ipChanged: return .blue
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

// MARK: - Name / Notes Editor Sheet

private struct DeviceHistoryNameEditor: View {
    let title: String
    @Binding var text: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(title, text: $text)
                }
            }
            .navigationTitle("Edit \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}

// MARK: - Device Type Selector Sheet

private struct DeviceHistoryTypeSelector: View {
    let deviceId: String
    @ObservedObject private var historyManager = DeviceHistoryManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(HistoricalDevice.DeviceCategory.allCases, id: \.self) { category in
                    Button(action: {
                        historyManager.setDeviceType(deviceId, type: category)
                        dismiss()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: category.icon)
                                .font(.title3)
                                .foregroundColor(.blue)
                                .frame(width: 28)

                            Text(category.rawValue)
                                .foregroundColor(.primary)

                            Spacer()

                            if historyManager.devices.first(where: { $0.id == deviceId })?.deviceType == category {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Device Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DeviceDetailView(deviceId: "sample_device")
}
