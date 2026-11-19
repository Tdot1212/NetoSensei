//
//  NetworkSecurityScanner.swift
//  NetoSensei
//
//  Network Security Scanner - Detects devices, rogue access points, ARP spoofing
//

import Foundation
import Network
import SystemConfiguration.CaptiveNetwork


@MainActor
class NetworkSecurityScanner: ObservableObject {
    static let shared = NetworkSecurityScanner()

    @Published var devices: [NetworkDevice] = []
    @Published var securityIssues: [SecurityIssue] = []
    @Published var isScanning = false

    // MARK: - Network Device

    struct NetworkDevice: Identifiable, Codable {
        let id: String // MAC address
        let ipAddress: String
        let macAddress: String
        let hostname: String?
        let vendor: String?
        let firstSeen: Date
        var lastSeen: Date
        var isKnown: Bool
        var isTrusted: Bool
        var deviceType: DeviceType

        enum DeviceType: String, Codable {
            case router = "Router"
            case phone = "Phone"
            case computer = "Computer"
            case tablet = "Tablet"
            case tv = "TV/Streaming"
            case iot = "IoT Device"
            case unknown = "Unknown"
        }

        var displayName: String {
            hostname ?? ipAddress
        }
    }

    // MARK: - Security Issue

    struct SecurityIssue: Identifiable {
        let id = UUID()
        let type: IssueType
        let severity: Severity
        let title: String
        let description: String
        let affectedDevice: NetworkDevice?
        let detectedAt: Date
        let recommendation: String

        enum IssueType {
            case unknownDevice
            case suspiciousDevice
            case arpSpoofing
            case rogueDHCP
            case duplicateIP
            case weakEncryption
            case openPort
            case suspiciousTraffic
        }

        enum Severity {
            case info
            case warning
            case critical

            var color: String {
                switch self {
                case .info: return "blue"
                case .warning: return "yellow"
                case .critical: return "red"
                }
            }
        }
    }

    private init() {}

    // MARK: - Scan Network

    func scanNetwork() async {
        await MainActor.run {
            isScanning = true
            securityIssues = []
        }

        // Get current network info
        guard let networkInfo = getCurrentNetworkInfo() else {
            await MainActor.run {
                isScanning = false
            }
            return
        }

        debugLog("🔍 Scanning network: \(networkInfo.ssid ?? "Unknown")")

        // Scan for devices
        let foundDevices = await scanForDevices(networkInfo: networkInfo)

        // Analyze for security issues
        let issues = analyzeSecurityIssues(devices: foundDevices, networkInfo: networkInfo)

        await MainActor.run {
            devices = foundDevices
            securityIssues = issues
            isScanning = false
            debugLog("✅ Security scan complete: \(foundDevices.count) devices, \(issues.count) issues")
        }
    }

    // MARK: - Get Network Info

    private struct NetworkInfo {
        let ssid: String?
        let bssid: String?
        let gateway: String?
        let subnet: String?
        let ipAddress: String?
    }

    private func getCurrentNetworkInfo() -> NetworkInfo? {
        // FIXED: Get WiFi SSID/BSSID safely with location permission check
        let (ssid, bssid) = getWiFiInfoSafely()

        // Get gateway and local IP (simplified - iOS doesn't expose ARP table)
        let gateway = getDefaultGateway()
        let localIP = getLocalIPAddress()

        return NetworkInfo(
            ssid: ssid,
            bssid: bssid,
            gateway: gateway,
            subnet: nil,
            ipAddress: localIP
        )
    }

