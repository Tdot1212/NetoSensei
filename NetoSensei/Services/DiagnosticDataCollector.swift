//
//  DiagnosticDataCollector.swift
//  NetoSensei
//
//  Collects ALL diagnostic data from every service into a single
//  comprehensive report for AI analysis. Runs every diagnostic tool.
//

import Foundation
import UIKit

// MARK: - Comprehensive Diagnostic Summary

struct ComprehensiveDiagnosticSummary: Codable {
    let collectedAt: Date

    // Network Basics
    let networkType: String
    let isConnected: Bool
    let wifiSSID: String?
    let wifiSignal: String?
    let vpnActive: Bool
    let vpnProtocol: String?
    let publicIP: String?
    let localIP: String?
    let gatewayIP: String?

    // Speed Test Results
    let speedTest: SpeedTestData?

    // Wi-Fi vs Cellular Comparison
    let connectionComparison: ConnectionComparisonData?

    // Device Discovery
    let deviceScan: DeviceScanData?

    // DNS Analysis
    let dnsAnalysis: DNSAnalysisData?

    // Traceroute
    let traceroute: TracerouteData?

    // Port Scan (Router)
    let routerPortScan: PortScanData?

    // TLS Analysis (Key Sites)
    let tlsAnalysis: [TLSSiteData]

    // Digital Footprint (if profile exists)
    let digitalFootprint: FootprintData?

    // Issues Detected
    let issues: [String]
    let warnings: [String]
    let recommendations: [String]

    // MARK: - Nested Data Types

    struct SpeedTestData: Codable {
        let downloadMbps: Double?
        let uploadMbps: Double?
        let latencyMs: Double?
        let jitterMs: Double?
        let quality: String
    }

    struct ConnectionComparisonData: Codable {
        let wifiDownload: Double?
        let wifiUpload: Double?
        let wifiLatency: Double?
        let cellularDownload: Double?
        let cellularUpload: Double?
        let cellularLatency: Double?
        let cellularCarrier: String?
        let cellularTechnology: String?
        let winner: String
        let recommendation: String
    }

    struct DeviceScanData: Codable {
        let totalDevices: Int
        let connectedNow: Int
        let newDevices: Int
        let untrustedDevices: Int
        let unknownDevices: Int
        let deviceList: [DeviceInfo]

        struct DeviceInfo: Codable {
            let name: String
            let ip: String
            let mac: String?
            let type: String
            let isTrusted: Bool
            let isNew: Bool
        }
    }

    struct DNSAnalysisData: Codable {
        let primaryDNS: String?
        let secondaryDNS: String?
        let dnsProvider: String?
        let isEncrypted: Bool
        let encryptionType: String?
        let latencyMs: Double?
        let hasLeak: Bool
        let leakDetails: String?
        let securityRating: String
    }

    struct TracerouteData: Codable {
        let destination: String
        let totalHops: Int
        let totalTimeMs: Double
        let hops: [HopInfo]
        let pathAnalysis: String

        struct HopInfo: Codable {
            let hopNumber: Int
            let ip: String?
            let hostname: String?
            let latencyMs: Double?
            let isp: String?
            let country: String?
            let isTimeout: Bool
        }
    }

    struct PortScanData: Codable {
        let targetIP: String
        let targetName: String
        let openPorts: [PortInfo]
        let closedPortCount: Int
        let securityRating: String
        let risks: [String]

        struct PortInfo: Codable {
            let port: Int
            let service: String
            let riskLevel: String
            let banner: String?
        }
    }

    struct TLSSiteData: Codable {
        let host: String
        let tlsVersion: String?
        let certificateIssuer: String?
        let certificateExpiry: Date?
        let daysUntilExpiry: Int?
        let securityRating: String
        let issues: [String]
    }

    struct FootprintData: Codable {
        let profileName: String
        let sitesScanned: Int
        let sitesWithData: Int
        let removalsPending: Int
        let removalsComplete: Int
        let privacyScore: Int
    }

    // MARK: - Format for AI Context

