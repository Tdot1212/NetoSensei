//
//  PortScanner.swift
//  NetoSensei
//
//  Scans devices on the local network for open TCP ports.
//  Identifies services, risk levels, and grabs banners.
//

import Foundation
import Network

// MARK: - Data Models

struct ScannedPort: Identifiable, Hashable {
    let id = UUID()
    let port: UInt16
    let isOpen: Bool
    let service: String
    let risk: PortRisk
    let responseTimeMs: Double?
    let banner: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ScannedPort, rhs: ScannedPort) -> Bool {
        lhs.id == rhs.id
    }

    enum PortRisk: String {
        case safe = "Safe"
        case caution = "Caution"
        case danger = "Danger"
        case info = "Info"
    }
}

struct DeviceScanResult: Identifiable {
    let id = UUID()
    let ipAddress: String
    let hostname: String?
    let openPorts: [ScannedPort]
    let scanDuration: Double
    let timestamp: Date

    var riskLevel: ScannedPort.PortRisk {
        if openPorts.contains(where: { $0.risk == .danger }) { return .danger }
        if openPorts.contains(where: { $0.risk == .caution }) { return .caution }
        if openPorts.isEmpty { return .safe }
        return .info
    }

    var riskSummary: String {
        let dangerous = openPorts.filter { $0.risk == .danger }.count
        let caution = openPorts.filter { $0.risk == .caution }.count
        if dangerous > 0 { return "\(dangerous) high-risk port\(dangerous > 1 ? "s" : "") open" }
        if caution > 0 { return "\(caution) port\(caution > 1 ? "s" : "") need attention" }
        if openPorts.isEmpty { return "No open ports found" }
        return "\(openPorts.count) port\(openPorts.count > 1 ? "s" : "") open"
    }
}

// MARK: - Port Database

struct PortInfo {
    let port: UInt16
    let service: String
    let description: String
    let risk: ScannedPort.PortRisk
}

let commonPorts: [PortInfo] = [
    // Danger — should not be exposed on LAN without reason
    PortInfo(port: 23, service: "Telnet", description: "Unencrypted remote access", risk: .danger),
    PortInfo(port: 111, service: "RPC", description: "Remote Procedure Call", risk: .danger),
    PortInfo(port: 135, service: "MSRPC", description: "Windows RPC", risk: .danger),
    PortInfo(port: 139, service: "NetBIOS", description: "NetBIOS Session", risk: .danger),
    PortInfo(port: 445, service: "SMB", description: "Windows File Sharing", risk: .danger),
    PortInfo(port: 1433, service: "MSSQL", description: "Microsoft SQL Server", risk: .danger),
    PortInfo(port: 1521, service: "Oracle", description: "Oracle Database", risk: .danger),
    PortInfo(port: 2049, service: "NFS", description: "Network File System", risk: .danger),
    PortInfo(port: 3306, service: "MySQL", description: "MySQL Database", risk: .danger),
    PortInfo(port: 3389, service: "RDP", description: "Remote Desktop", risk: .danger),
    PortInfo(port: 5432, service: "PostgreSQL", description: "PostgreSQL Database", risk: .danger),
    PortInfo(port: 5900, service: "VNC", description: "Remote Desktop", risk: .danger),
    PortInfo(port: 5985, service: "WinRM", description: "Windows Remote Mgmt", risk: .danger),
    PortInfo(port: 6379, service: "Redis", description: "Redis Database", risk: .danger),
    PortInfo(port: 27017, service: "MongoDB", description: "MongoDB Database", risk: .danger),

    // Caution — review if intentional
    PortInfo(port: 21, service: "FTP", description: "File Transfer Protocol", risk: .caution),
    PortInfo(port: 25, service: "SMTP", description: "Email server", risk: .caution),
    PortInfo(port: 110, service: "POP3", description: "Email retrieval", risk: .caution),
    PortInfo(port: 137, service: "NetBIOS-NS", description: "NetBIOS Name Service", risk: .caution),
    PortInfo(port: 138, service: "NetBIOS-DGM", description: "NetBIOS Datagram", risk: .caution),
    PortInfo(port: 143, service: "IMAP", description: "Email retrieval", risk: .caution),
    PortInfo(port: 514, service: "Syslog", description: "System logging", risk: .caution),
    PortInfo(port: 515, service: "LPD", description: "Printer service", risk: .caution),
    PortInfo(port: 548, service: "AFP", description: "Apple File Protocol", risk: .caution),
    PortInfo(port: 1080, service: "SOCKS", description: "SOCKS Proxy", risk: .caution),
    PortInfo(port: 1883, service: "MQTT", description: "IoT Messaging", risk: .caution),
    PortInfo(port: 1900, service: "SSDP", description: "UPnP Discovery", risk: .caution),
    PortInfo(port: 5000, service: "UPnP", description: "UPnP Control", risk: .caution),
    PortInfo(port: 5060, service: "SIP", description: "VoIP Signaling", risk: .caution),
    PortInfo(port: 8080, service: "HTTP-Proxy", description: "HTTP Proxy/Admin", risk: .caution),
    PortInfo(port: 8888, service: "HTTP-Alt", description: "Alternative HTTP", risk: .caution),
    PortInfo(port: 9000, service: "Various", description: "Common admin port", risk: .caution),
    PortInfo(port: 9090, service: "WebAdmin", description: "Web admin panel", risk: .caution),

    // Safe — encrypted / expected
    PortInfo(port: 443, service: "HTTPS", description: "Secure web server", risk: .safe),
    PortInfo(port: 993, service: "IMAPS", description: "Secure IMAP", risk: .safe),
    PortInfo(port: 995, service: "POP3S", description: "Secure POP3", risk: .safe),

    // Info — standard services
    PortInfo(port: 22, service: "SSH", description: "Secure Shell", risk: .info),
    PortInfo(port: 53, service: "DNS", description: "Domain Name System", risk: .info),
    PortInfo(port: 80, service: "HTTP", description: "Web server", risk: .info),
    PortInfo(port: 465, service: "SMTPS", description: "Secure email", risk: .info),
    PortInfo(port: 554, service: "RTSP", description: "Streaming media", risk: .info),
    PortInfo(port: 587, service: "Submission", description: "Email submission", risk: .info),
    PortInfo(port: 631, service: "IPP", description: "Internet Printing", risk: .info),
    PortInfo(port: 5353, service: "mDNS", description: "Multicast DNS", risk: .info),
    PortInfo(port: 8000, service: "HTTP-Alt", description: "Alternative HTTP", risk: .info),
    PortInfo(port: 8008, service: "HTTP-Alt", description: "Alternative HTTP", risk: .info),
    PortInfo(port: 8443, service: "HTTPS-Alt", description: "Alternative HTTPS", risk: .info),
    PortInfo(port: 9100, service: "JetDirect", description: "Printer", risk: .info),
    PortInfo(port: 49152, service: "Dynamic", description: "Dynamic port", risk: .info),
    PortInfo(port: 62078, service: "iPhone-Sync", description: "iOS Sync", risk: .info),
]

