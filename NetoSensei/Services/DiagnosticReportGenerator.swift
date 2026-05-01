//
//  DiagnosticReportGenerator.swift
//  NetoSensei
//
//  Generates formatted diagnostic reports for sharing
//

import Foundation

@MainActor
class DiagnosticReportGenerator {

    static let shared = DiagnosticReportGenerator()

    private init() {}

    /// Generate a comprehensive network diagnostic report
    func generateReport(
        diagnostic: DiagnosticResult?,
        speedTest: SpeedTestResult?,
        vpnInfo: SmartVPNDetector.VPNDetectionResult?,
        analysis: RootCauseAnalyzer.Analysis?,
        networkStatus: NetworkStatus
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .medium

        var report = """
        ═══════════════════════════════════
        NetoSensei Network Diagnostic Report
        Generated: \(dateFormatter.string(from: Date()))
        ═══════════════════════════════════

        """

        // Health Score Section
        if let analysis = analysis {
            report += """
            HEALTH SCORE: \(analysis.healthScore)/100
            ROOT CAUSE: \(analysis.primaryProblem.rawValue)
            SEVERITY: \(severityLabel(analysis.severity))

            """
        }

        // Network Metrics Section
        report += """
        ─── NETWORK METRICS ───

        """

        // Connection Type
        if let connectionType = networkStatus.connectionType {
            report += "Connection Type:    \(connectionType.displayName)\n"
        }

        // Router/Gateway
        if let gateway = networkStatus.router.gatewayIP {
            report += "Gateway IP:         \(gateway)\n"
        }
        if let gatewayLatency = networkStatus.router.latency {
            report += "Gateway Latency:    \(String(format: "%.0f", gatewayLatency))ms\n"
        }

        // Internet
        if let internetLatency = networkStatus.internet.latencyToExternal {
            report += "Internet Latency:   \(String(format: "%.0f", internetLatency))ms\n"
        }

        // DNS
        if let dnsLatency = networkStatus.dns.latency {
            report += "DNS Latency:        \(String(format: "%.0f", dnsLatency))ms\n"
        }
        if let dnsServer = networkStatus.dns.resolverIP {
            report += "DNS Server:         \(dnsServer)\n"
        }

        // Speed Test Results
        if let speed = speedTest {
            report += """

            ─── SPEED TEST ───
            Download Speed:     \(String(format: "%.1f", speed.downloadSpeed)) Mbps
            Upload Speed:       \(String(format: "%.1f", speed.uploadSpeed)) Mbps
            Ping:               \(String(format: "%.0f", speed.ping))ms
            Jitter:             \(String(format: "%.0f", speed.jitter))ms
            Packet Loss:        \(String(format: "%.1f", speed.packetLoss))%
            Quality:            \(speed.quality.rawValue)
            4K Capable:         \(speed.isStreamingCapable ? "Yes" : "No")

            """
        }

        // VPN Status
        if networkStatus.vpn.isActive || (vpnInfo?.isVPNActive ?? false) {
            report += """

            ─── VPN STATUS ───
            VPN Active:         Yes

            """

            if let overhead = calculateVPNOverhead(networkStatus: networkStatus) {
                report += "VPN Overhead:       \(String(format: "%.0f", overhead))ms\n"
            }

            if let vpn = vpnInfo {
                if let ip = vpn.publicIP {
                    report += "Exit IP:            \(ip)\n"
                }
                if let country = vpn.publicCountry {
                    report += "Exit Country:       \(country)\n"
                }
                if let isp = vpn.publicISP {
                    report += "Exit ISP:           \(isp)\n"
                }
                report += "Confidence:         \(Int(vpn.confidence * 100))%\n"
            }
        }

        // Wi-Fi Info
        if networkStatus.wifi.isConnected {
            report += """

            ─── WI-FI ───

            """
            if let ssid = networkStatus.wifi.ssid {
                report += "Network Name:       \(ssid)\n"
            }
        }

        // Public IP Info
        let geoIP = GeoIPService.shared.currentGeoIP
        if geoIP.publicIP != "0.0.0.0" {
            report += """

            ─── PUBLIC IP ───
            IP Address:         \(geoIP.publicIP)

            """
            if !geoIP.displayLocation.isEmpty {
                report += "Location:           \(geoIP.displayLocation)\n"
            }
            if let isp = geoIP.isp {
                report += "ISP:                \(isp)\n"
            }
            if let asn = geoIP.asn {
                report += "ASN:                \(asn)\n"
            }
        }

        // Recommendations
        if let analysis = analysis {
            report += """

            ─── RECOMMENDATIONS ───
            \(analysis.beginnerExplanation)

            What to do:
            \(analysis.whatToDoNext)

            """
        }

        // Smart Recommendations
        let recommendations = SmartRecommendationEngine.shared.generateRecommendations(
            from: networkStatus,
            speedTest: speedTest,
            diagnosticResult: nil
        )

        if !recommendations.isEmpty {
            report += """

            ─── SMART RECOMMENDATIONS ───

            """
            for (index, rec) in recommendations.prefix(5).enumerated() {
                report += "\(index + 1). \(rec.title)\n"
                report += "   \(rec.description)\n\n"
            }
        }

        // Footer
        report += """

        ═══════════════════════════════════
        Report generated by NetoSensei
        App Version: \(appVersion)
        ═══════════════════════════════════
        """

        return report
    }

    /// Generate a quick speed test report
    func generateSpeedTestReport(speedTest: SpeedTestResult) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        return """
        NetoSensei Speed Test Results
        \(dateFormatter.string(from: speedTest.timestamp))

        ⬇️ Download: \(String(format: "%.1f", speedTest.downloadSpeed)) Mbps
        ⬆️ Upload:   \(String(format: "%.1f", speedTest.uploadSpeed)) Mbps
        📍 Ping:     \(String(format: "%.0f", speedTest.ping))ms
        📊 Jitter:   \(String(format: "%.0f", speedTest.jitter))ms
        📉 Loss:     \(String(format: "%.1f", speedTest.packetLoss))%

        Quality: \(speedTest.quality.rawValue)
        \(speedTest.isStreamingCapable ? "✅ 4K streaming capable" : "❌ Not 4K capable")

        Shared via NetoSensei
        """
    }

    // MARK: - Helpers

    private func severityLabel(_ severity: RootCauseAnalyzer.Analysis.Severity) -> String {
        switch severity {
        case .none: return "No Issues"
        case .minor: return "Minor"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        case .critical: return "Critical"
        }
    }

    private func calculateVPNOverhead(networkStatus: NetworkStatus) -> Double? {
        guard let externalLatency = networkStatus.internet.latencyToExternal,
              let gatewayLatency = networkStatus.router.latency else {
            return nil
        }
        return max(0, externalLatency - gatewayLatency)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