    var asContextString: String {
        var output = """
        ═══════════════════════════════════════════════════════════════
        NETOSENSEI COMPREHENSIVE NETWORK DIAGNOSTIC REPORT
        Collected: \(collectedAt.formatted(date: .abbreviated, time: .standard))
        ═══════════════════════════════════════════════════════════════

        ┌─────────────────────────────────────────────────────────────┐
        │ NETWORK STATUS                                              │
        └─────────────────────────────────────────────────────────────┘
        Connection: \(isConnected ? "Connected" : "Disconnected")
        Type: \(networkType)
        \(wifiSSID != nil ? "Wi-Fi SSID: \(wifiSSID!)" : "")
        \(wifiSignal != nil ? "Signal: \(wifiSignal!)" : "")
        VPN: \(vpnActive ? "Active (\(vpnProtocol ?? "Unknown"))" : "Not Active")
        Public IP: \(publicIP ?? "Unknown")
        Local IP: \(localIP ?? "Unknown")
        Gateway: \(gatewayIP ?? "Unknown")

        """

        // Speed Test
        if let speed = speedTest {
            output += """

            ┌─────────────────────────────────────────────────────────────┐
            │ SPEED TEST RESULTS                                          │
            └─────────────────────────────────────────────────────────────┘
            Download: \(speed.downloadMbps != nil ? String(format: "%.1f Mbps", speed.downloadMbps!) : "N/A")
            Upload: \(speed.uploadMbps != nil ? String(format: "%.1f Mbps", speed.uploadMbps!) : "N/A")
            Latency: \(speed.latencyMs != nil ? String(format: "%.0f ms", speed.latencyMs!) : "N/A")
            Jitter: \(speed.jitterMs != nil ? String(format: "%.1f ms", speed.jitterMs!) : "N/A")
            Quality: \(speed.quality)

            """
        }

        // Wi-Fi vs Cellular
        if let comparison = connectionComparison {
            output += """

            ┌─────────────────────────────────────────────────────────────┐
            │ WI-FI VS CELLULAR COMPARISON                                │
            └─────────────────────────────────────────────────────────────┘
            Wi-Fi Download: \(comparison.wifiDownload != nil ? String(format: "%.1f Mbps", comparison.wifiDownload!) : "N/A")
            Wi-Fi Upload: \(comparison.wifiUpload != nil ? String(format: "%.1f Mbps", comparison.wifiUpload!) : "N/A")
            Wi-Fi Latency: \(comparison.wifiLatency != nil ? String(format: "%.0f ms", comparison.wifiLatency!) : "N/A")

            Cellular Carrier: \(comparison.cellularCarrier ?? "Unknown")
            Cellular Technology: \(comparison.cellularTechnology ?? "Unknown")
            Cellular Download: \(comparison.cellularDownload != nil ? String(format: "%.1f Mbps", comparison.cellularDownload!) : "N/A")
            Cellular Upload: \(comparison.cellularUpload != nil ? String(format: "%.1f Mbps", comparison.cellularUpload!) : "N/A")
            Cellular Latency: \(comparison.cellularLatency != nil ? String(format: "%.0f ms", comparison.cellularLatency!) : "N/A")

            Winner: \(comparison.winner)
            Recommendation: \(comparison.recommendation)

            """
        }

        // Device Scan
        if let devices = deviceScan {
            output += """

            ┌─────────────────────────────────────────────────────────────┐
            │ DEVICE SCAN                                                 │
            └─────────────────────────────────────────────────────────────┘
            Total Devices Seen: \(devices.totalDevices)
            Currently Connected: \(devices.connectedNow)
            New Devices: \(devices.newDevices)
            Untrusted Devices: \(devices.untrustedDevices)
            Unknown Devices: \(devices.unknownDevices)

            Device List:
            """
            for device in devices.deviceList.prefix(20) {
                let trustStatus = device.isTrusted ? "✓" : (device.isNew ? "NEW" : "?")
                output += "\n  [\(trustStatus)] \(device.name) - \(device.ip) (\(device.type))"
            }
            if devices.deviceList.count > 20 {
                output += "\n  ... and \(devices.deviceList.count - 20) more devices"
            }
            output += "\n"
        }

        // DNS Analysis
        if let dns = dnsAnalysis {
            output += """

            ┌─────────────────────────────────────────────────────────────┐
            │ DNS ANALYSIS                                                │
            └─────────────────────────────────────────────────────────────┘
            Primary DNS: \(dns.primaryDNS ?? "Unknown")
            Secondary DNS: \(dns.secondaryDNS ?? "None")
            Provider: \(dns.dnsProvider ?? "Unknown")
            Encrypted: \(dns.isEncrypted ? "Yes (\(dns.encryptionType ?? "Unknown"))" : "No")
            Latency: \(dns.latencyMs != nil ? String(format: "%.0f ms", dns.latencyMs!) : "N/A")
            DNS Leak: \(dns.hasLeak ? "⚠️ DETECTED - \(dns.leakDetails ?? "")" : "No leak detected")
            Security Rating: \(dns.securityRating)

            """
        }

        // Traceroute
        if let trace = traceroute {
            output += """

            ┌─────────────────────────────────────────────────────────────┐
            │ TRACEROUTE                                                  │
            └─────────────────────────────────────────────────────────────┘
            Destination: \(trace.destination)
            Total Hops: \(trace.totalHops)
            Total Time: \(String(format: "%.0f ms", trace.totalTimeMs))
            Path Analysis: \(trace.pathAnalysis)

            Hop Details:
            """
            for hop in trace.hops {
                let latency = hop.latencyMs != nil ? String(format: "%.0f ms", hop.latencyMs!) : "timeout"
                let location = [hop.isp, hop.country].compactMap { $0 }.joined(separator: ", ")
                output += "\n  \(hop.hopNumber). \(hop.ip ?? "*") (\(latency)) \(location)"
            }
            output += "\n"
        }

        // Router Port Scan
        if let ports = routerPortScan {
            output += """

            ┌─────────────────────────────────────────────────────────────┐
            │ ROUTER PORT SCAN                                            │
            └─────────────────────────────────────────────────────────────┘
            Target: \(ports.targetName) (\(ports.targetIP))
            Open Ports: \(ports.openPorts.count)
            Security Rating: \(ports.securityRating)

            """
            if !ports.openPorts.isEmpty {
                output += "Open Ports:\n"
                for port in ports.openPorts {
                    output += "  - Port \(port.port) (\(port.service)) - Risk: \(port.riskLevel)\n"
                }
            }
            if !ports.risks.isEmpty {
                output += "\nSecurity Risks:\n"
                for risk in ports.risks {
                    output += "  ⚠️ \(risk)\n"
                }
            }
        }

        // TLS Analysis
        if !tlsAnalysis.isEmpty {
            output += """

            ┌─────────────────────────────────────────────────────────────┐
            │ TLS/CERTIFICATE ANALYSIS                                    │
            └─────────────────────────────────────────────────────────────┘
            """
            for site in tlsAnalysis {
                output += "\n\(site.host):"
                output += "\n  TLS Version: \(site.tlsVersion ?? "Unknown")"
                output += "\n  Issuer: \(site.certificateIssuer ?? "Unknown")"
                if let days = site.daysUntilExpiry {
                    output += "\n  Expires: \(days) days"
                }
                output += "\n  Security: \(site.securityRating)"
                if !site.issues.isEmpty {
                    for issue in site.issues {
                        output += "\n  ⚠️ \(issue)"
                    }
                }
            }
            output += "\n"
        }

        // Digital Footprint
        if let footprint = digitalFootprint {
            output += """

            ┌─────────────────────────────────────────────────────────────┐
            │ DIGITAL FOOTPRINT                                           │
            └─────────────────────────────────────────────────────────────┘
            Profile: \(footprint.profileName)
            Sites Scanned: \(footprint.sitesScanned)
            Sites With Data: \(footprint.sitesWithData)
            Removals Pending: \(footprint.removalsPending)
            Removals Complete: \(footprint.removalsComplete)
            Privacy Score: \(footprint.privacyScore)/100

            """
        }

        // Issues, Warnings, Recommendations
        output += """

        ┌─────────────────────────────────────────────────────────────┐
        │ SUMMARY                                                     │
        └─────────────────────────────────────────────────────────────┘
        """

        if !issues.isEmpty {
            output += "\n🔴 ISSUES (\(issues.count)):\n"
            for issue in issues {
                output += "  • \(issue)\n"
            }
        }

        if !warnings.isEmpty {
            output += "\n🟡 WARNINGS (\(warnings.count)):\n"
            for warning in warnings {
                output += "  • \(warning)\n"
            }
        }

        if !recommendations.isEmpty {
            output += "\n💡 RECOMMENDATIONS (\(recommendations.count)):\n"
            for rec in recommendations {
                output += "  • \(rec)\n"
            }
        }

        if issues.isEmpty && warnings.isEmpty {
            output += "\n✅ No critical issues detected.\n"
        }

        output += """

        ═══════════════════════════════════════════════════════════════
        END OF DIAGNOSTIC REPORT
        ═══════════════════════════════════════════════════════════════
        """

        return output
    }
}

