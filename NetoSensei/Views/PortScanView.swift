//
//  PortScanView.swift
//  NetoSensei
//
//  Scan devices for open ports and identify services / security risks.
//

import SwiftUI

struct PortScanView: View {
    @StateObject private var scanner = PortScanner.shared
    @ObservedObject private var discovery = NetworkDeviceDiscovery.shared

    @State private var selectedDevice: String?  // IP or "router"/"localhost"
    @State private var customIP = ""
    @State private var scanMode: ScanMode = .quick

    enum ScanMode: String, CaseIterable {
        case quick = "Quick"
        case standard = "Standard"

        var description: String {
            switch self {
            case .quick: return "9 common ports (~10s)"
            case .standard: return "50+ ports (~60s)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                deviceSelectionSection
                scanModeSection
                actionButton

                if scanner.isScanning {
                    progressSection
                }

                if let result = scanner.currentDeviceResult, !scanner.isScanning {
                    resultSection(result)
                }

                if !scanner.isScanning && scanner.currentDeviceResult == nil {
                    riskExplanationCard
                }
            }
            .padding()
        }
        .navigationTitle("Port Scanner")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Port Scanner")
                    .font(.headline)
                Text("Find open ports and services")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Device Selection

    private var deviceSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Device")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                // Router
                let gatewayIP = NetworkMonitorService.shared.currentStatus.router.gatewayIP ?? "192.168.1.1"
                PortScanDeviceRow(
                    icon: "wifi.router",
                    title: "Router / Gateway",
                    subtitle: gatewayIP,
                    isSelected: selectedDevice == "router",
                    color: .orange
                ) { selectedDevice = "router" }

                // Localhost
                PortScanDeviceRow(
                    icon: "iphone",
                    title: "This Device",
                    subtitle: "127.0.0.1",
                    isSelected: selectedDevice == "localhost",
                    color: .blue
                ) { selectedDevice = "localhost" }

                // Discovered devices
                if !discovery.discoveredDevices.isEmpty {
                    Divider()
                    Text("Discovered Devices")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(discovery.discoveredDevices.prefix(8)) { device in
                        PortScanDeviceRow(
                            icon: device.deviceIcon,
                            title: device.hostname ?? device.ipAddress,
                            subtitle: device.hostname != nil ? device.ipAddress : nil,
                            isSelected: selectedDevice == device.ipAddress,
                            color: .green
                        ) { selectedDevice = device.ipAddress }
                    }
                }

                // Custom IP
                Divider()
                PortScanDeviceRow(
                    icon: "keyboard",
                    title: "Custom IP Address",
                    subtitle: nil,
                    isSelected: selectedDevice == "custom",
                    color: .purple
                ) { selectedDevice = "custom" }

                if selectedDevice == "custom" {
                    HStack {
                        TextField("192.168.1.100", text: $customIP)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)

                        Button("Set") {
                            if isValidIP(customIP) {
                                selectedDevice = customIP
                            }
                        }
                        .disabled(!isValidIP(customIP))
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Scan Mode

    private var scanModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan Mode")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            Picker("Scan Mode", selection: $scanMode) {
                ForEach(ScanMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(scanMode.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button(action: startScan) {
            HStack {
                if scanner.isScanning {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 20, height: 20)
                    Text("Scanning...")
                } else {
                    Image(systemName: "magnifyingglass")
                    Text("Scan Ports")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(canScan ? Color.blue : Color.gray)
            .cornerRadius(12)
        }
        .disabled(!canScan)
    }

    private var canScan: Bool {
        !scanner.isScanning && selectedDevice != nil && selectedDevice != "custom"
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: scanner.progress)
                .progressViewStyle(.linear)

            HStack {
                Text("Scanning \(scanner.currentIP)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Port \(scanner.currentPort)")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Results

    private func resultSection(_ result: DeviceScanResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.hostname ?? result.ipAddress)
                        .font(.headline)
                    Text(result.ipAddress)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(result.openPorts.count)")
                        .font(.title.bold())
                        .foregroundColor(riskColor(result.riskLevel))
                    Text("open ports")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(riskColor(result.riskLevel).opacity(0.1))
            .cornerRadius(12)

            // Risk summary
            HStack {
                Image(systemName: riskIcon(result.riskLevel))
                    .foregroundColor(riskColor(result.riskLevel))
                Text(result.riskSummary)
                    .font(.subheadline)
                    .foregroundColor(riskColor(result.riskLevel))
            }

            // Open ports list
            if !result.openPorts.isEmpty {
                Text("Open Ports")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)

                VStack(spacing: 0) {
                    ForEach(result.openPorts) { port in
                        PortResultRow(port: port)
                        if port.id != result.openPorts.last?.id {
                            Divider()
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            // Scan info
            HStack {
                Text("Scanned in \(String(format: "%.1fs", result.scanDuration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(result.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Risk Explanation

    private var riskExplanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Port Risk Levels")
                    .font(.subheadline.bold())
            }

            VStack(alignment: .leading, spacing: 8) {
                PortRiskLegendRow(color: .red, title: "Danger",
                                  description: "Should not be exposed (RDP, databases, Telnet)")
                PortRiskLegendRow(color: .orange, title: "Caution",
                                  description: "Review if intentional (FTP, email, UPnP)")
                PortRiskLegendRow(color: .green, title: "Safe",
                                  description: "Normal encrypted services (HTTPS)")
                PortRiskLegendRow(color: .blue, title: "Info",
                                  description: "Standard services (HTTP, SSH, DNS)")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func startScan() {
        guard let device = selectedDevice else { return }

        let ip: String
        switch device {
        case "router":
            ip = NetworkMonitorService.shared.currentStatus.router.gatewayIP ?? "192.168.1.1"
        case "localhost":
            ip = "127.0.0.1"
        case "custom":
            return
        default:
            ip = device
        }

        let ports: [UInt16]? = scanMode == .quick ? quickScanPorts : nil
        Task {
            _ = await scanner.scanDevice(ip: ip, hostname: nil, ports: ports)
        }
    }

    // MARK: - Helpers

    private func isValidIP(_ string: String) -> Bool {
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part) else { return false }
            return (0...255).contains(n)
        }
    }

    private func riskColor(_ risk: ScannedPort.PortRisk) -> Color {
        switch risk {
        case .safe: return .green
        case .caution: return .orange
        case .danger: return .red
        case .info: return .blue
        }
    }

    private func riskIcon(_ risk: ScannedPort.PortRisk) -> String {
        switch risk {
        case .safe: return "checkmark.shield"
        case .caution: return "exclamationmark.triangle"
        case .danger: return "xmark.shield"
        case .info: return "info.circle"
        }
    }
}

// MARK: - Device Selection Row

struct PortScanDeviceRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Port Result Row

struct PortResultRow: View {
    let port: ScannedPort

    var body: some View {
        HStack(spacing: 12) {
            Text("\(port.port)")
                .font(.system(.subheadline, design: .monospaced).bold())
                .foregroundColor(riskColor)
                .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(port.service)
                    .font(.subheadline)
                if let banner = port.banner {
                    Text(banner)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(port.risk.rawValue)
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(riskColor)
                .cornerRadius(4)

            if let ms = port.responseTimeMs {
                Text("\(Int(ms))ms")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var riskColor: Color {
        switch port.risk {
        case .safe: return .green
        case .caution: return .orange
        case .danger: return .red
        case .info: return .blue
        }
    }
}

// MARK: - Risk Legend Row

struct PortRiskLegendRow: View {
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(color)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