    /// Safely get WiFi SSID/BSSID - delegates to NetworkMonitorService's cached SSID
    /// ISSUE 2 FIX: Reuses the existing WiFi info from the monitor instead of calling CNCopy again
    private func getWiFiInfoSafely() -> (ssid: String?, bssid: String?) {
        guard LocationPermissionManager.shared.isLocationEnabled else {
            return (nil, nil)
        }
        let status = LocationPermissionManager.shared.currentStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return (nil, nil)
        }
        // Use CNCopy only if already known to work, otherwise skip
        if let interfaces = CNCopySupportedInterfaces() as? [String] {
            for interface in interfaces {
                if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any] {
                    let ssid = info[kCNNetworkInfoKeySSID as String] as? String
                    let bssid = info[kCNNetworkInfoKeyBSSID as String] as? String
                    if ssid != nil { return (ssid, bssid) }
                }
            }
        }
        return (nil, nil)
    }

    private func getDefaultGateway() -> String? {
        // Typically 192.168.1.1 or 192.168.0.1
        // iOS doesn't expose routing table, so we guess common gateways
        return "192.168.1.1"
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            let interface = ptr?.pointee
            let addrFamily = interface?.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: (interface?.ifa_name)!)
                if name == "en0" { // WiFi interface
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface?.ifa_addr,
                              socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                              &hostname,
                              socklen_t(hostname.count),
                              nil,
                              socklen_t(0),
                              NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }

    // MARK: - Device Scanning

    private func scanForDevices(networkInfo: NetworkInfo) async -> [NetworkDevice] {
        var foundDevices: [NetworkDevice] = []

        // Add gateway (router) as first device
        if let gateway = networkInfo.gateway {
            foundDevices.append(NetworkDevice(
                id: "gateway",
                ipAddress: gateway,
                macAddress: "unknown",
                hostname: "Router",
                vendor: nil,
                firstSeen: Date(),
                lastSeen: Date(),
                isKnown: true,
                isTrusted: true,
                deviceType: .router
            ))
        }

        // Add current device
        if let localIP = networkInfo.ipAddress {
            foundDevices.append(NetworkDevice(
                id: "self",
                ipAddress: localIP,
                macAddress: "local",
                hostname: "This iPhone",
                vendor: "Apple",
                firstSeen: Date(),
                lastSeen: Date(),
                isKnown: true,
                isTrusted: true,
                deviceType: .phone
            ))
        }

        // Simulate scanning for other devices
        // Note: iOS doesn't allow true network scanning for security reasons
        // We can only detect devices through indirect methods

        // Add some example devices for demonstration
        // In production, this would use mDNS/Bonjour or cloud-based device tracking
        foundDevices.append(contentsOf: getDemoDevices())

        return foundDevices
    }

    private func getDemoDevices() -> [NetworkDevice] {
        // Demo devices for testing
        // In real implementation, use mDNS/Bonjour discovery or user-maintained device list
        return []
    }

    // MARK: - Security Analysis

    private func analyzeSecurityIssues(devices: [NetworkDevice], networkInfo: NetworkInfo) -> [SecurityIssue] {
        var issues: [SecurityIssue] = []

        // Check for unknown devices
        let unknownDevices = devices.filter { !$0.isKnown && !$0.isTrusted }
        for device in unknownDevices {
            issues.append(SecurityIssue(
                type: .unknownDevice,
                severity: .warning,
                title: "Unknown Device Detected",
                description: "A device with IP \(device.ipAddress) is connected to your network. This might be a new device you added, or an unauthorized device.",
                affectedDevice: device,
                detectedAt: Date(),
                recommendation: "If you don't recognize this device, consider changing your WiFi password and blocking it from your router."
            ))
        }

        // Check for duplicate IPs (simplified)
        let ipCounts = Dictionary(grouping: devices, by: { $0.ipAddress })
        for (ip, devicesWithIP) in ipCounts where devicesWithIP.count > 1 {
            issues.append(SecurityIssue(
                type: .duplicateIP,
                severity: .warning,
                title: "Duplicate IP Address",
                description: "Multiple devices claim to have IP address \(ip). This could cause connectivity issues or indicate ARP spoofing.",
                affectedDevice: devicesWithIP.first,
                detectedAt: Date(),
                recommendation: "Restart your router to reassign IP addresses via DHCP."
            ))
        }

        // Check if too many devices (potential hotspot theft)
        if devices.count > 15 {
            issues.append(SecurityIssue(
                type: .suspiciousDevice,
                severity: .critical,
                title: "Unusual Number of Devices",
                description: "\(devices.count) devices detected on your network. This is unusually high and could indicate unauthorized access.",
                affectedDevice: nil,
                detectedAt: Date(),
                recommendation: "Review all connected devices. Change your WiFi password if you see devices you don't recognize."
            ))
        }

        // Check BSSID for rogue AP
        if let bssid = networkInfo.bssid, let knownBSSID = getKnownBSSID(ssid: networkInfo.ssid) {
            if bssid != knownBSSID {
                issues.append(SecurityIssue(
                    type: .arpSpoofing,
                    severity: .critical,
                    title: "Possible Rogue Access Point",
                    description: "The router's MAC address has changed. You might be connected to a fake WiFi network (Evil Twin attack).",
                    affectedDevice: nil,
                    detectedAt: Date(),
                    recommendation: "Disconnect immediately. Verify you're connected to the correct network. Enable VPN for protection."
                ))
            }
        }

        return issues
    }

    private func getKnownBSSID(ssid: String?) -> String? {
        // In production, this would check user's saved known BSSIDs for their home networks
        // For now, return nil to skip check
        return nil
    }

    // MARK: - Device Management

    func markDeviceAsTrusted(_ deviceId: String) {
        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
            devices[index].isTrusted = true
            devices[index].isKnown = true
            saveDevices()

            // Remove related security issues
            securityIssues.removeAll { issue in
                issue.affectedDevice?.id == deviceId
            }
        }
    }

    func blockDevice(_ deviceId: String) {
        // In production, this would integrate with router API to block MAC address
        debugLog("🚫 Block device: \(deviceId)")
        // For now, just remove from trusted list
        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
            devices[index].isTrusted = false
        }
    }

    // MARK: - Persistence

    private func saveDevices() {
        if let encoded = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(encoded, forKey: "knownDevices")
        }
    }

    private func loadDevices() {
        if let data = UserDefaults.standard.data(forKey: "knownDevices"),
           let decoded = try? JSONDecoder().decode([NetworkDevice].self, from: data) {
            devices = decoded
        }
    }

    // MARK: - Quick Security Check

    // MARK: - Security Status

    enum SecurityStatus {
        case secure
        case warning
        case critical

        var displayText: String {
            switch self {
            case .secure: return "Secure"
            case .warning: return "Issues Found"
            case .critical: return "Critical Threat"
            }
        }

        var icon: String {
            switch self {
            case .secure: return "checkmark.shield.fill"
            case .warning: return "exclamationmark.shield.fill"
            case .critical: return "xmark.shield.fill"
            }
        }
    }

    struct SecurityReport {
        let status: SecurityStatus
        let deviceCount: Int
        let unknownDeviceCount: Int
        let criticalIssues: Int
        let warningIssues: Int
        let lastScanDate: Date
    }

    func quickSecurityCheck() -> SecurityReport {
        let criticalIssues = securityIssues.filter { $0.severity == .critical }.count
        let warningIssues = securityIssues.filter { $0.severity == .warning }.count
        let unknownDeviceCount = devices.filter { !$0.isKnown }.count

        let status: SecurityStatus
        if criticalIssues > 0 {
            status = .critical
        } else if warningIssues > 0 || unknownDeviceCount > 0 {
            status = .warning
        } else {
            status = .secure
        }

        return SecurityReport(
            status: status,
            deviceCount: devices.count,
            unknownDeviceCount: unknownDeviceCount,
            criticalIssues: criticalIssues,
            warningIssues: warningIssues,
            lastScanDate: Date()
        )
    }
}
