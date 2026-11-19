import Foundation

/// A row represents an observed address. An advertised service name can be
/// associated only when discovery supplied the same address.
struct WiFiDeviceInventory {
    struct Observation: Identifiable {
        let address: String
        let name: String?
        let source: String?
        let icon: String
        let isGateway: Bool
        var id: String { address }
    }

    let observations: [Observation]
    let advertisedNames: [String]
    let excludedAddressCount: Int

    init(tcp: [NetworkDeviceDiscovery.DiscoveredDevice], ssdp: [NetworkDeviceDiscovery.SSDPDevice],
         bonjour: [NetworkDeviceDiscovery.BonjourDevice], gateway: String?, localAddress: String?,
         resolvedNames: [String: Set<String>] = [:]) {
        let allAddresses = Set(tcp.map(\.ipAddress) + ssdp.map(\.ip))
        var infrastructure = Set([gateway, localAddress].compactMap { $0 })
        infrastructure.formUnion(tcp.filter(\.isGateway).map(\.ipAddress))
        excludedAddressCount = allAddresses.intersection(infrastructure).count

        let byAddress = Dictionary(grouping: tcp, by: \.ipAddress)
        let adsByAddress = Dictionary(grouping: ssdp, by: \.ip)
        observations = allAddresses.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { address in
            let probe = byAddress[address]?.first
            let ads = adsByAddress[address] ?? []
            let advertisedDevice = ads.first { Self.clean($0.friendlyName) != nil } ?? ads.first
            let advertised = Self.clean(advertisedDevice?.friendlyName)
            let hostname = Self.clean(probe?.hostname)
            let isGateway = address == gateway || probe?.isGateway == true
            let resolved = resolvedNames[address] ?? []
            let bonjourName = resolved.count == 1 ? resolved.first : nil
            let name = bonjourName ?? advertised ?? hostname
            let bonjourIcon = bonjourName.flatMap { label in
                bonjour.first(where: { Self.clean($0.displayName) == label })?.deviceTypeIcon
            }
            return Observation(address: address, name: name,
                source: bonjourName != nil ? "Bonjour service name" :
                    (advertised != nil ? "Advertised device name" : hostname.map { _ in "Reported hostname" }),
                icon: isGateway ? "wifi.router" : bonjourIcon ?? advertisedDevice?.deviceTypeIcon ?? (name == nil ? "questionmark.circle" : "network"),
                isGateway: isGateway)
        }
        // Service instance names may describe the same host or different hosts
        // with identical names. Display names without adding them to the count.
        advertisedNames = Set(bonjour.compactMap { Self.clean($0.displayName) })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var otherAddressCount: Int { observations.count - excludedAddressCount }

    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let printable = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let trimmed = String(String.UnicodeScalarView(printable)).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(80))
    }

    @MainActor
    static func currentDiscovery() async -> WiFiDeviceInventory? {
        let path = ExitPath.lastPathChange
        let discovery = NetworkDeviceDiscovery.shared
        let tcp = discovery.discoveredDevices
        let ssdp = discovery.uniqueSSDPDevices
        let advertisements = discovery.bonjourDevices
        let names = await resolveNames(advertisements, knownAddresses: Set(tcp.map(\.ipAddress) + ssdp.map(\.ip)))
        guard !Task.isCancelled, path == ExitPath.lastPathChange else { return nil }
        return WiFiDeviceInventory(tcp: tcp, ssdp: ssdp, bonjour: advertisements,
            gateway: DefaultRouteResolver.lanGateway()?.gateway,
            localAddress: IPv4Subnet.activeWiFi().map { IPv4Subnet.string($0.address) }, resolvedNames: names)
    }

    private static func resolveNames(_ advertisements: [NetworkDeviceDiscovery.BonjourDevice],
                              knownAddresses: Set<String>) async -> [String: Set<String>] {
        guard !knownAddresses.isEmpty else { return [:] }
        return await withTaskGroup(of: (String, [String]).self) { group in
            for ad in advertisements.prefix(24) {
                guard let name = WiFiDeviceInventory.clean(ad.displayName) else { continue }
                group.addTask { @MainActor in
                    let resolver = BonjourNameResolution(advertisement: ad)
                    return (name, await resolver.resolve())
                }
            }
            var names: [String: Set<String>] = [:]
            for await (name, addresses) in group {
                for address in addresses where knownAddresses.contains(address) {
                    names[address, default: []].insert(name)
                }
            }
            return names
        }
    }

}
