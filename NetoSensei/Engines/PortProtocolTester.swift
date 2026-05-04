//
//  PortProtocolTester.swift
//  NetoSensei
//
//  Port & Protocol Testing - Detect port-level blocking
//  Critical for understanding WHY certain services are slow (common in China)
//

import Foundation
import Network

// MARK: - Port Test Result

struct PortTestResult: Identifiable {
    let id = UUID()
    let port: Int
    let protocolType: ProtocolType
    let name: String
    let status: PortStatus
    let latency: Double?  // ms
    let details: String?

    enum ProtocolType: String {
        case tcp = "TCP"
        case udp = "UDP"
    }

    enum PortStatus: String {
        case working = "Working"
        case blocked = "Blocked"
        case slow = "Slow"
        case timeout = "Timeout"
        case unknown = "Unknown"

        var icon: String {
            switch self {
            case .working: return "checkmark.circle.fill"
            case .blocked: return "xmark.circle.fill"
            case .slow: return "exclamationmark.triangle.fill"
            case .timeout: return "clock.fill"
            case .unknown: return "questionmark.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .working: return "green"
            case .blocked: return "red"
            case .slow: return "yellow"
            case .timeout: return "orange"
            case .unknown: return "gray"
            }
        }
    }
}

// MARK: - Port Protocol Test Suite

struct PortProtocolTestSuite {
    let timestamp: Date
    let results: [PortTestResult]
    let overallStatus: OverallStatus
    let blockedPorts: [PortTestResult]
    let slowPorts: [PortTestResult]
    let recommendations: [String]

    enum OverallStatus: String {
        case allClear = "All Clear"
        case someBlocked = "Some Ports Blocked"
        case severeBlocking = "Severe Blocking"
        case unknown = "Unknown"
    }

    var summary: String {
        let working = results.filter { $0.status == .working }.count
        let blocked = results.filter { $0.status == .blocked }.count
        let slow = results.filter { $0.status == .slow }.count

        return "\(working) working, \(blocked) blocked, \(slow) slow"
    }
}

// MARK: - Port Protocol Tester

