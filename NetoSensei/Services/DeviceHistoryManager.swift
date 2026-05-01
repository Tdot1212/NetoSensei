//
//  DeviceHistoryManager.swift
//  NetoSensei
//
//  Persistent device history — tracks every device ever seen on the network,
//  records join/leave events, flags new/unknown devices with alerts.
//

import Foundation

// MARK: - Data Models

struct HistoricalDevice: Identifiable, Codable, Equatable {
    let id: String  // Hostname-based or IP-based stable key
    var ipAddress: String
    var hostname: String?
    var vendor: String?
    var deviceType: DeviceCategory
    var firstSeen: Date
    var lastSeen: Date
    var seenCount: Int
    var isTrusted: Bool
    var isCurrentlyConnected: Bool
    var customName: String?
    var notes: String?
    var networkSSID: String?

    var displayName: String {
        if let custom = customName, !custom.isEmpty { return custom }
        if let host = hostname, !host.isEmpty { return host }
        if let vendor = vendor, !vendor.isEmpty { return "\(vendor) Device" }
        return ipAddress
    }

    var isNew: Bool {
        firstSeen.timeIntervalSinceNow > -86400
    }

    var daysSinceLastSeen: Int {
        max(0, Int(-lastSeen.timeIntervalSinceNow / 86400))
    }

    var connectionHistory: String {
        if isCurrentlyConnected { return "Connected now" }
        let d = daysSinceLastSeen
        if d == 0 { return "Seen today" }
        if d == 1 { return "Seen yesterday" }
        if d < 7 { return "Seen \(d) days ago" }
        if d < 30 { return "Seen \(d / 7) weeks ago" }
        return "Seen \(d / 30) months ago"
    }

    enum DeviceCategory: String, Codable, CaseIterable {
        case router = "Router"
        case computer = "Computer"
        case laptop = "Laptop"
        case phone = "Phone"
        case tablet = "Tablet"
        case tv = "Smart TV"
        case speaker = "Speaker"
        case camera = "Camera"
        case printer = "Printer"
        case gaming = "Gaming Console"
        case iot = "IoT Device"
        case unknown = "Unknown"

        var icon: String {
            switch self {
            case .router: return "wifi.router"
            case .computer: return "desktopcomputer"
            case .laptop: return "laptopcomputer"
            case .phone: return "iphone"
            case .tablet: return "ipad"
            case .tv: return "tv"
            case .speaker: return "hifispeaker"
            case .camera: return "video"
            case .printer: return "printer"
            case .gaming: return "gamecontroller"
            case .iot: return "sensor"
            case .unknown: return "questionmark.circle"
            }
        }
    }
}

struct DeviceEvent: Identifiable, Codable {
    let id: UUID
    let deviceId: String
    let eventType: EventType
    let timestamp: Date
    let ipAddress: String
    let networkSSID: String?

    enum EventType: String, Codable {
        case joined = "Joined"
        case left = "Left"
        case firstSeen = "First Seen"
        case ipChanged = "IP Changed"
    }

    init(deviceId: String, eventType: EventType, ipAddress: String, networkSSID: String?) {
        self.id = UUID()
        self.deviceId = deviceId
        self.eventType = eventType
        self.timestamp = Date()
        self.ipAddress = ipAddress
        self.networkSSID = networkSSID
    }
}

struct NetworkAlert: Identifiable, Codable {
    let id: UUID
    let type: AlertType
    let deviceId: String
    let deviceName: String
    let message: String
    let timestamp: Date
    var isRead: Bool

    enum AlertType: String, Codable {
        case newDevice = "New Device"
        case unknownDevice = "Unknown Device"
        case suspiciousActivity = "Suspicious"
        case deviceReturned = "Device Returned"
    }

    init(type: AlertType, deviceId: String, deviceName: String, message: String) {
        self.id = UUID()
        self.type = type
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.message = message
        self.timestamp = Date()
        self.isRead = false
    }
}

// MARK: - Device History Manager

@MainActor
class DeviceHistoryManager: ObservableObject {
    static let shared = DeviceHistoryManager()

