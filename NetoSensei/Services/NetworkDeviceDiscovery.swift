//
//  NetworkDeviceDiscovery.swift
//  NetoSensei
//
//  Local network device discovery using TCP probes, Bonjour/mDNS,
//  SSDP/UPnP multicast, and NetBIOS name queries
//

import Foundation
import Network

@MainActor
class NetworkDeviceDiscovery: ObservableObject {
    static let shared = NetworkDeviceDiscovery()

    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var bonjourDevices: [BonjourDevice] = []
    @Published var ssdpDevices: [SSDPDevice] = []
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var lastScanDate: Date?

    struct DiscoveredDevice: Identifiable, Sendable {
        let id: String // IP address
        let ipAddress: String
        let responseTimeMs: Double
        let isGateway: Bool
        var hostname: String?
        let services: [String]
        var deviceInfo: String?  // Extra info from SSDP/NetBIOS

        init(ipAddress: String, responseTimeMs: Double, isGateway: Bool = false, hostname: String? = nil, services: [String] = [], deviceInfo: String? = nil) {
            self.id = ipAddress
            self.ipAddress = ipAddress
            self.responseTimeMs = responseTimeMs
            self.isGateway = isGateway
            self.hostname = hostname
            self.services = services
            self.deviceInfo = deviceInfo
        }

        /// Icon based on device info / hostname hints
        var deviceIcon: String {
            if isGateway { return "wifi.router" }
            let lower = (hostname ?? "").lowercased() + " " + (deviceInfo ?? "").lowercased()
            if lower.contains("windows") || lower.contains("desktop-") || lower.contains("laptop-") { return "pc" }
            if lower.contains("android") { return "smartphone" }
            if lower.contains("samsung") || lower.contains("galaxy") { return "smartphone" }
            if lower.contains("roku") || lower.contains("firetv") || lower.contains("fire tv") { return "tv" }
            if lower.contains("xbox") { return "gamecontroller" }
            if lower.contains("playstation") || lower.contains("ps5") || lower.contains("ps4") { return "gamecontroller" }
            if lower.contains("printer") { return "printer.fill" }
            if lower.contains("nas") || lower.contains("synology") || lower.contains("qnap") { return "externaldrive.connected.to.line.below" }
            return "desktopcomputer"
        }
    }

    // MARK: - SSDP Device

    struct SSDPDevice: Identifiable, Sendable {
        let id: String  // IP or USN
        let ip: String
        let friendlyName: String?
        let deviceType: String?
        let manufacturer: String?
        let modelName: String?
        let server: String?  // SERVER header (e.g. "Microsoft-Windows/10.0 UPnP/1.0")

        var displayName: String {
            if let name = friendlyName, !name.isEmpty { return name }
            if let model = modelName, !model.isEmpty { return model }
            return ip
        }

        var detectedType: (description: String, icon: String) {
            let lower = [friendlyName, deviceType, manufacturer, modelName, server]
                .compactMap { $0?.lowercased() }.joined(separator: " ")

            // Windows
            if lower.contains("windows") { return ("Windows PC", "pc") }
            // Android
            if lower.contains("android") { return ("Android device", "smartphone") }
            if lower.contains("samsung") && !lower.contains("tv") { return ("Samsung device", "smartphone") }
            // Smart TVs
            if lower.contains("samsung") && lower.contains("tv") { return ("Samsung TV", "tv") }
            if lower.contains("lg") && lower.contains("tv") { return ("LG TV", "tv") }
            if lower.contains("sony") && lower.contains("tv") { return ("Sony TV", "tv") }
            if lower.contains("roku") { return ("Roku", "tv") }
            if lower.contains("fire tv") || lower.contains("firetv") { return ("Fire TV", "tv") }
            if lower.contains("mediarenderer") { return ("Media player", "tv") }
            if lower.contains("mediaserver") { return ("Media server", "server.rack") }
            // Routers / Gateways
            if lower.contains("router") || lower.contains("gateway") || lower.contains("internetgateway") {
                return ("Router", "wifi.router")
            }
            // NAS
            if lower.contains("nas") || lower.contains("synology") || lower.contains("qnap") {
                return ("NAS", "externaldrive.connected.to.line.below")
            }
            // Printers
            if lower.contains("printer") { return ("Printer", "printer.fill") }
            // Game consoles
            if lower.contains("xbox") { return ("Xbox", "gamecontroller") }
            if lower.contains("playstation") { return ("PlayStation", "gamecontroller") }
            // Generic UPnP
            if lower.contains("upnp") || lower.contains("dlna") { return ("UPnP device", "network") }

            return ("Network device", "network")
        }