actor PortProtocolTester {
    static let shared = PortProtocolTester()

    private init() {}

    // Common ports to test
    private let testPorts: [(port: Int, protocol: PortTestResult.ProtocolType, name: String, host: String)] = [
        (443, .tcp, "HTTPS", "www.google.com"),
        (80, .tcp, "HTTP", "www.apple.com"),
        (53, .tcp, "DNS (TCP)", "8.8.8.8"),
        (53, .udp, "DNS (UDP)", "8.8.8.8"),
        (22, .tcp, "SSH", "github.com"),
        (21, .tcp, "FTP", "ftp.debian.org"),
        (25, .tcp, "SMTP", "smtp.gmail.com"),
        (587, .tcp, "SMTP (Submission)", "smtp.gmail.com"),
        (993, .tcp, "IMAPS", "imap.gmail.com"),
        (1194, .udp, "OpenVPN", "openvpn.net"),
        (51820, .udp, "WireGuard", "1.1.1.1"),
        (8080, .tcp, "HTTP Proxy", "proxy.golang.org"),
    ]

    // MARK: - Feature Flag
    // DISABLED: NWConnection spam was freezing the app
    // Set to true once the freeze issue is fixed
    private static let NWCONNECTION_TESTS_ENABLED = false

    // MARK: - Run Full Test

    func runFullTest() async -> PortProtocolTestSuite {
        // DISABLED: NWConnection tests causing app freeze
        // Creates 12+ connections that flood the main thread
        guard Self.NWCONNECTION_TESTS_ENABLED else {
            debugLog("⚠️ Port test DISABLED — NWConnection causing freeze")
            return PortProtocolTestSuite(
                timestamp: Date(),
                results: [],
                overallStatus: .unknown,
                blockedPorts: [],
                slowPorts: [],
                recommendations: ["Port testing is temporarily disabled"]
            )
        }

        var results: [PortTestResult] = []

        // Test each port
        for portConfig in testPorts {
            let result = await testPort(
                port: portConfig.port,
                protocolType: portConfig.protocol,
                name: portConfig.name,
                host: portConfig.host
            )
            results.append(result)
        }

        // Also test QUIC (UDP 443) separately
        let quicResult = await testQUIC()
        results.append(quicResult)

        // Analyze results
        let blockedPorts = results.filter { $0.status == .blocked }
        let slowPorts = results.filter { $0.status == .slow }

        let overallStatus: PortProtocolTestSuite.OverallStatus
        if blockedPorts.count >= 3 {
            overallStatus = .severeBlocking
        } else if !blockedPorts.isEmpty {
            overallStatus = .someBlocked
        } else {
            overallStatus = .allClear
        }

        let recommendations = generateRecommendations(results: results)

        return PortProtocolTestSuite(
            timestamp: Date(),
            results: results,
            overallStatus: overallStatus,
            blockedPorts: blockedPorts,
            slowPorts: slowPorts,
            recommendations: recommendations
        )
    }

    // MARK: - Test Individual Port

    func testPort(port: Int, protocolType: PortTestResult.ProtocolType, name: String, host: String) async -> PortTestResult {
        let start = Date()
        let timeout: TimeInterval = 5.0

        do {
            let result: (Bool, Double?) = try await withThrowingTaskGroup(of: (Bool, Double?).self) { group -> (Bool, Double?) in
                // Main test task
                group.addTask {
                    await self.performConnection(host: host, port: port, protocolType: protocolType)
                }

                // Timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    return (false, nil)
                }

                guard let result = try await group.next() else {
                    group.cancelAll()
                    return (false, nil)
                }
                group.cancelAll()
                return result
            }
            let success = result.0
            let latency = result.1

            if success {
                let latencyMs = latency ?? Date().timeIntervalSince(start) * 1000

                if latencyMs > 500 {
                    return PortTestResult(
                        port: port,
                        protocolType: protocolType,
                        name: name,
                        status: .slow,
                        latency: latencyMs,
                        details: "Connection slow (\(Int(latencyMs))ms)"
                    )
                } else {
                    return PortTestResult(
                        port: port,
                        protocolType: protocolType,
                        name: name,
                        status: .working,
                        latency: latencyMs,
                        details: nil
                    )
                }
            } else {
                return PortTestResult(
                    port: port,
                    protocolType: protocolType,
                    name: name,
                    status: .timeout,
                    latency: nil,
                    details: "Connection timed out after \(Int(timeout))s"
                )
            }
        } catch {
            return PortTestResult(
                port: port,
                protocolType: protocolType,
                name: name,
                status: .blocked,
                latency: nil,
                details: "Connection failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Connection Test
    // FIXED: NWConnection removed - was causing app freeze

    private func performConnection(host: String, port: Int, protocolType: PortTestResult.ProtocolType) async -> (Bool, Double?) {
        // NWConnection removed - was causing app freeze
        // This function is only called when NWCONNECTION_TESTS_ENABLED = true (currently false)
        return (false, nil)
    }

    // MARK: - QUIC Test
    // FIXED: NWConnection removed - was causing app freeze

    private func testQUIC() async -> PortTestResult {
        // NWConnection removed - was causing app freeze
        // This function is only called when NWCONNECTION_TESTS_ENABLED = true (currently false)
        return PortTestResult(
            port: 443,
            protocolType: .udp,
            name: "QUIC (UDP 443)",
            status: .unknown,
            latency: nil,
            details: "QUIC test disabled"
        )
    }

    // MARK: - Generate Recommendations

    private func generateRecommendations(results: [PortTestResult]) -> [String] {
        var recommendations: [String] = []

        // Check specific blocked ports
        let blocked = results.filter { $0.status == .blocked || $0.status == .timeout }

        for port in blocked {
            switch port.port {
            case 443 where port.protocolType == .udp:
                recommendations.append("QUIC (UDP 443) is blocked. YouTube and Google services may be slower. Try using a VPN that supports QUIC.")
            case 22:
                recommendations.append("SSH (port 22) is blocked. You won't be able to connect to remote servers via SSH. Use a VPN or alternative port.")
            case 1194:
                recommendations.append("OpenVPN port (1194) is blocked. OpenVPN connections will fail. Try TCP mode on port 443 instead.")
            case 51820:
                recommendations.append("WireGuard port (51820) is blocked. WireGuard VPN won't work. Try obfuscated protocols like V2Ray or Trojan.")
            case 25, 587:
                recommendations.append("Email ports are blocked. Sending email from apps may fail. This is common to prevent spam.")
            default:
                break
            }
        }

        // Check slow ports
        let slow = results.filter { $0.status == .slow }
        if !slow.isEmpty {
            recommendations.append("Some ports are slow (>500ms). This may indicate throttling or congestion.")
        }

        // Overall recommendation
        if blocked.count >= 3 {
            recommendations.append("Multiple ports are blocked. You're likely on a restricted network. Consider using obfuscated VPN protocols.")
        }

        if recommendations.isEmpty {
            recommendations.append("All tested ports are accessible. Your network is not blocking common protocols.")
        }

        return recommendations
    }
}
