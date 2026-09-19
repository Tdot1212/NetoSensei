//
//  DiagnosticResult.swift
//  NetoSensei
//
//  Diagnostic test results and recommendations
//

import Foundation

enum IssueSeverity {
    case critical   // Red - blocking issue
    case moderate   // Yellow - degrading performance
    case minor      // Blue - optimization opportunity
    case none       // Green - all good
}

enum IssueCategory {
    case wifi
    case router
    case isp
    case vpn
    case dns
    case device
    case streaming
    case cdn
    case unknown
}

struct DiagnosticTest {
    var name: String
    var result: TestResult
    var latency: Double?
    var details: String
    var timestamp: Date

    enum TestResult {
        case pass
        case fail
        case warning
        case skipped         // not run (e.g. superseded by another check)
        case notApplicable   // cannot apply on this network (e.g. no router on cellular, no VPN in use); never a pass, never a fail
    }
}

struct IdentifiedIssue {
    var category: IssueCategory
    var severity: IssueSeverity
    var title: String
    var description: String
    var technicalDetails: String
    var estimatedImpact: String  // e.g., "Reducing speed by 80%"

    // One-Tap Fix
    var fixAvailable: Bool
    var fixTitle: String?
    var fixDescription: String?
    var fixAction: FixAction?

    enum FixAction {
        case reconnectWiFi
        case restartRouter
        case switchDNS(recommended: String)
        case disconnectVPN
        case reconnectVPN
        case switchVPNServer
        case switchVPNProtocol
        case changeCellular
        case forgetNetwork
        case moveCloserToRouter
        case contactISP
        case changeVPNRegion(recommended: String)
        case openSystemSettings(path: String)
    }
}

struct DiagnosticResult {
    var timestamp: Date
    var testDuration: TimeInterval

    // All tests performed
    var testsPerformed: [DiagnosticTest]

    // Identified issues
    var issues: [IdentifiedIssue]

    // Primary root cause
    var primaryIssue: IdentifiedIssue?

    // Summary
    var summary: String
    var overallStatus: NetworkHealth

    // Recommendations
    var recommendations: [String]

    // One-Tap Fix recommendation
    var oneTapFix: IdentifiedIssue?

    // Network snapshot at time of diagnosis
    var networkSnapshot: NetworkStatus

    var hasCriticalIssues: Bool {
        issues.contains { $0.severity == .critical }
    }

    var hasIssues: Bool {
        !issues.isEmpty
    }

    static func healthy(networkStatus: NetworkStatus) -> DiagnosticResult {
        DiagnosticResult(
            timestamp: Date(),
            testDuration: 0,
            testsPerformed: [],
            issues: [],
            primaryIssue: nil,
            summary: "All systems operational. Your network is performing well.",
            overallStatus: .excellent,
            recommendations: [],
            oneTapFix: nil,
            networkSnapshot: networkStatus
        )
    }
}

// History entry for persistence
struct DiagnosticHistoryEntry: Codable, Identifiable {
    var id: UUID
    var timestamp: Date
    var summary: String
    var issueCount: Int
    var primaryIssueCategory: String
    var overallStatus: String

    // Phase 4 (Trends honesty): network identity so diagnostic trends only
    // compare runs on the same network. All optional — entries written before
    // this field set decode with nil and are segmented as "unknown".
    var connectionType: String? = nil
    var vpnActive: Bool? = nil
    var networkSSID: String? = nil
    var localSubnet: String? = nil
    var publicCountry: String? = nil   // Diagnosis v2 §G: cellular key only

    /// nil for legacy entries with no identity — they never merge with
    /// identified entries.
    var segmentKey: String? {
        guard let type = connectionType, let vpn = vpnActive else { return nil }
        return NetworkSegment.key(connectionType: type, vpnActive: vpn,
                                  ssid: networkSSID, subnet: localSubnet, country: publicCountry)
    }

    /// Field-wise initializer (tests / synthetic entries).
    init(timestamp: Date, summary: String, issueCount: Int, primaryIssueCategory: String,
         overallStatus: String, connectionType: String? = nil, vpnActive: Bool? = nil,
         networkSSID: String? = nil, localSubnet: String? = nil, publicCountry: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.summary = summary
        self.issueCount = issueCount
        self.primaryIssueCategory = primaryIssueCategory
        self.overallStatus = overallStatus
        self.connectionType = connectionType
        self.vpnActive = vpnActive
        self.networkSSID = networkSSID
        self.localSubnet = localSubnet
        self.publicCountry = publicCountry
    }

    /// - Parameter publicCountry: GeoIP country code at the time of the run
    ///   (the caller reads it on the MainActor; NetworkStatus carries none).
    init(from result: DiagnosticResult, publicCountry: String? = nil) {
        self.id = UUID()
        self.timestamp = result.timestamp
        self.summary = result.summary
        self.issueCount = result.issues.count
        self.primaryIssueCategory = result.primaryIssue?.category.description ?? "None"
        self.overallStatus = result.overallStatus.color
        let snap = result.networkSnapshot
        self.connectionType = snap.connectionType?.displayName ?? "Unknown"
        self.vpnActive = snap.vpn.isActive
        self.networkSSID = snap.wifi.ssid
        self.localSubnet = NetworkSegment.subnet(of: snap.localIP)
        self.publicCountry = publicCountry
    }
}

extension IssueCategory: CustomStringConvertible {
    var description: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .router: return "Router"
        case .isp: return "ISP"
        case .vpn: return "VPN"
        case .dns: return "DNS"
        case .device: return "Device"
        case .streaming: return "Streaming"
        case .cdn: return "CDN"
        case .unknown: return "Unknown"
        }
    }
}