        var deviceTypeIcon: String { detectedType.icon }
        var serviceDescription: String { detectedType.description }
    }

    struct BonjourDevice: Identifiable, Sendable {
        let id: String
        let name: String
        let serviceType: String
        let domain: String

        /// Clean device name: strip Bonjour encoding like "74A6CDBE4F90@" prefix
        var displayName: String {
            var cleanName = name

            // Strip MAC address prefix (e.g. "74A6CDBE4F90@温欣的MacBook Air" → "温欣的MacBook Air")
            if let atIndex = cleanName.firstIndex(of: "@") {
                let prefix = cleanName[cleanName.startIndex..<atIndex]
                // If prefix looks like a hex MAC address (12 hex chars), strip it
                let hexChars = prefix.filter { $0.isHexDigit }
                if hexChars.count >= 12 && prefix.count <= 17 {
                    cleanName = String(cleanName[cleanName.index(after: atIndex)...])
                }
            }

            return cleanName.isEmpty ? name : cleanName
        }

        /// All service types this device was discovered via (populated during dedup)
        var allServiceTypes: [String] = []

        /// Detect device type and icon from name first, then fall back to service type
        private var detectedType: (description: String, icon: String) {
            let nameLower = displayName.lowercased()
            let allSvcs = allServiceTypes.isEmpty ? [serviceType] : allServiceTypes

            // === Detect from device name (most reliable) ===

            // Mac laptops
            if nameLower.contains("macbook pro") { return ("MacBook Pro", "laptopcomputer") }
            if nameLower.contains("macbook air") { return ("MacBook Air", "laptopcomputer") }
            if nameLower.contains("macbook") { return ("Apple laptop", "laptopcomputer") }

            // Mac desktops
            if nameLower.contains("imac") { return ("iMac", "desktopcomputer") }
            if nameLower.contains("mac mini") { return ("Mac mini", "macmini") }
            if nameLower.contains("mac studio") { return ("Mac Studio", "desktopcomputer") }
            if nameLower.contains("mac pro") { return ("Mac Pro", "desktopcomputer") }

            // iOS devices
            if nameLower.contains("iphone") { return ("iPhone", "iphone") }
            if nameLower.contains("ipad") { return ("iPad", "ipad") }

            // Audio devices
            if nameLower.contains("homepod") { return ("HomePod", "hifispeaker") }
            if nameLower.contains("airpods") { return ("AirPods", "airpodspro") }

            // Apple TV
            if nameLower.contains("apple tv") || nameLower.contains("appletv") { return ("Apple TV", "appletv") }

            // === Fall back to service type ===
            let svcJoined = allSvcs.joined(separator: " ").lowercased()

            if svcJoined.contains("printer") || svcJoined.contains("ipp") { return ("Printer", "printer.fill") }
            if svcJoined.contains("smb") { return ("File Sharing (SMB)", "externaldrive.connected.to.line.below") }
            if svcJoined.contains("afpovertcp") { return ("File Sharing (AFP)", "externaldrive.connected.to.line.below") }
            if svcJoined.contains("airdr") { return ("AirDrop device", "iphone") }
            if svcJoined.contains("homekit") || svcJoined.contains("hap") { return ("HomeKit device", "homekit") }
            if svcJoined.contains("googlecast") { return ("Chromecast", "tv") }
            if svcJoined.contains("spotify") { return ("Spotify Connect", "music.note") }
            if svcJoined.contains("ssh") { return ("Computer (SSH)", "terminal") }
            if svcJoined.contains("http") && !svcJoined.contains("https") { return ("Web Server", "network") }

            // AirPlay/RAOP with unknown name = likely speaker or smart device
            if svcJoined.contains("raop") && !svcJoined.contains("airplay") {
                return ("Speaker", "hifispeaker")
            }
            if svcJoined.contains("airplay") && svcJoined.contains("raop") {
                // Has both AirPlay video + audio = could be Mac, Apple TV, or HomePod
                // Without a recognizable name, default to Apple device
                return ("Apple device", "desktopcomputer")
            }
            if svcJoined.contains("airplay") {
                return ("Apple device", "desktopcomputer")
            }
            if svcJoined.contains("raop") {
                return ("Speaker", "hifispeaker")
            }

            return ("Network device", "network")
        }