/// Quick scan: 9 most important ports
let quickScanPorts: [UInt16] = [21, 22, 23, 80, 443, 445, 3389, 5900, 8080]

/// Standard scan: all known ports
let standardScanPorts: [UInt16] = commonPorts.map { $0.port }

// MARK: - Port Scanner Service

@MainActor
class PortScanner: ObservableObject {
    static let shared = PortScanner()

    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var currentPort: UInt16 = 0
    @Published var currentIP: String = ""
    @Published var results: [DeviceScanResult] = []
    @Published var currentDeviceResult: DeviceScanResult?

    private let connectionTimeout: TimeInterval = 1.0
    private let concurrentScans = 20

    private init() {}

    // MARK: - Scan Single Device

    func scanDevice(ip: String, hostname: String? = nil, ports: [UInt16]? = nil) async -> DeviceScanResult {
        return await BackgroundTaskManager.shared.runInBackground(
            id: "portScan",
            name: "Port Scan: \(hostname ?? ip)",
            operation: {
                return await self.performScanDevice(ip: ip, hostname: hostname, ports: ports)
            },
            resultFormatter: { result in
                "\(result.openPorts.count) open ports found"
            }
        )
    }

    private func performScanDevice(ip: String, hostname: String? = nil, ports: [UInt16]? = nil) async -> DeviceScanResult {
        var portsToScan = ports ?? standardScanPorts

        // ISSUE 12 FIX: When scanning the device's own IP, skip privileged ports (0-1023)
        // iOS sandbox blocks connections to privileged ports on localhost
        let localIP = await MainActor.run { NetworkMonitorService.shared.currentStatus.localIP }
        let isSelfScan = (ip == localIP || ip == "127.0.0.1" || ip == "localhost")
        if isSelfScan {
            portsToScan = portsToScan.filter { $0 > 1023 }
        }

        isScanning = true
        progress = 0
        currentIP = ip

        let startTime = Date()
        var openPorts: [ScannedPort] = []

        // Scan in concurrent batches
        let batches = stride(from: 0, to: portsToScan.count, by: concurrentScans).map {
            Array(portsToScan[$0..<min($0 + concurrentScans, portsToScan.count)])
        }

        for (batchIndex, batch) in batches.enumerated() {
            let batchResults = await withTaskGroup(of: ScannedPort?.self, returning: [ScannedPort].self) { group in
                for port in batch {
                    group.addTask { [self] in
                        await self.probePort(ip: ip, port: port)
                    }
                }
                var found: [ScannedPort] = []
                for await result in group {
                    if let p = result, p.isOpen {
                        found.append(p)
                    }
                }
                return found
            }

            openPorts.append(contentsOf: batchResults)
            progress = Double(batchIndex + 1) / Double(batches.count)
        }

        let duration = Date().timeIntervalSince(startTime)

        let result = DeviceScanResult(
            ipAddress: ip,
            hostname: hostname,
            openPorts: openPorts.sorted { $0.port < $1.port },
            scanDuration: duration,
            timestamp: Date()
        )

        currentDeviceResult = result

        if let idx = results.firstIndex(where: { $0.ipAddress == ip }) {
            results[idx] = result
        } else {
            results.append(result)
        }

        isScanning = false
        progress = 1.0
        return result
    }

