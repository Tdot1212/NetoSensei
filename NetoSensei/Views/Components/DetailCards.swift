//
//  DetailCards.swift
//  NetoSensei
//
//  VPN Details, WiFi Details expandable cards, and VPN Leak Test result sheet
//

import SwiftUI

// MARK: - VPN Details Card

struct VPNDetailsCard: View {
    @ObservedObject private var vpnDetector = SmartVPNDetector.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @ObservedObject private var privacyService = PrivacyShieldService.shared
    @State private var isExpanded = false

    var body: some View {
        // Only show when VPN is detected
        let vpnActive = vpnDetector.detectionResult?.isVPNActive ?? false
        if vpnActive {
            VStack(alignment: .leading, spacing: 12) {
                Text("VPN Details")
                    .font(.headline)
                    .padding(.leading, 4)

                CardView {
                    VStack(spacing: 0) {
                        // Header - always visible
                        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } }) {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vpnDetector.detectionResult?.isAuthoritative == true
                                         ? "VPN Active"
                                         : "VPN/Proxy Detected (inferred)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text(vpnDetector.detectionResult?.publicISP ?? "Unknown provider")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        // Expanded details
                        if isExpanded, let result = vpnDetector.detectionResult {
                            Divider()
                                .padding(.vertical, 8)

                            // VPN Health Score
                            vpnHealthSection

                            Divider()
                                .padding(.vertical, 4)

                            VStack(spacing: 10) {
                                detailRow(title: "Server IP", value: result.publicIP ?? "Unknown")
                                detailRow(title: "Server Location", value: formatLocation(city: result.publicCity, country: result.publicCountry))
                                detailRow(title: "ISP / Provider", value: result.publicISP ?? "Unknown")
                                detailRow(title: "IP Type", value: detectIPType(isp: result.publicISP))
                                detailRow(title: "Protocol Hint", value: detectProtocolHint())
                                detailRow(title: "Detection", value: result.isAuthoritative
                                         ? "Confirmed (iOS system)"
                                         : "Inferred (\(Int(result.confidence * 100))% confidence)")
                                if !result.inferenceReasons.isEmpty {
                                    detailRow(title: "Reasoning", value: result.inferenceReasons.joined(separator: "\n"))
                                }
                                detailRow(title: "Tunnel Interface", value: getVPNInterfaceName())

                                // DNS through VPN
                                let dnsInfo = networkMonitor.currentStatus.dns
                                if let resolver = dnsInfo.resolverIP {
                                    detailRow(title: "DNS Server", value: resolver)
                                }

                                // Connection uptime (from detection timestamp)
                                detailRow(title: "Detected", value: formatTimestamp(result.timestamp))

                                // Detection method results
                                if !result.methodResults.isEmpty {
                                    Divider()
                                        .padding(.vertical, 4)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Detection Methods")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)

                                        ForEach(result.methodResults.indices, id: \.self) { index in
                                            let method = result.methodResults[index]
                                            // FIX (Sec Issue 5): Three-state icon — green ✓ for
                                            // genuine positives, gray ⓘ for "platform limitation /
                                            // not applicable" results, gray ⊗ for genuine negatives.
                                            // Previously platform-limit results rendered as ⊗ and
                                            // looked like failures.
                                            let iconName: String = {
                                                if method.detected { return "checkmark.circle.fill" }
                                                if method.isInformational { return "info.circle" }
                                                return "xmark.circle"
                                            }()
                                            let iconColor: Color = method.detected ? .green : .gray
                                            HStack(alignment: .top, spacing: 6) {
                                                Image(systemName: iconName)
                                                    .font(.caption2)
                                                    .foregroundColor(iconColor)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(method.method)
                                                        .font(.caption.bold())
                                                    Text(method.detail)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }

                                // iOS limitations note
                                Divider()
                                    .padding(.vertical, 4)

                                Text("iOS can only detect VPNs registered with the system. Third-party proxy apps and router-level VPNs may not be detected directly.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - VPN Health Score Section

    private var vpnHealthSection: some View {
        let score = vpnHealthScore
        let color = vpnHealthScoreColor

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 5)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.caption.bold())
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(vpnHealthRating)
                    .font(.subheadline.bold())
                    .foregroundColor(color)
                Text(privacyService.lastLeakTestResult != nil
                     ? "Based on leaks, overhead & stability"
                     : "Run VPN Leak Test for full score")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var vpnHealthScore: Int {
        let status = networkMonitor.currentStatus
        var score = 100

        // 1. Latency overhead (VPN adds latency over gateway)
        if let ext = status.internet.latencyToExternal,
           let gw = status.router.latency {
            let overhead = max(0, ext - gw)
            if overhead > 200 { score -= 40 }
            else if overhead > 100 { score -= 25 }
            else if overhead > 50 { score -= 10 }
        }

        // 2. Packet loss from VPN tunnel
        if let loss = status.vpn.packetLoss {
            if loss > 5 { score -= 30 }
            else if loss > 2 { score -= 15 }
            else if loss > 0 { score -= 5 }
        }

        // 3. Leak test results (from PrivacyShieldService)
        if let leakResult = privacyService.lastLeakTestResult,
           leakResult.overallVerdict != .noVPN {
            // DNS leak
            if leakResult.dnsLeak.isLeaking {
                score -= (leakResult.dnsLeak.severity == .critical) ? 25 : 15
            }
            // IP leak
            if leakResult.ipLeak.isLeaking {
                score -= (leakResult.ipLeak.severity == .critical) ? 30 : 20
            }
            // WebRTC leak
            if leakResult.webRTCLeak.isLeaking {
                score -= (leakResult.webRTCLeak.severity == .critical) ? 25 : 15
            }
        }

        return max(0, min(100, score))
    }

    private var vpnHealthRating: String {
        let score = vpnHealthScore
        if score >= 80 { return "Excellent" }
        if score >= 60 { return "Good" }
        if score >= 40 { return "Fair" }
        return "Poor"
    }

    private var vpnHealthScoreColor: Color {
        let score = vpnHealthScore
        if score >= 80 { return .green }
        if score >= 60 { return .blue }
        if score >= 40 { return .yellow }
        return .red
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatLocation(city: String?, country: String?) -> String {
        if let c = city, let co = country, !c.isEmpty {
            return "\(c), \(co)"
        } else if let co = country {
            return co
        }
        return "Unknown"
    }

    private func detectIPType(isp: String?) -> String {
        guard let ispName = isp?.lowercased() else { return "Unknown" }
        let datacenterKeywords = ["hosting", "cloud", "data center", "server", "vps",
                                   "digitalocean", "aws", "azure", "linode", "vultr", "ovh",
                                   "hetzner", "choopa", "m247", "datacamp"]
        if datacenterKeywords.contains(where: { ispName.contains($0) }) {
            return "Datacenter"
        }
        let vpnKeywords = ["vpn", "private", "express", "nord", "surfshark", "proton", "mullvad"]
        if vpnKeywords.contains(where: { ispName.contains($0) }) {
            return "VPN Provider"
        }
        return "Residential"
    }

    private func detectProtocolHint() -> String {
        // Check interface names for protocol hints
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "Unknown" }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        var interfaces: [String] = []
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                interfaces.append(name)
            }
        }

        if interfaces.isEmpty { return "Proxy-based (no tunnel)" }

        // Heuristic: utun interfaces suggest WireGuard or IKEv2
        // ipsec interfaces suggest IPSec
        // ppp suggests L2TP/PPTP
        if interfaces.contains(where: { $0.hasPrefix("ipsec") }) { return "IPSec" }
        if interfaces.contains(where: { $0.hasPrefix("ppp") }) { return "L2TP/PPTP" }
        if interfaces.contains(where: { $0.hasPrefix("utun") }) {
            // Multiple utun could be WireGuard, IKEv2, or proxy app
            return "WireGuard/IKEv2 (utun\(interfaces.count > 1 ? " x\(interfaces.count)" : ""))"
        }
        return interfaces.joined(separator: ", ")
    }

    private func getVPNInterfaceName() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "None" }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        var vpnInterfaces: [String] = []
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                if !vpnInterfaces.contains(name) {
                    vpnInterfaces.append(name)
                }
            }
        }

        return vpnInterfaces.isEmpty ? "None detected" : vpnInterfaces.joined(separator: ", ")
    }

    private func formatTimestamp(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h ago" }
        return "\(Int(elapsed / 86400))d ago"
    }
}

// MARK: - Diagnosis Evidence Cards

struct DiagnosisEvidenceCard: View {
    let diagnosis: NetworkDiagnosis

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnosis Evidence")
                .font(.headline)
                .padding(.leading, 4)