// MARK: - Diagnostic Data Collector

@MainActor
class DiagnosticDataCollector: ObservableObject {
    static let shared = DiagnosticDataCollector()

    @Published var isCollecting = false
    @Published var progress: Double = 0
    @Published var currentStep = ""
    @Published var lastSummary: ComprehensiveDiagnosticSummary?

    private init() {}

    // Total number of diagnostic steps
    private let totalSteps = 9

    // MARK: - Run ALL Diagnostics

    func collectFullDiagnostics() async -> ComprehensiveDiagnosticSummary {
        isCollecting = true
        progress = 0

        var issues: [String] = []
        var warnings: [String] = []
        var recommendations: [String] = []

        // ═══════════════════════════════════════════════════════════
        // STEP 1: Basic Network Status
        // ═══════════════════════════════════════════════════════════
        currentStep = "Checking network status..."
        progress = 1.0 / Double(totalSteps)

        let networkStatus = NetworkMonitorService.shared.currentStatus

        let networkType: String
        if networkStatus.wifi.isConnected {
            networkType = "Wi-Fi"
        } else if networkStatus.connectionType == .cellular {
            networkType = "Cellular"
        } else {
            networkType = networkStatus.connectionType?.displayName ?? "None"
        }

        let isConnected = networkStatus.internet.isReachable

        // ═══════════════════════════════════════════════════════════
        // STEP 2: Speed Test (Wi-Fi vs Cellular Comparison)
        // ═══════════════════════════════════════════════════════════
        currentStep = "Running speed test..."
        progress = 2.0 / Double(totalSteps)

        var speedTestData: ComprehensiveDiagnosticSummary.SpeedTestData?
        var connectionComparisonData: ComprehensiveDiagnosticSummary.ConnectionComparisonData?

        if let comparisonResult = await ConnectionComparator.shared.runComparison() {
            let wifi = comparisonResult.wifiResult
            let cell = comparisonResult.cellularResult

            // Speed test data (Wi-Fi primary)
            speedTestData = .init(
                downloadMbps: wifi.downloadSpeedMbps,
                uploadMbps: wifi.uploadSpeedMbps,
                latencyMs: wifi.latencyMs,
                jitterMs: wifi.jitterMs,
                quality: wifi.qualityRating.rawValue
            )

            // Wi-Fi vs Cellular comparison
            let cellInfo = ConnectionComparator.shared.cellularInfo
            connectionComparisonData = .init(
                wifiDownload: wifi.downloadSpeedMbps,
                wifiUpload: wifi.uploadSpeedMbps,
                wifiLatency: wifi.latencyMs,
                cellularDownload: cell.downloadSpeedMbps,
                cellularUpload: cell.uploadSpeedMbps,
                cellularLatency: cell.latencyMs,
                cellularCarrier: cellInfo?.carrierName,
                cellularTechnology: cellInfo?.radioTechnology,
                winner: comparisonResult.recommendation.title,
                recommendation: comparisonResult.useCases.first?.reason ?? "Use Wi-Fi for general usage"
            )

            // Check for issues
            if let download = wifi.downloadSpeedMbps, download < 10 {
                issues.append("Slow download speed: \(String(format: "%.1f", download)) Mbps")
            }
            if let latency = wifi.latencyMs, latency > 100 {
                warnings.append("High latency: \(String(format: "%.0f", latency)) ms")
            }
            if let jitter = wifi.jitterMs, jitter > 30 {
                warnings.append("High jitter: \(String(format: "%.1f", jitter)) ms - may affect video calls")
            }
        }

        // ═══════════════════════════════════════════════════════════
        // STEP 3: Device Discovery
        // ═══════════════════════════════════════════════════════════
        currentStep = "Scanning for devices..."
        progress = 3.0 / Double(totalSteps)

        var deviceScanData: ComprehensiveDiagnosticSummary.DeviceScanData?

        await NetworkDeviceDiscovery.shared.scanNetwork()
        DeviceHistoryManager.shared.onNetworkScanComplete()

        let historyManager = DeviceHistoryManager.shared
        let allDevices = historyManager.devices
        let connectedDevices = historyManager.connectedDevices
        let newDevices = allDevices.filter { $0.isNew }
        let untrustedDevices = allDevices.filter { !$0.isTrusted }
        let unknownDevices = allDevices.filter { $0.deviceType == .unknown }

        let deviceList: [ComprehensiveDiagnosticSummary.DeviceScanData.DeviceInfo] = allDevices.prefix(30).map { device in
            .init(
                name: device.displayName,
                ip: device.ipAddress,
                mac: nil,
                type: device.deviceType.rawValue,
                isTrusted: device.isTrusted,
                isNew: device.isNew
            )
        }

        deviceScanData = .init(
            totalDevices: allDevices.count,
            connectedNow: connectedDevices.count,
            newDevices: newDevices.count,
            untrustedDevices: untrustedDevices.count,
            unknownDevices: unknownDevices.count,
            deviceList: deviceList
        )

        // Check for issues
        if !newDevices.isEmpty {
            warnings.append("\(newDevices.count) new device(s) detected on network")
        }
        if untrustedDevices.count > 5 {
            warnings.append("\(untrustedDevices.count) untrusted devices on network")
        }
        if unknownDevices.count > 3 {
            recommendations.append("Review \(unknownDevices.count) unknown devices and assign types")
        }

        // ═══════════════════════════════════════════════════════════
        // STEP 4: DNS Analysis
        // ═══════════════════════════════════════════════════════════
        currentStep = "Analyzing DNS configuration..."
        progress = 4.0 / Double(totalSteps)

        var dnsAnalysisData: ComprehensiveDiagnosticSummary.DNSAnalysisData?

        let dnsResult = await DNSAnalyzer.shared.runFullAnalysis()

        let leakDetails: String? = dnsResult.hasLeak
            ? dnsResult.leakTestResults.filter { $0.isLeak }.map { "\($0.respondingIP) (\($0.provider.rawValue))" }.joined(separator: ", ")
            : nil

        // FIX (Phase 6.1): pull DNS latency from NetworkMonitorService — its
        // RTT is honest. DNSAnalyzer no longer reports an average latency
        // (its previous value came from a system-resolver short-circuit).
        let dnsLatencyMs = NetworkMonitorService.shared.currentStatus.dns.latency

        dnsAnalysisData = .init(
            primaryDNS: dnsResult.systemDNS.first?.ipAddress,
            secondaryDNS: dnsResult.systemDNS.count > 1 ? dnsResult.systemDNS[1].ipAddress : nil,
            dnsProvider: dnsResult.systemDNS.first?.provider.rawValue,
            isEncrypted: dnsResult.isEncryptedDNS,
            encryptionType: dnsResult.encryptedDNSType?.rawValue,
            latencyMs: dnsLatencyMs,
            hasLeak: dnsResult.hasLeak,
            leakDetails: leakDetails,
            securityRating: dnsResult.securityRating.rawValue
        )

        // Check for issues
        if dnsResult.hasLeak {
            issues.append("DNS leak detected: Your DNS queries may be exposed")
        }
        if !dnsResult.isEncryptedDNS {
            recommendations.append("Enable encrypted DNS (DoH/DoT) for better privacy")
        }
        if let latency = dnsLatencyMs, latency > 100 {
            warnings.append("High DNS latency: \(String(format: "%.0f", latency)) ms")
        }

        // ═══════════════════════════════════════════════════════════
        // STEP 5: Traceroute
        // ═══════════════════════════════════════════════════════════
        currentStep = "Running traceroute..."
        progress = 5.0 / Double(totalSteps)

        var tracerouteData: ComprehensiveDiagnosticSummary.TracerouteData?

        let traceResult = await TracerouteService.shared.runPracticalTraceroute(
            vpnActive: networkStatus.vpn.isActive
        )

        let hops: [ComprehensiveDiagnosticSummary.TracerouteData.HopInfo] = traceResult.hops.map { hop in
            .init(
                hopNumber: hop.hopNumber,
                ip: hop.ipAddress == "*" ? nil : hop.ipAddress,
                hostname: hop.hostname,
                latencyMs: hop.latency > 0 ? hop.latency : nil,
                isp: hop.isp,
                country: hop.location,
                isTimeout: hop.ipAddress == "*"
            )
        }

        // Analyze path
        var pathAnalysis = "Normal path"
        let timeoutCount = traceResult.hops.filter { $0.ipAddress == "*" }.count
        if timeoutCount > traceResult.hops.count / 2 {
            pathAnalysis = "Many timeouts - possible filtering"
            warnings.append("Traceroute shows many timeouts - network may be filtering ICMP")
        }

        tracerouteData = .init(
            destination: traceResult.destination,
            totalHops: traceResult.hops.count,
            totalTimeMs: traceResult.totalLatency,
            hops: hops,
            pathAnalysis: pathAnalysis
        )

        // ═══════════════════════════════════════════════════════════
        // STEP 6: Router Port Scan
        // ═══════════════════════════════════════════════════════════
        currentStep = "Scanning router ports..."
        progress = 6.0 / Double(totalSteps)

        var routerPortScanData: ComprehensiveDiagnosticSummary.PortScanData?

        if let gateway = networkStatus.router.gatewayIP {
            let routerPorts: [UInt16] = [
                21, 22, 23, 53, 80, 443, 445,
                1900, 5000, 5431,
                8000, 8080, 8443, 8888,
                49152
            ]

            let scanResult = await PortScanner.shared.scanDevice(
                ip: gateway,
                hostname: "Router",
                ports: routerPorts
            )

            let openPorts: [ComprehensiveDiagnosticSummary.PortScanData.PortInfo] = scanResult.openPorts.map { port in
                .init(
                    port: Int(port.port),
                    service: port.service,
                    riskLevel: port.risk.rawValue,
                    banner: port.banner
                )
            }

            var risks: [String] = []
            let dangerPorts = scanResult.openPorts.filter { $0.risk == .danger }
            let cautionPorts = scanResult.openPorts.filter { $0.risk == .caution }

            for port in dangerPorts {
                risks.append("Port \(port.port) (\(port.service)) is open - HIGH RISK")
                issues.append("High-risk port \(port.port) (\(port.service)) is open on router")
            }

            for port in cautionPorts {
                risks.append("Port \(port.port) (\(port.service)) is open - Monitor")
            }

            let securityRating: String
            if !dangerPorts.isEmpty {
                securityRating = "Poor"
            } else if !cautionPorts.isEmpty {
                securityRating = "Fair"
            } else if scanResult.openPorts.isEmpty {
                securityRating = "Excellent"
            } else {
                securityRating = "Good"
            }

            let totalScanned = routerPorts.count
            let closedCount = totalScanned - scanResult.openPorts.count

            routerPortScanData = .init(
                targetIP: gateway,
                targetName: "Router",
                openPorts: openPorts,
                closedPortCount: closedCount,
                securityRating: securityRating,
                risks: risks
            )
        }

        // ═══════════════════════════════════════════════════════════
        // STEP 7: TLS Analysis on Key Sites
        // ═══════════════════════════════════════════════════════════
        currentStep = "Checking TLS/certificates..."
        progress = 7.0 / Double(totalSteps)

        var tlsAnalysisData: [ComprehensiveDiagnosticSummary.TLSSiteData] = []

        // Test key sites
        let sitesToTest = ["google.com", "cloudflare.com", "apple.com", "baidu.com"]

        for site in sitesToTest {
            let result = await TLSAnalyzer.shared.analyzeHost(site)

            var daysUntilExpiry: Int?
            let leafCert = result.certificateChain.first
            if let expiry = leafCert?.validTo {
                daysUntilExpiry = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
            }

            let siteData = ComprehensiveDiagnosticSummary.TLSSiteData(
                host: site,
                tlsVersion: result.tlsVersion.version,
                certificateIssuer: leafCert?.issuer,
                certificateExpiry: leafCert?.validTo,
                daysUntilExpiry: daysUntilExpiry,
                securityRating: result.securityRating.rawValue,
                issues: result.issues.map { $0.title }
            )

            tlsAnalysisData.append(siteData)

            // Check for issues
            if result.securityRating == .poor || result.securityRating == .critical {
                warnings.append("TLS issues detected for \(site): \(result.securityRating.rawValue)")
            }
            if let days = daysUntilExpiry, days < 30 {
                warnings.append("Certificate for \(site) expires in \(days) days")
            }
        }

        // ═══════════════════════════════════════════════════════════
        // STEP 8: Digital Footprint (if profile exists)
        // ═══════════════════════════════════════════════════════════
        currentStep = "Checking digital footprint..."
        progress = 8.0 / Double(totalSteps)

        var footprintData: ComprehensiveDiagnosticSummary.FootprintData?

        let footprintScanner = DigitalFootprintScanner.shared
        if let profile = footprintScanner.scanProfile {
            // If no recent scan, run one
            if footprintScanner.scanResults.isEmpty {
                await footprintScanner.startScan(profile: profile)
            }

            footprintData = .init(
                profileName: profile.fullName,
                sitesScanned: footprintScanner.scanResults.count,
                sitesWithData: footprintScanner.foundCount,
                removalsPending: footprintScanner.pendingCount,
                removalsComplete: footprintScanner.removedCount,
                privacyScore: footprintScanner.exposureScore
            )

            if footprintScanner.foundCount > 0 {
                warnings.append("Your data found on \(footprintScanner.foundCount) data broker sites")
            }
            if footprintScanner.exposureScore < 50 {
                recommendations.append("Privacy score is low - consider requesting data removal")
            }
        }

        // ═══════════════════════════════════════════════════════════
        // STEP 9: Compile Final Summary
        // ═══════════════════════════════════════════════════════════
        currentStep = "Compiling report..."
        progress = 9.0 / Double(totalSteps)

        // Add general recommendations
        if !networkStatus.vpn.isActive {
            recommendations.append("Consider using a VPN for enhanced privacy")
        }
        if issues.isEmpty && warnings.isEmpty {
            recommendations.append("Network is healthy - continue regular monitoring")
        }

        let summary = ComprehensiveDiagnosticSummary(
            collectedAt: Date(),
            networkType: networkType,
            isConnected: isConnected,
            wifiSSID: networkStatus.wifi.ssid,
            wifiSignal: nil, // iOS doesn't expose this
            vpnActive: networkStatus.vpn.isActive,
            vpnProtocol: networkStatus.vpn.vpnProtocol,
            publicIP: networkStatus.publicIP,
            localIP: networkStatus.localIP,
            gatewayIP: networkStatus.router.gatewayIP,
            speedTest: speedTestData,
            connectionComparison: connectionComparisonData,
            deviceScan: deviceScanData,
            dnsAnalysis: dnsAnalysisData,
            traceroute: tracerouteData,
            routerPortScan: routerPortScanData,
            tlsAnalysis: tlsAnalysisData,
            digitalFootprint: footprintData,
            issues: issues,
            warnings: warnings,
            recommendations: recommendations
        )

        lastSummary = summary
        progress = 1.0
        currentStep = "Complete"
        isCollecting = false

        return summary
    }

    // MARK: - Quick Diagnostics (same as full for now)

    func collectQuickDiagnostics() async -> ComprehensiveDiagnosticSummary {
        return await collectFullDiagnostics()
    }
}