    @Published var devices: [HistoricalDevice] = []
    @Published var events: [DeviceEvent] = []
    @Published var alerts: [NetworkAlert] = []
    @Published var unreadAlertCount: Int = 0

    // Settings
    @Published var alertOnNewDevices: Bool = true
    @Published var alertOnUnknownDevices: Bool = true
    @Published var trackDeviceHistory: Bool = true

    private let devicesKey = "deviceHistory_devices"
    private let eventsKey = "deviceHistory_events"
    private let alertsKey = "deviceHistory_alerts"
    private let settingsPrefix = "deviceHistory_settings"

    private let maxEvents = 500
    private let maxAlerts = 100

    private init() {
        loadData()
        loadSettings()
    }

    // MARK: - Process Scan Results

    /// Call after NetworkDeviceDiscovery finishes a scan.
    func onNetworkScanComplete() {
        let discovery = NetworkDeviceDiscovery.shared
        let ssid = NetworkMonitorService.shared.currentStatus.wifi.ssid
        processDiscoveredDevices(discovery.discoveredDevices, currentSSID: ssid)
        processBonjourDevices(discovery.uniqueBonjourDevices, currentSSID: ssid)
    }

    func processDiscoveredDevices(
        _ discoveredDevices: [NetworkDeviceDiscovery.DiscoveredDevice],
        currentSSID: String?
    ) {
        guard trackDeviceHistory else { return }

        let now = Date()
        let currentIPs = Set(discoveredDevices.map { $0.ipAddress })

        // Mark devices not in current scan as disconnected
        for i in devices.indices {
            if devices[i].isCurrentlyConnected && !currentIPs.contains(devices[i].ipAddress) {
                devices[i].isCurrentlyConnected = false
                addEvent(DeviceEvent(
                    deviceId: devices[i].id,
                    eventType: .left,
                    ipAddress: devices[i].ipAddress,
                    networkSSID: currentSSID
                ))
            }
        }

        // Process each discovered device
        for discovered in discoveredDevices {
            let deviceId = stableId(ip: discovered.ipAddress, hostname: discovered.hostname)

            if let idx = devices.firstIndex(where: { $0.id == deviceId }) {
                // Update existing device
                let wasConnected = devices[idx].isCurrentlyConnected
                let oldIP = devices[idx].ipAddress

                devices[idx].lastSeen = now
                devices[idx].seenCount += 1
                devices[idx].isCurrentlyConnected = true
                devices[idx].networkSSID = currentSSID

                if oldIP != discovered.ipAddress {
                    addEvent(DeviceEvent(deviceId: deviceId, eventType: .ipChanged,
                                         ipAddress: discovered.ipAddress, networkSSID: currentSSID))
                    devices[idx].ipAddress = discovered.ipAddress
                }
                if let h = discovered.hostname, devices[idx].hostname == nil {
                    devices[idx].hostname = h
                }

                // Returning device alert
                if !wasConnected && devices[idx].daysSinceLastSeen > 7 && alertOnNewDevices {
                    addEvent(DeviceEvent(deviceId: deviceId, eventType: .joined,
                                         ipAddress: discovered.ipAddress, networkSSID: currentSSID))
                    addAlert(NetworkAlert(
                        type: .deviceReturned, deviceId: deviceId,
                        deviceName: devices[idx].displayName,
                        message: "\(devices[idx].displayName) reconnected after \(devices[idx].daysSinceLastSeen) days"
                    ))
                }
            } else {
                // New device
                let category = categorize(hostname: discovered.hostname, vendor: nil)
                let newDevice = HistoricalDevice(
                    id: deviceId,
                    ipAddress: discovered.ipAddress,
                    hostname: discovered.hostname,
                    vendor: nil,
                    deviceType: category,
                    firstSeen: now, lastSeen: now, seenCount: 1,
                    isTrusted: discovered.isGateway,
                    isCurrentlyConnected: true,
                    customName: nil, notes: nil,
                    networkSSID: currentSSID
                )
                devices.append(newDevice)

                addEvent(DeviceEvent(deviceId: deviceId, eventType: .firstSeen,
                                     ipAddress: discovered.ipAddress, networkSSID: currentSSID))

                if alertOnNewDevices && !discovered.isGateway {
                    addAlert(NetworkAlert(
                        type: .newDevice, deviceId: deviceId,
                        deviceName: newDevice.displayName,
                        message: "New device: \(newDevice.displayName) (\(discovered.ipAddress))"
                    ))
                }
                if alertOnUnknownDevices && category == .unknown {
                    addAlert(NetworkAlert(
                        type: .unknownDevice, deviceId: deviceId,
                        deviceName: newDevice.displayName,
                        message: "Unknown device type: \(discovered.ipAddress)"
                    ))
                }
            }
        }

        saveData()
        updateUnreadCount()
    }