        var deviceTypeIcon: String { detectedType.icon }

        var serviceDescription: String { detectedType.description }
    }

    private var activeBrowsers: [NWBrowser] = []

    private init() {}

    var deviceCount: Int { discoveredDevices.count }

    /// Deduplicated Bonjour devices — groups by displayName, merges service types
    var uniqueBonjourDevices: [BonjourDevice] {
        var seen: [String: BonjourDevice] = [:]
        let priority = ["_airplay._tcp", "_hap._tcp", "_smb._tcp", "_printer._tcp", "_ipp._tcp", "_raop._tcp"]

        for device in bonjourDevices {
            let key = device.displayName.lowercased()

            if var existing = seen[key] {
                // Merge: collect all service types, keep higher-priority service as primary
                if !existing.allServiceTypes.contains(device.serviceType) {
                    existing.allServiceTypes.append(device.serviceType)
                }
                // Keep the one with better priority as primary
                let existingPriority = priority.firstIndex(of: existing.serviceType.lowercased()) ?? priority.count
                let newPriority = priority.firstIndex(of: device.serviceType.lowercased()) ?? priority.count
                if newPriority < existingPriority {
                    let mergedServices = existing.allServiceTypes
                    var updated = device
                    updated.allServiceTypes = mergedServices
                    seen[key] = updated
                } else {
                    seen[key] = existing
                }
            } else {
                var newDevice = device
                newDevice.allServiceTypes = [device.serviceType]
                seen[key] = newDevice
            }
        }
        return Array(seen.values).sorted { $0.displayName < $1.displayName }
    }

    /// Deduplicated SSDP devices — groups by IP, keeps most informative entry
    var uniqueSSDPDevices: [SSDPDevice] {
        var seen: [String: SSDPDevice] = [:]
        for device in ssdpDevices {
            if let existing = seen[device.ip] {
                // Keep the one with a friendlyName
                if existing.friendlyName == nil && device.friendlyName != nil {
                    seen[device.ip] = device
                }
            } else {
                seen[device.ip] = device
            }
        }
        return Array(seen.values).sorted { $0.displayName < $1.displayName }
    }

    var totalDeviceCount: Int {
        // All unique IPs across all discovery methods
        var allIPs = Set(discoveredDevices.map { $0.ipAddress })
        // Add SSDP IPs not already found by TCP
        for device in uniqueSSDPDevices {
            allIPs.insert(device.ip)
        }
        // Add Bonjour-only count estimate (Bonjour doesn't provide IPs directly)
        let bonjourOnlyEstimate = max(0, uniqueBonjourDevices.count - allIPs.count)
        return allIPs.count + bonjourOnlyEstimate
    }

    @discardableResult
    func scanNetwork() async -> [DiscoveredDevice] {
        await BackgroundTaskManager.shared.runInBackground(
            id: "deviceDiscovery",
            name: "Network Scan",
            operation: {
                await self.performScanNetwork()
                return self.discoveredDevices
            },
            resultFormatter: { devices in
                "\(devices.count) devices found"
            }
        )
    }

    private func performScanNetwork() async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        discoveredDevices = []
        bonjourDevices = []
        ssdpDevices = []
        stopBonjourBrowsing()

        defer {
            isScanning = false
            lastScanDate = Date()
        }

        // Start Bonjour + SSDP discovery in parallel with TCP scan
        startBonjourBrowsing()

