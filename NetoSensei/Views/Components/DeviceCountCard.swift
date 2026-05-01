//
//  DeviceCountCard.swift
//  NetoSensei
//
//  Shows estimated device count on the local network
//  Uses TCP probe sweep to discover active hosts
//

import SwiftUI

struct DeviceCountCard: View {
    @StateObject private var discovery = NetworkDeviceDiscovery.shared
    @State private var isExpanded = false

    /// Optional secondary action surfaced under the device list. The Security
    /// tab passes a closure that opens the Port Scanner — moved here from the
    /// "Security Tools" section because port-scanning is a property of the
    /// devices on the LAN, not of the user's own protection.
    var onScanPorts: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "desktopcomputer")
                    .foregroundColor(.blue)
                Text("Devices on Network")
                    .font(.headline)

                Spacer()

                Button(action: {
                    Task { await discovery.scanNetwork() }
                }) {
                    if discovery.isScanning {
                        ProgressView()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .disabled(discovery.isScanning)
            }
            .padding(.leading, 4)

            CardView {
                VStack(spacing: 12) {
                    if discovery.isScanning {
                        // Scanning in progress
                        VStack(spacing: 8) {
                            ProgressView(value: discovery.scanProgress)
                                .progressViewStyle(.linear)
                            Text("Scanning network... \(Int(discovery.scanProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if discovery.discoveredDevices.count > 0 {
                                Text("Found \(discovery.discoveredDevices.count) device\(discovery.discoveredDevices.count == 1 ? "" : "s") so far")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if discovery.discoveredDevices.isEmpty {
                        // No data yet
                        VStack(spacing: 8) {
                            Image(systemName: "network")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("Tap refresh to scan for devices")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Discovers active devices on your local network using TCP probes.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else {
                        // Results
                        HStack(spacing: 16) {
                            VStack {
                                Text("~\(discovery.totalDeviceCount)")
                                    .font(.title.bold())
                                    .foregroundColor(.blue)
                                Text("Devices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(discovery.discoveredDevices.count) via TCP")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if !discovery.uniqueBonjourDevices.isEmpty {
                                    Text("\(discovery.uniqueBonjourDevices.count) via Bonjour")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if !discovery.uniqueSSDPDevices.isEmpty {
                                    Text("\(discovery.uniqueSSDPDevices.count) via SSDP")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if let lastScan = discovery.lastScanDate {
                                VStack {
                                    Text(timeAgo(lastScan))
                                        .font(.subheadline.bold())
                                    Text("Last scan")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button(action: { withAnimation { isExpanded.toggle() } }) {
                                HStack(spacing: 4) {
                                    Text(isExpanded ? "Hide" : "Details")
                                        .font(.caption)
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                            }
                        }

                        // Expandable device list
                        if isExpanded {
                            Divider()

                            // TCP-discovered devices (enriched with NetBIOS/SSDP names)
                            ForEach(discovery.discoveredDevices) { device in
                                HStack(spacing: 8) {
                                    Image(systemName: device.deviceIcon)
                                        .font(.caption)
                                        .foregroundColor(device.isGateway ? .orange : .blue)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 1) {
                                        if let hostname = device.hostname {
                                            Text(hostname)
                                                .font(.caption)
                                            Text(device.ipAddress)
                                                .font(.caption2.monospaced())
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text(device.ipAddress)
                                                .font(.caption.monospaced())
                                        }
                                        if let info = device.deviceInfo {
                                            Text(info)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    if device.isGateway {
                                        Text("GATEWAY")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange)
                                            .cornerRadius(3)
                                    }

                                    Spacer()

                                    Text("\(Int(device.responseTimeMs))ms")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Bonjour-discovered devices (deduplicated)
                            if !discovery.uniqueBonjourDevices.isEmpty {
                                Divider()
                                    .padding(.vertical, 4)

                                Text("Discovered Devices (Bonjour)")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)

                                ForEach(discovery.uniqueBonjourDevices) { device in
                                    HStack(spacing: 8) {
                                        Image(systemName: device.deviceTypeIcon)
                                            .font(.caption)
                                            .foregroundColor(.purple)
                                            .frame(width: 20)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(device.displayName)
                                                .font(.caption)
                                            Text(device.serviceDescription)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()
                                    }
                                }
                            }

                            // SSDP/UPnP-discovered devices
                            if !discovery.uniqueSSDPDevices.isEmpty {
                                Divider()
                                    .padding(.vertical, 4)

                                Text("Discovered Devices (SSDP/UPnP)")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)

                                ForEach(discovery.uniqueSSDPDevices) { device in
                                    HStack(spacing: 8) {
                                        Image(systemName: device.deviceTypeIcon)
                                            .font(.caption)
                                            .foregroundColor(.green)
                                            .frame(width: 20)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(device.displayName)
                                                .font(.caption)
                                            HStack(spacing: 4) {
                                                Text(device.serviceDescription)
                                                if device.manufacturer != nil || device.ip != device.displayName {
                                                    Text("·")
                                                    Text(device.ip)
                                                }
                                            }
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        }

                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // "Scan ports on these devices →" — secondary action moved here
            // from the old "Security Tools" section. Port scanning is a
            // property of the LAN devices listed above, not of the user's
            // own protection, so it lives next to the device list.
            if let onScanPorts = onScanPorts,
               !discovery.discoveredDevices.isEmpty,
               !discovery.isScanning {
                Button(action: onScanPorts) {
                    HStack(spacing: 8) {
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.caption)
                        Text("Scan ports on these devices")
                            .font(.caption.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            // Note about scan limitations
            if !discovery.discoveredDevices.isEmpty && !discovery.isScanning {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Uses TCP probes + Bonjour/mDNS + SSDP/UPnP + NetBIOS. Devices with strict firewalls may not respond.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        return "\(Int(elapsed / 3600))h ago"
    }
}