    func processBonjourDevices(
        _ bonjourDevices: [NetworkDeviceDiscovery.BonjourDevice],
        currentSSID: String?
    ) {
        guard trackDeviceHistory else { return }

        for bonjour in bonjourDevices {
            let deviceId = stableId(ip: nil, hostname: bonjour.displayName)

            if let idx = devices.firstIndex(where: { $0.id == deviceId }) {
                if devices[idx].hostname == nil {
                    devices[idx].hostname = bonjour.displayName
                }
                devices[idx].deviceType = categorizeBonjour(bonjour)
                devices[idx].lastSeen = Date()
                devices[idx].isCurrentlyConnected = true
            }
        }
        saveData()
    }

    // MARK: - Device Management

    func trustDevice(_ deviceId: String) {
        guard let i = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        devices[i].isTrusted = true
        saveData()
    }

    func untrustDevice(_ deviceId: String) {
        guard let i = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        devices[i].isTrusted = false
        saveData()
    }

    func setCustomName(_ deviceId: String, name: String?) {
        guard let i = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        devices[i].customName = name
        saveData()
    }

    func setNotes(_ deviceId: String, notes: String?) {
        guard let i = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        devices[i].notes = notes
        saveData()
    }

    func setDeviceType(_ deviceId: String, type: HistoricalDevice.DeviceCategory) {
        guard let i = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        devices[i].deviceType = type
        saveData()
    }

    func deleteDevice(_ deviceId: String) {
        devices.removeAll { $0.id == deviceId }
        events.removeAll { $0.deviceId == deviceId }
        alerts.removeAll { $0.deviceId == deviceId }
        saveData()
        updateUnreadCount()
    }

    // MARK: - Alert Management

    func markAlertRead(_ alertId: UUID) {
        guard let i = alerts.firstIndex(where: { $0.id == alertId }) else { return }
        alerts[i].isRead = true
        saveData()
        updateUnreadCount()
    }

    func markAllAlertsRead() {
        for i in alerts.indices { alerts[i].isRead = true }
        saveData()
        updateUnreadCount()
    }

    func clearAlerts() {
        alerts.removeAll()
        saveData()
        updateUnreadCount()
    }

    // MARK: - Queries

    func eventsForDevice(_ deviceId: String) -> [DeviceEvent] {
        events.filter { $0.deviceId == deviceId }.sorted { $0.timestamp > $1.timestamp }
    }

    var connectedDevices: [HistoricalDevice] {
        devices.filter { $0.isCurrentlyConnected }
    }

    var newDevices: [HistoricalDevice] {
        devices.filter { $0.isNew }
    }

    var untrustedDevices: [HistoricalDevice] {
        devices.filter { !$0.isTrusted }
    }

    func clearAllHistory() {
        devices.removeAll()
        events.removeAll()
        alerts.removeAll()
        saveData()
        updateUnreadCount()
    }

