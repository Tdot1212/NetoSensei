import SwiftUI

struct DeviceCountCard: View {
    @StateObject private var discovery = NetworkDeviceDiscovery.shared
    @State private var inventory: WiFiDeviceInventory?
    @State private var scanPath: Date?
    @State private var isRunning = false
    @State private var showIdentification = false
    @State private var message: String?
    @Environment(\.openURL) private var openURL

    var onScanPorts: (() -> Void)? = nil

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Devices on this network", systemImage: "network").font(.headline)
                if isRunning {
                    ProgressView(discovery.isScanning ? "Looking for responding addresses…" : "Matching advertised names…")
                } else {
                    Button("Look for devices", action: scan)
                        .buttonStyle(.borderedProminent)
                        .disabled(discovery.isScanning)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                if let inventory, scanPath == ExitPath.lastPathChange {
                    results(inventory)
                }
                Text("The list shows addresses your phone could observe. Check your router’s client list for connected devices the scan missed.")
                    .font(.footnote).foregroundStyle(.secondary)

                DisclosureGroup("Identify a phone or computer", isExpanded: $showIdentification) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("On the device, open Wi-Fi settings and tap the network’s information button. On a Mac, open System Settings → Wi-Fi → Details → TCP/IP. Match the IPv4 address to a row.")
                        Text("For a device without a match, open your router’s Connected Devices or Clients list. Match the device name or its Wi-Fi address. If you confirm an unauthorized device, use your router’s Pause or Block control, if available.")
                        if let url = WiFiRepairGuide.routerURL(gateway: DefaultRouteResolver.lanGateway()?.gateway,
                                                               localSubnet: IPv4Subnet.activeWiFi()) {
                            Button("Try router settings") { openURL(url) }
                            Text("If the page doesn’t open, use the router maker’s app or the admin address in its manual.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func results(_ inventory: WiFiDeviceInventory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(inventory.otherAddressCount) other IPv4 addresses observed").font(.subheadline.bold())
            let named = inventory.observations.filter { $0.name != nil || $0.isGateway }
            let unnamed = inventory.observations.filter { $0.name == nil && !$0.isGateway }
            ForEach(named) { row($0) }
            if !unnamed.isEmpty {
                DisclosureGroup("Unnamed addresses (\(unnamed.count))") {
                    ForEach(unnamed) { row($0).padding(.vertical, 4) }
                }
            }
            if !inventory.advertisedNames.isEmpty {
                DisclosureGroup("Names advertised over Bonjour") {
                    Text("These service names may overlap with the rows above.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(inventory.advertisedNames, id: \.self) { name in
                        Text(name).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if let onScanPorts, !inventory.observations.isEmpty {
                Button("Open local port checks", action: onScanPorts)
                    .font(.subheadline)
            }
        }
    }

    private func row(_ item: WiFiDeviceInventory.Observation) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name ?? (item.isGateway ? "Router" : "Unnamed address")).font(.subheadline.bold())
                Text(item.address + (item.source.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: item.icon).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func scan() {
        guard !isRunning, !discovery.isScanning else { return }
        inventory = nil
        message = nil
        guard IPv4Subnet.activeWiFi() != nil else {
            message = "Connect to Wi-Fi with an IPv4 address, then try again."
            return
        }
        isRunning = true
        Task { @MainActor in
            defer { isRunning = false }
            let path = ExitPath.lastPathChange
            await discovery.scanNetwork()
            guard let observed = await WiFiDeviceInventory.currentDiscovery(), path == ExitPath.lastPathChange else {
                message = "The network changed. Look for devices again."
                return
            }
            scanPath = path
            inventory = observed
        }
    }
}