    // MARK: - Scan Router

    func scanRouter() async -> DeviceScanResult? {
        return await BackgroundTaskManager.shared.runInBackground(
            id: "routerScan",
            name: "Router Port Scan",
            operation: {
                return await self.performScanRouter()
            },
            resultFormatter: { result in
                guard let r = result else { return "No router found" }
                return "\(r.openPorts.count) open ports on router"
            }
        )
    }

    private func performScanRouter() async -> DeviceScanResult? {
        let gatewayIP = NetworkMonitorService.shared.currentStatus.router.gatewayIP ?? "192.168.1.1"

        let routerPorts: [UInt16] = [
            21, 22, 23, 53, 80, 443, 445,
            1900, 5000, 5431,
            8000, 8080, 8443, 8888,
            49152
        ]

        return await performScanDevice(ip: gatewayIP, hostname: "Router", ports: routerPorts)
    }

    func clearResults() {
        results = []
        currentDeviceResult = nil
    }

    // MARK: - Port Probe

    private nonisolated func probePort(ip: String, port: UInt16) async -> ScannedPort? {
        await MainActor.run { currentPort = port }

        let startTime = CFAbsoluteTimeGetCurrent()
        let isOpen = await checkPort(ip: ip, port: port)
        let responseTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        let portInfo = commonPorts.first { $0.port == port }
        let service = portInfo?.service ?? "Unknown"
        let risk = portInfo?.risk ?? .info

        var banner: String? = nil
        if isOpen && [21, 22, 25, 80, 110, 143].contains(port) {
            banner = await grabBanner(ip: ip, port: port)
        }

        return ScannedPort(
            port: port,
            isOpen: isOpen,
            service: service,
            risk: risk,
            responseTimeMs: isOpen ? responseTime : nil,
            banner: banner
        )
    }

    // MARK: - TCP Connect Check

    /// Thread-safe once-guard for NWConnection callbacks.
    private final class OnceFlag: @unchecked Sendable {
        private var _done = false
        private let lock = NSLock()
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if _done { return false }
            _done = true
            return true
        }
    }

    private nonisolated func checkPort(ip: String, port: UInt16) async -> Bool {
        await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(ip)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: false)
                return
            }
            let connection = NWConnection(to: .hostPort(host: host, port: nwPort), using: .tcp)
            let flag = OnceFlag()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if flag.claim() {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    if flag.claim() {
                        continuation.resume(returning: false)
                    }
                case .waiting:
                    // Connection refused / unreachable
                    if flag.claim() {
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + self.connectionTimeout) {
                if flag.claim() {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Banner Grab

    private nonisolated func grabBanner(ip: String, port: UInt16) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let host = NWEndpoint.Host(ip)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: nil)
                return
            }
            let connection = NWConnection(to: .hostPort(host: host, port: nwPort), using: .tcp)
            let flag = OnceFlag()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Some services send banner on connect; HTTP needs a request
                    let probe: Data? = (port == 80)
                        ? "HEAD / HTTP/1.0\r\n\r\n".data(using: .utf8)
                        : nil

                    if let probe = probe {
                        connection.send(content: probe, completion: .idempotent)
                    }

                    connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { data, _, _, _ in
                        guard flag.claim() else { return }
                        connection.cancel()

                        if let data = data,
                           let text = String(data: data, encoding: .utf8) {
                            let firstLine = text
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .components(separatedBy: .newlines)
                                .first ?? ""
                            continuation.resume(returning: String(firstLine.prefix(100)))
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }

                case .failed, .cancelled:
                    if flag.claim() { continuation.resume(returning: nil) }

                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if flag.claim() {
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