        // Get local IP from NetworkMonitorService or fallback
        guard let localIP = NetworkMonitorService.shared.currentStatus.localIP ?? getLocalIP() else {
            // Still wait a bit for Bonjour results
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            stopBonjourBrowsing()
            scanProgress = 1.0
            return
        }

        let parts = localIP.split(separator: ".")
        guard parts.count == 4 else { return }
        let subnet = "\(parts[0]).\(parts[1]).\(parts[2])"
        let gatewayIP = "\(subnet).1"

        // Launch SSDP discovery concurrently (runs for ~3s)
        let ssdpTask = Task.detached { [weak self] in
            await self?.discoverSSDP() ?? []
        }

        var found: [DiscoveredDevice] = []

        // Batch TCP sweep: 30 hosts per batch, 200ms timeout each
        let batchSize = 30
        for batchStart in stride(from: 1, through: 254, by: batchSize) {
            let batchEnd = min(batchStart + batchSize - 1, 254)

            let batchResults = await withTaskGroup(of: DiscoveredDevice?.self, returning: [DiscoveredDevice].self) { group in
                for hostNum in batchStart...batchEnd {
                    let ip = "\(subnet).\(hostNum)"
                    let isGW = (ip == gatewayIP)
                    group.addTask {
                        await self.probeHostAsync(ip, isGateway: isGW)
                    }
                }

                var results: [DiscoveredDevice] = []
                for await result in group {
                    if let device = result {
                        results.append(device)
                    }
                }
                return results
            }

            found.append(contentsOf: batchResults)
            scanProgress = Double(batchEnd) / 254.0 * 0.7  // TCP = 70% of progress
            discoveredDevices = found.sorted {
                $0.ipAddress.localizedStandardCompare($1.ipAddress) == .orderedAscending
            }
        }

        // Collect SSDP results
        scanProgress = 0.75
        let ssdpResults = await ssdpTask.value
        ssdpDevices = ssdpResults
        debugLog("[Discovery] SSDP found \(ssdpResults.count) device(s)")

        // NetBIOS: query each TCP-discovered IP that lacks a hostname
        scanProgress = 0.80
        let ipsNeedingNames = found.filter { $0.hostname == nil }.map { $0.ipAddress }
        if !ipsNeedingNames.isEmpty {
            let netbiosResults = await queryNetBIOSBatch(ips: ipsNeedingNames)
            // Enrich TCP devices with NetBIOS hostnames
            for i in found.indices {
                if found[i].hostname == nil, let name = netbiosResults[found[i].ipAddress] {
                    found[i].hostname = name
                }
            }
            // Also enrich from SSDP friendlyName
            let ssdpByIP = Dictionary(uniqueKeysWithValues: uniqueSSDPDevices.compactMap { d in
                d.friendlyName != nil ? (d.ip, d) : nil
            })
            for i in found.indices {
                if found[i].hostname == nil, let ssdp = ssdpByIP[found[i].ipAddress] {
                    found[i].hostname = ssdp.friendlyName
                    found[i].deviceInfo = ssdp.serviceDescription
                }
            }

            discoveredDevices = found.sorted {
                $0.ipAddress.localizedStandardCompare($1.ipAddress) == .orderedAscending
            }
        }

        // Allow a brief window for remaining Bonjour results
        scanProgress = 0.90
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        stopBonjourBrowsing()

        scanProgress = 1.0