    // MARK: - Settings

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(alertOnNewDevices, forKey: "\(settingsPrefix)_alertNew")
        d.set(alertOnUnknownDevices, forKey: "\(settingsPrefix)_alertUnknown")
        d.set(trackDeviceHistory, forKey: "\(settingsPrefix)_track")
    }

    // MARK: - Private — ID Generation

    private func stableId(ip: String?, hostname: String?) -> String {
        if let h = hostname, !h.isEmpty {
            return h.lowercased().replacingOccurrences(of: " ", with: "_")
        }
        return ip ?? UUID().uuidString
    }

    // MARK: - Private — Device Categorization

    private func categorize(hostname: String?, vendor: String?) -> HistoricalDevice.DeviceCategory {
        let n = (hostname ?? "").lowercased()
        let v = (vendor ?? "").lowercased()

        if n.contains("macbook") || n.contains("laptop") { return .laptop }
        if n.contains("imac") || n.contains("mac-pro") || n.contains("desktop") { return .computer }
        if n.contains("iphone") || n.contains("android") || n.contains("phone")
            || n.contains("galaxy") || n.contains("pixel") { return .phone }
        if n.contains("ipad") || n.contains("tablet") { return .tablet }
        if n.contains("appletv") || n.contains("apple-tv") || n.contains("roku")
            || n.contains("firetv") || n.contains("chromecast") { return .tv }
        if n.contains("homepod") || n.contains("echo") || n.contains("alexa")
            || n.contains("sonos") || n.contains("speaker") { return .speaker }
        if n.contains("camera") || n.contains("ring") || n.contains("nest") { return .camera }
        if n.contains("printer") || n.contains("print") { return .printer }
        if n.contains("playstation") || n.contains("xbox") || n.contains("nintendo") { return .gaming }
        if n.contains("router") || n.contains("gateway") { return .router }

        if v.contains("tp-link") || v.contains("netgear") || v.contains("asus")
            || v.contains("linksys") { return .router }
        if v.contains("raspberry") || v.contains("espressif") { return .iot }

        return .unknown
    }

    private func categorizeBonjour(_ device: NetworkDeviceDiscovery.BonjourDevice) -> HistoricalDevice.DeviceCategory {
        let svc = device.serviceType.lowercased()
        if svc.contains("printer") || svc.contains("ipp") { return .printer }
        if svc.contains("airplay") || svc.contains("raop") {
            let n = device.displayName.lowercased()
            if n.contains("tv") { return .tv }
            if n.contains("homepod") { return .speaker }
            return .computer
        }
        if svc.contains("ssh") || svc.contains("smb") || svc.contains("afp") { return .computer }
        return categorize(hostname: device.displayName, vendor: nil)
    }

    // MARK: - Private — Events / Alerts

    private func addEvent(_ event: DeviceEvent) {
        events.insert(event, at: 0)
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }
    }

    private func addAlert(_ alert: NetworkAlert) {
        alerts.insert(alert, at: 0)
        if alerts.count > maxAlerts {
            alerts = Array(alerts.prefix(maxAlerts))
        }
        updateUnreadCount()
    }

    private func updateUnreadCount() {
        unreadAlertCount = alerts.filter { !$0.isRead }.count
    }

    // MARK: - Private — Persistence

    private func loadData() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: devicesKey),
           let decoded = try? JSONDecoder().decode([HistoricalDevice].self, from: data) {
            devices = decoded
        }
        if let data = d.data(forKey: eventsKey),
           let decoded = try? JSONDecoder().decode([DeviceEvent].self, from: data) {
            events = decoded
        }
        if let data = d.data(forKey: alertsKey),
           let decoded = try? JSONDecoder().decode([NetworkAlert].self, from: data) {
            alerts = decoded
        }
        updateUnreadCount()
    }

    private func saveData() {
        let d = UserDefaults.standard
        if let enc = try? JSONEncoder().encode(devices) { d.set(enc, forKey: devicesKey) }
        if let enc = try? JSONEncoder().encode(events) { d.set(enc, forKey: eventsKey) }
        if let enc = try? JSONEncoder().encode(alerts) { d.set(enc, forKey: alertsKey) }
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        alertOnNewDevices = d.object(forKey: "\(settingsPrefix)_alertNew") as? Bool ?? true
        alertOnUnknownDevices = d.object(forKey: "\(settingsPrefix)_alertUnknown") as? Bool ?? true
        trackDeviceHistory = d.object(forKey: "\(settingsPrefix)_track") as? Bool ?? true
    }
}
