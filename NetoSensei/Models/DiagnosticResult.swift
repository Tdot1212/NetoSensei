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
        case skipped
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

    init(from result: DiagnosticResult) {
        self.id = UUID()
        self.timestamp = result.timestamp
        self.summary = result.summary
        self.issueCount = result.issues.count
        self.primaryIssueCategory = result.primaryIssue?.category.description ?? "None"
        self.overallStatus = result.overallStatus.color
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