        // Update persistent device history
        DeviceHistoryManager.shared.onNetworkScanComplete()
    }

    // MARK: - Bonjour/mDNS Discovery

    private func startBonjourBrowsing() {
        let serviceTypes = [
            "_airplay._tcp",
            "_raop._tcp",
            "_printer._tcp",
            "_ipp._tcp",
            "_smb._tcp",
            "_afpovertcp._tcp",
            "_http._tcp",
            "_ssh._tcp",
            "_googlecast._tcp",
            "_spotify-connect._tcp",
            "_hap._tcp"
        ]

        for serviceType in serviceTypes {
            let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: "local.")
            let browser = NWBrowser(for: descriptor, using: .tcp)

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    for result in results {
                        if case .service(let name, let type, let domain, _) = result.endpoint {
                            let device = BonjourDevice(
                                id: "\(name)-\(type)",
                                name: name,
                                serviceType: type,
                                domain: domain
                            )
                            if !self.bonjourDevices.contains(where: { $0.id == device.id }) {
                                self.bonjourDevices.append(device)
                            }
                        }
                    }
                }
            }

            browser.stateUpdateHandler = { _ in }
            browser.start(queue: .global(qos: .utility))
            activeBrowsers.append(browser)
        }
    }

    private func stopBonjourBrowsing() {
        for browser in activeBrowsers {
            browser.cancel()
        }
        activeBrowsers.removeAll()
    }

    // MARK: - TCP Probe (runs on GCD to avoid blocking cooperative thread pool)

    nonisolated private func probeHostAsync(_ ip: String, isGateway: Bool) async -> DiscoveredDevice? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = self.probeHostBlocking(ip, isGateway: isGateway)
                continuation.resume(returning: result)
            }
        }
    }

    /// TCP connect to port 80 with 200ms timeout using non-blocking socket + poll()
    nonisolated private func probeHostBlocking(_ ip: String, isGateway: Bool) -> DiscoveredDevice? {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        // Set non-blocking
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(80).bigEndian
        inet_pton(AF_INET, ip, &addr.sin_addr)

        let start = CFAbsoluteTimeGetCurrent()

        let connectResult = withUnsafeMutablePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            // Connected immediately (unlikely but possible)
            let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
            return DiscoveredDevice(ipAddress: ip, responseTimeMs: latency, isGateway: isGateway)
        }

        guard errno == EINPROGRESS else { return nil }

        // Wait for connection result with poll()
        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pfd, 1, 200) // 200ms timeout

        if pollResult > 0 {
            var error: Int32 = 0
            var errorLen = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(sock, SOL_SOCKET, SO_ERROR, &error, &errorLen)

            if error == 0 || error == ECONNREFUSED {
                // error == 0: port open (connected)
                // ECONNREFUSED: host is UP, port closed
                let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
                return DiscoveredDevice(ipAddress: ip, responseTimeMs: latency, isGateway: isGateway)
            }
            // EHOSTUNREACH, ENETUNREACH = host is DOWN
        }
        // Timeout = host not responding

        return nil
    }

    // MARK: - SSDP/UPnP Discovery

    /// Send M-SEARCH multicast to 239.255.255.250:1900 and collect responses
    nonisolated private func discoverSSDP() async -> [SSDPDevice] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let results = self.performSSDPSearch()
                continuation.resume(returning: results)
            }
        }
    }

    nonisolated private func performSSDPSearch() -> [SSDPDevice] {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return [] }
        defer { close(sock) }

        // Allow address reuse
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Set receive timeout to 3 seconds
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // SSDP M-SEARCH request
        let mSearch = [
            "M-SEARCH * HTTP/1.1\r\n",
            "HOST: 239.255.255.250:1900\r\n",
            "MAN: \"ssdp:discover\"\r\n",
            "MX: 3\r\n",
            "ST: ssdp:all\r\n",
            "\r\n"
        ].joined()

        // Send to multicast address
        var destAddr = sockaddr_in()
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = UInt16(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &destAddr.sin_addr)

        let sendData = Array(mSearch.utf8)
        _ = withUnsafePointer(to: &destAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                sendto(sock, sendData, sendData.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        // Collect responses for up to 3 seconds
        var devices: [SSDPDevice] = []
        var seenIPs = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let deadline = CFAbsoluteTimeGetCurrent() + 3.0

        while CFAbsoluteTimeGetCurrent() < deadline {
            let bytesRead = withUnsafeMutablePointer(to: &srcAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    recvfrom(sock, &buffer, buffer.count, 0, sockaddrPtr, &srcLen)
                }
            }

            guard bytesRead > 0 else { break }

            // Extract source IP
            var ipStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addrCopy = srcAddr.sin_addr
            inet_ntop(AF_INET, &addrCopy, &ipStr, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: ipStr)

            let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
            let headers = parseSSDPHeaders(response)

            let server = headers["SERVER"] ?? headers["server"]
            let location = headers["LOCATION"] ?? headers["location"]
            let st = headers["ST"] ?? headers["st"]
            let usn = headers["USN"] ?? headers["usn"]

            // Use a unique key to avoid duplicates from the same device
            let deviceKey = usn ?? "\(ip)-\(st ?? "")"
            if seenIPs.contains(deviceKey) { continue }
            seenIPs.insert(deviceKey)

            // Try to fetch device description XML for friendlyName
            var friendlyName: String? = nil
            var manufacturer: String? = nil
            var modelName: String? = nil
            var deviceType: String? = st

            if let loc = location, let url = URL(string: loc) {
                if let xmlInfo = fetchSSDPDeviceDescription(url: url) {
                    friendlyName = xmlInfo.friendlyName
                    manufacturer = xmlInfo.manufacturer
                    modelName = xmlInfo.modelName
                    if let dt = xmlInfo.deviceType { deviceType = dt }
                }
            }

            devices.append(SSDPDevice(
                id: deviceKey,
                ip: ip,
                friendlyName: friendlyName,
                deviceType: deviceType,
                manufacturer: manufacturer,
                modelName: modelName,
                server: server
            ))
        }

        return devices
    }

    /// Parse SSDP HTTP-like response headers
    nonisolated private func parseSSDPHeaders(_ response: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in response.components(separatedBy: "\r\n") {
            if let colonRange = line.range(of: ":") {
                let key = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    headers[key] = value
                }
            }
        }
        return headers
    }

    /// Fetch and parse UPnP device description XML (lightweight, 2s timeout)
    nonisolated private func fetchSSDPDeviceDescription(url: URL) -> (friendlyName: String?, manufacturer: String?, modelName: String?, deviceType: String?)? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        let session = URLSession(configuration: config)

        var result: (String?, String?, String?, String?)? = nil
        let semaphore = DispatchSemaphore(value: 0)

        let task = session.dataTask(with: url) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data, let xml = String(data: data, encoding: .utf8) else { return }

            let friendlyName = self.extractXMLValue(xml, tag: "friendlyName")
            let manufacturer = self.extractXMLValue(xml, tag: "manufacturer")
            let modelName = self.extractXMLValue(xml, tag: "modelName")
            let deviceType = self.extractXMLValue(xml, tag: "deviceType")
            result = (friendlyName, manufacturer, modelName, deviceType)
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.5)
        session.invalidateAndCancel()
        return result
    }

    /// Simple XML tag value extraction (no full XML parser needed for UPnP)
    nonisolated private func extractXMLValue(_ xml: String, tag: String) -> String? {
        let open = "<\(tag)>"
        let closeTag = "</\(tag)>"
        guard let openRange = xml.range(of: open),
              let closeRange = xml.range(of: closeTag, range: openRange.upperBound..<xml.endIndex) else {
            return nil
        }
        let value = String(xml[openRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - NetBIOS Name Query (UDP port 137)

    /// Query multiple IPs for NetBIOS names concurrently
    nonisolated private func queryNetBIOSBatch(ips: [String]) async -> [String: String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var results: [String: String] = [:]
                let lock = NSLock()

                DispatchQueue.concurrentPerform(iterations: ips.count) { index in
                    let ip = ips[index]
                    if let name = self.queryNetBIOSName(ip: ip) {
                        lock.lock()
                        results[ip] = name
                        lock.unlock()
                    }
                }

                continuation.resume(returning: results)
            }
        }
    }

    /// Send a NetBIOS Name Service query to get the machine's hostname
    nonisolated private func queryNetBIOSName(ip: String) -> String? {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        // Set receive timeout to 500ms
        var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // NetBIOS Node Status Request packet
        // Transaction ID (2 bytes) + Flags (2) + Questions (2) + Answer/Auth/Add (6)
        // Question: NBSTAT query for "*" (wildcard) encoded in NetBIOS name encoding
        var packet: [UInt8] = [
            // Transaction ID
            0x00, 0x01,
            // Flags: Standard query, no recursion
            0x00, 0x00,
            // Questions: 1
            0x00, 0x01,
            // Answer RRs: 0
            0x00, 0x00,
            // Authority RRs: 0
            0x00, 0x00,
            // Additional RRs: 0
            0x00, 0x00,
            // Query Name: NetBIOS-encoded "*" (CKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA)
            // Length-prefixed: 0x20 = 32 bytes
            0x20,
            // "* " padded to 16 bytes, each byte encoded as two bytes:
            // '*' = 0x2A → 0x43, 0x4B
            // ' ' = 0x20 → 0x43, 0x41 (repeated 15 times)
            0x43, 0x4B,  // *
            0x43, 0x41, 0x43, 0x41, 0x43, 0x41, 0x43, 0x41,  // spaces
            0x43, 0x41, 0x43, 0x41, 0x43, 0x41, 0x43, 0x41,
            0x43, 0x41, 0x43, 0x41, 0x43, 0x41, 0x43, 0x41,
            0x43, 0x41, 0x43, 0x41, 0x43, 0x41,
            // Null terminator
            0x00,
            // Query Type: NBSTAT (0x0021)
            0x00, 0x21,
            // Query Class: IN (0x0001)
            0x00, 0x01
        ]

        var destAddr = sockaddr_in()
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = UInt16(137).bigEndian
        inet_pton(AF_INET, ip, &destAddr.sin_addr)

        // Send the query
        let sent = withUnsafePointer(to: &destAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                sendto(sock, &packet, packet.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent > 0 else { return nil }

        // Receive response
        var buffer = [UInt8](repeating: 0, count: 1024)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let bytesRead = withUnsafeMutablePointer(to: &srcAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                recvfrom(sock, &buffer, buffer.count, 0, sockaddrPtr, &srcLen)
            }
        }

        guard bytesRead > 57 else { return nil }  // Minimum valid NBSTAT response

        // Parse response: skip header (12 bytes) + question echo + answer header
        // The answer section starts after the header. The name count is at offset
        // after the answer name + TTL + data length.
        // For NBSTAT, we need to find the number of names and extract the first one.

        return parseNetBIOSResponse(buffer: buffer, length: bytesRead)
    }

    /// Parse NetBIOS Node Status Response to extract the machine name
    nonisolated private func parseNetBIOSResponse(buffer: [UInt8], length: Int) -> String? {
        // Skip the 12-byte header
        var offset = 12

        // Skip the question name (encoded name)
        while offset < length && buffer[offset] != 0 {
            let labelLen = Int(buffer[offset])
            offset += labelLen + 1
        }
        offset += 1  // skip null terminator

        // Skip question type (2) and class (2)
        offset += 4

        // Now we're at the answer section
        // Skip the answer name (usually a pointer 0xC00C or encoded)
        if offset + 2 <= length && buffer[offset] & 0xC0 == 0xC0 {
            offset += 2  // pointer (2 bytes)
        } else {
            while offset < length && buffer[offset] != 0 {
                let labelLen = Int(buffer[offset])
                offset += labelLen + 1
            }
            offset += 1
        }

        // Skip answer type (2) + class (2) + TTL (4) + data length (2)
        offset += 10

        guard offset < length else { return nil }

        // Number of names
        let nameCount = Int(buffer[offset])
        offset += 1

        guard nameCount > 0, offset + 18 <= length else { return nil }

        // Each name entry: 15-byte name + 1-byte suffix + 2-byte flags
        // Find the first entry with suffix 0x00 (workstation) or 0x20 (file server)
        for _ in 0..<nameCount {
            guard offset + 18 <= length else { break }

            // Extract 15-byte name
            let nameBytes = Array(buffer[offset..<(offset + 15)])
            let suffix = buffer[offset + 15]
            // Flags at offset+16 and offset+17
            let flags = UInt16(buffer[offset + 16]) << 8 | UInt16(buffer[offset + 17])
            let isGroup = (flags & 0x8000) != 0

            offset += 18

            // We want the unique (non-group) workstation name (suffix 0x00)
            if suffix == 0x00 && !isGroup {
                if let name = String(bytes: nameBytes, encoding: .ascii)?
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) {
                    if !name.isEmpty {
                        return name
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Helpers

    nonisolated private func getLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee, let addr = interface.ifa_addr else { continue }
            if addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST)
                    return String(cString: hostname)
                }
            }
        }
        return nil
    }
}