            CardView {
                VStack(spacing: 0) {
                    // Header with scores summary
                    Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } }) {
                        HStack {
                            Image(systemName: "stethoscope")
                                .foregroundColor(.blue)
                                .font(.title2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(diagnosis.scores.summary)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                if let issue = diagnosis.primaryIssue {
                                    Text(issue)
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }

                            Spacer()

                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        Divider()
                            .padding(.vertical, 8)

                        // 5 Scores
                        VStack(spacing: 8) {
                            scoreRow("Local Network", score: diagnosis.scores.localNetwork)
                            scoreRow("Domestic Internet", score: diagnosis.scores.domesticInternet)
                            scoreRow("International", score: diagnosis.scores.internationalInternet)
                            scoreRow("Privacy", score: diagnosis.scores.privacy)
                            scoreRow("Stability", score: diagnosis.scores.stability)
                        }

                        // Explanation Cards
                        if !diagnosis.cards.isEmpty {
                            Divider()
                                .padding(.vertical, 8)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Evidence")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)

                                ForEach(diagnosis.cards) { card in
                                    evidenceCardRow(card)
                                }
                            }
                        }

                        // Probe Results
                        if !diagnosis.probeResults.isEmpty {
                            Divider()
                                .padding(.vertical, 8)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Probes")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)

                                ForEach(diagnosis.probeResults) { probe in
                                    probeRow(probe)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func scoreRow(_ label: String, score: Int) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(scoreColor(score))
                        .frame(width: max(0, geo.size.width * CGFloat(score) / 100), height: 6)
                }
            }
            .frame(height: 6)

            Text("\(score)")
                .font(.caption.bold())
                .foregroundColor(scoreColor(score))
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .blue }
        if score >= 40 { return .yellow }
        if score >= 20 { return .orange }
        return .red
    }

    private func evidenceCardRow(_ card: ExplanationCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: cardResultIcon(card.result))
                    .font(.caption2)
                    .foregroundColor(cardResultColor(card.result))
                // FIX (Sec Issue 6): Prefer displayLabel when provided so two
                // .internet cards (Domestic / Overseas) don't both render as
                // bare "Internet" with opposite verdicts.
                Text(card.displayLabel ?? card.category.rawValue)
                    .font(.caption.bold())

                Spacer()

                // Confidence badge
                Text(card.confidence.label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confidenceColor(card.confidence).opacity(0.2))
                    .foregroundColor(confidenceColor(card.confidence))
                    .cornerRadius(4)
            }

            Text(card.measured)
                .font(.caption2)
                .foregroundColor(.secondary)

            if let limitation = card.iOSLimitation {
                Text(limitation)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }

            Text(card.nextSteps)
                .font(.caption2)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }

    /// Map InterpretationEngine's SCREAMING_SNAKE_CASE probe names to plain-
    /// English labels for the user-facing Diagnosis Evidence row. Pure
    /// presentation transform — the underlying probe data is unchanged.
    private func displayName(for probeName: String) -> String {
        switch probeName {
        case "LOCAL_NETWORK":      return "Local Network"
        case "DOMESTIC_INTERNET":  return "Domestic Internet"
        case "OVERSEAS_INTERNET":  return "Overseas Internet"
        case "SYSTEM_DNS":         return "System DNS"
        case "VPN_STATE":          return "VPN State"
        case "IP_IDENTITY":        return "IP & Location"
        case "SPEED_TEST":         return "Speed Test"
        default:                   return probeName
        }
    }

    private func probeRow(_ probe: ProbeResult) -> some View {
        HStack(spacing: 6) {
            Image(systemName: probe.passed ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption2)
                .foregroundColor(probe.passed ? .green : .red)

            Text(displayName(for: probe.name))
                .font(.caption)
                .frame(width: 80, alignment: .leading)

            Text(probe.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            if let ms = probe.latencyMs {
                Text("\(Int(ms))ms")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
        }
    }

    private func cardResultIcon(_ result: CardResult) -> String {
        switch result {
        case .good: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.circle.fill"
        case .hidden: return "eye.slash.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func cardResultColor(_ result: CardResult) -> Color {
        switch result {
        case .good: return .green
        case .warning: return .yellow
        case .problem: return .red
        case .hidden: return .gray
        case .unknown: return .gray
        }
    }

    private func confidenceColor(_ confidence: CardConfidence) -> Color {
        switch confidence {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        }
    }
}

// MARK: - WiFi Details Card

struct WiFiDetailsCard: View {
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @State private var isExpanded = false

    var body: some View {
        let wifi = networkMonitor.currentStatus.wifi
        guard wifi.isConnected else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("WiFi Details")
                    .font(.headline)
                    .padding(.leading, 4)

                CardView {
                    VStack(spacing: 0) {
                        // Header
                        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } }) {
                            HStack {
                                Image(systemName: "wifi")
                                    .foregroundColor(.blue)
                                    .font(.title2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(wifi.ssid ?? "Connected")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text("Tap for details")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if isExpanded {
                            Divider()
                                .padding(.vertical, 8)

                            let status = networkMonitor.currentStatus

                            VStack(spacing: 10) {
                                // SSID
                                wifiDetailRow(title: "Network Name (SSID)", value: wifi.ssid ?? "Unknown (needs location permission)")

                                // BSSID (Router MAC)
                                wifiDetailRow(title: "Router MAC (BSSID)", value: wifi.bssid ?? "Unknown (needs location permission)")

                                // Local IP
                                wifiDetailRow(title: "Your Local IP", value: status.localIP ?? "Unknown")

                                // Gateway / Router IP
                                wifiDetailRow(title: "Router IP (Gateway)", value: status.router.gatewayIP ?? "Unknown")

                                // Router latency
                                if let latency = status.router.latency {
                                    wifiDetailRow(title: "Router Latency", value: "\(Int(latency))ms")
                                }

                                // DNS Servers
                                if let dns = status.dns.resolverIP {
                                    wifiDetailRow(title: "DNS Server", value: dns)
                                }

                                // DNS Latency
                                if let dnsLatency = status.dns.latency {
                                    wifiDetailRow(title: "DNS Latency", value: "\(Int(dnsLatency))ms")
                                }

                                // IPv6
                                wifiDetailRow(title: "IPv6", value: status.isIPv6Enabled ? "Supported" : "Not available")

                                // Hotspot detection
                                if status.isHotspot {
                                    HStack(spacing: 6) {
                                        Image(systemName: "personalhotspot")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                        Text("Connected via mobile hotspot")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.top, 4)
                                }

                                // Radio Metrics (Not available on iOS)
                                Divider()
                                    .padding(.vertical, 4)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Radio Metrics")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)

                                    wifiUnavailableRow(title: "Signal Strength (RSSI)")
                                    wifiUnavailableRow(title: "Noise Floor")
                                    wifiUnavailableRow(title: "Channel / Frequency Band")
                                    wifiUnavailableRow(title: "Channel Width (20/40/80/160 MHz)")
                                    wifiUnavailableRow(title: "PHY Mode (802.11ac/ax)")
                                    wifiUnavailableRow(title: "TX Rate / Link Speed")
                                    wifiUnavailableRow(title: "MCS Index")
                                    wifiUnavailableRow(title: "Spatial Streams (NSS)")
                                    wifiUnavailableRow(title: "Security Type (WPA2/WPA3)")
                                }

                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("These metrics require CoreWLAN which is macOS-only. Apple does not provide equivalent APIs on iOS.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        )
    }

    private func wifiUnavailableRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("Not available on iOS")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
                .italic()
        }
    }

    private func wifiDetailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - VPN Leak Test Result Sheet

struct VPNLeakTestResultSheet: View {
    let result: VPNLeakTestResult?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if let result = result {
                        // Overall verdict
                        VStack(spacing: 12) {
                            Image(systemName: result.overallVerdict.systemImage)
                                .font(.system(size: 60))
                                .foregroundColor(verdictColor(result.overallVerdict))

                            Text(result.overallVerdict.displayText)
                                .font(.title.bold())
                                .foregroundColor(verdictColor(result.overallVerdict))

                            if result.overallVerdict == .noVPN {
                                Text("Connect to a VPN first, then run this test")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding()

                        if result.overallVerdict != .noVPN {
                            // VPN Server info
                            if let serverIP = result.vpnServerIP {
                                HStack {
                                    Image(systemName: "server.rack")
                                        .foregroundColor(.blue)
                                    Text("VPN Server: \(serverIP)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                            }

                            // Leak check results
                            VStack(spacing: 0) {
                                leakCheckRow(result.dnsLeak)
                                Divider()
                                leakCheckRow(result.ipLeak)
                                Divider()
                                leakCheckRow(result.webRTCLeak)
                            }
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)

                            // DNS servers detected
                            if !result.detectedDNSServers.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("DNS Servers Detected")
                                        .font(.subheadline.bold())

                                    ForEach(result.detectedDNSServers, id: \.self) { server in
                                        HStack {
                                            Image(systemName: "server.rack")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                            Text(server)
                                                .font(.caption.monospaced())
                                        }
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }

                            // Solutions section
                            let solutions = [result.dnsLeak, result.ipLeak, result.webRTCLeak]
                                .compactMap { $0.solution }

                            if !solutions.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recommendations")
                                        .font(.subheadline.bold())

                                    ForEach(solutions.indices, id: \.self) { index in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "lightbulb.fill")
                                                .font(.caption)
                                                .foregroundColor(.yellow)
                                            Text(solutions[index])
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }
                        }

                        Spacer()
                    } else {
                        ProgressView("Running leak test...")
                    }
                }
            }
            .navigationTitle("VPN Leak Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func leakCheckRow(_ check: VPNLeakTestResult.LeakCheck) -> some View {
        HStack {
            Image(systemName: severityIcon(check.severity))
                .foregroundColor(severityColor(check.severity))

            VStack(alignment: .leading, spacing: 2) {
                Text(check.name)
                    .font(.subheadline.bold())
                Text(check.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private func verdictColor(_ verdict: VPNLeakTestResult.Verdict) -> Color {
        switch verdict {
        case .noLeaks: return .green
        case .minorLeaks: return .yellow
        case .majorLeaks: return .red
        case .noVPN: return .gray
        }
    }

    private func severityIcon(_ severity: VPNLeakTestResult.LeakCheck.Severity) -> String {
        switch severity {
        case .safe: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }

    private func severityColor(_ severity: VPNLeakTestResult.LeakCheck.Severity) -> Color {
        switch severity {
        case .safe: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}
