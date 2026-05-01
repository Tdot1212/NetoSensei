//
//  SecurityScanResult.swift
//  NetoSensei
//
//  Legacy security scan result model (used by SecurityScanService)
//  Note: Network Security Audit (NetworkSecurityAuditService) is the preferred security check
//

import Foundation

struct SecurityScanResult: Codable, Identifiable {
    let id: UUID
    let timestamp: Date

    // Test Results
    var arpScanResult: ARPScanResult
    var dnsLeakResult: DNSLeakResult
    var webRTCLeakResult: WebRTCLeakResult
    var dpiThrottlingResult: DPIThrottlingResult
    var portScanResult: PortScanResult
    var tlsFingerprintResult: TLSFingerprintResult

    // New: Malware Risk Score
    var malwareRiskScore: MalwareRiskScore?

    // Overall Assessment
    var overallThreatLevel: ThreatLevel
    var threatsDetected: [LegacySecurityThreat]
    var recommendations: [String]
    var networkSafetyRating: Int  // 0-100

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        arpScanResult: ARPScanResult = .notTested,
        dnsLeakResult: DNSLeakResult = .notTested,
        webRTCLeakResult: WebRTCLeakResult = .notTested,
        dpiThrottlingResult: DPIThrottlingResult = .notTested,
        portScanResult: PortScanResult = .notTested,
        tlsFingerprintResult: TLSFingerprintResult = .notTested,
        malwareRiskScore: MalwareRiskScore? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.arpScanResult = arpScanResult
        self.dnsLeakResult = dnsLeakResult
        self.webRTCLeakResult = webRTCLeakResult
        self.dpiThrottlingResult = dpiThrottlingResult
        self.portScanResult = portScanResult
        self.tlsFingerprintResult = tlsFingerprintResult
        self.malwareRiskScore = malwareRiskScore

        // Calculate overall threat level
        var threats: [LegacySecurityThreat] = []

        if case .detected(let threat) = arpScanResult {
            threats.append(threat)
        }
        if case .detected(let threat) = dnsLeakResult {
            threats.append(threat)
        }
        if case .detected(let threat) = webRTCLeakResult {
            threats.append(threat)
        }
        if case .detected(let threat) = dpiThrottlingResult {
            threats.append(threat)
        }
        if case .detected(let threats_) = portScanResult {
            threats.append(contentsOf: threats_)
        }
        if case .detected(let threat) = tlsFingerprintResult {
            threats.append(threat)
        }

        // Add malware threats
        if let malware = malwareRiskScore {
            threats.append(contentsOf: malware.detectedThreats)
        }

        self.threatsDetected = threats

        // Determine threat level
        let criticalCount = threats.filter { $0.severity == .critical }.count
        let highCount = threats.filter { $0.severity == .high }.count
        let mediumCount = threats.filter { $0.severity == .medium }.count

        if criticalCount > 0 {
            self.overallThreatLevel = .critical
        } else if highCount > 0 {
            self.overallThreatLevel = .high
        } else if mediumCount > 0 {
            self.overallThreatLevel = .medium
        } else if threats.isEmpty {
            self.overallThreatLevel = .secure
        } else {
            self.overallThreatLevel = .low
        }

        // Calculate network safety rating (0-100)
        var safetyScore = 100
        safetyScore -= criticalCount * 30
        safetyScore -= highCount * 15
        safetyScore -= mediumCount * 10
        safetyScore -= (threats.count - criticalCount - highCount - mediumCount) * 5

        // Factor in malware risk
        if let malwareScore = malwareRiskScore?.riskScore {
            safetyScore -= malwareScore / 2  // Malware score affects safety
        }

        self.networkSafetyRating = max(0, safetyScore)

        // Generate recommendations
        self.recommendations = Self.generateRecommendations(for: threats)
    }

    static func generateRecommendations(for threats: [LegacySecurityThreat]) -> [String] {
        var recommendations: [String] = []

        for threat in threats {
            switch threat.type {
            case .mitm:
                recommendations.append("⚠️ Disconnect from this network immediately")
                recommendations.append("Use cellular data or trusted network")
                recommendations.append("Avoid entering passwords or sensitive data")
            case .dnsHijacking:
                recommendations.append("Change DNS to 1.1.1.1 or 8.8.8.8")
                recommendations.append("Enable DNS over HTTPS in iOS Settings")
                recommendations.append("Consider using a trusted VPN")
            case .ipLeak:
                recommendations.append("Disable WebRTC in your browser")
                recommendations.append("Use a VPN with WebRTC leak protection")
                recommendations.append("Your real IP may be exposed to websites")
            case .dpiThrottling:
                recommendations.append("Use encrypted DNS (DoH/DoT)")
                recommendations.append("Enable VPN to bypass ISP throttling")
                recommendations.append("Consider switching ISP if persistent")
            case .openPort:
                recommendations.append("Close unnecessary open ports")
                recommendations.append("Enable firewall protection")
                recommendations.append("Scan device for malware")
            case .tlsTampering:
                recommendations.append("Do not trust this network")
                recommendations.append("Possible SSL/TLS interception detected")
                recommendations.append("Avoid banking and sensitive transactions")
            }
        }

        if recommendations.isEmpty {
            recommendations.append("✅ No security threats detected")
            recommendations.append("Your connection appears secure")
        }

        return Array(Set(recommendations)) // Remove duplicates
    }
}

// MARK: - Threat Level

enum ThreatLevel: String, Codable {
    case secure = "Secure"
    case low = "Low Risk"
    case medium = "Medium Risk"
    case high = "High Risk"
    case critical = "Critical"

    var color: String {
        switch self {
        case .secure: return "green"
        case .low: return "blue"
        case .medium: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }

    var icon: String {
        switch self {
        case .secure: return "checkmark.shield.fill"
        case .low: return "shield.lefthalf.filled"
        case .medium: return "exclamationmark.shield.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.shield.fill"
        }
    }
}

// MARK: - Legacy Security Threat

struct LegacySecurityThreat: Codable, Identifiable, Equatable {
    let id: UUID
    let type: LegacyThreatType
    let severity: LegacyThreatSeverity
    let title: String
    let description: String
    let detectedAt: Date
    let technicalDetails: [String: String]

    init(
        id: UUID = UUID(),
        type: LegacyThreatType,
        severity: LegacyThreatSeverity,
        title: String,
        description: String,
        detectedAt: Date = Date(),
        technicalDetails: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.severity = severity
        self.title = title
        self.description = description
        self.detectedAt = detectedAt
        self.technicalDetails = technicalDetails
    }

    static func == (lhs: LegacySecurityThreat, rhs: LegacySecurityThreat) -> Bool {
        lhs.id == rhs.id &&
        lhs.type == rhs.type &&
        lhs.severity == rhs.severity &&
        lhs.title == rhs.title &&
        lhs.description == rhs.description
    }
}

enum LegacyThreatType: String, Codable {
    case mitm = "MITM Attack"
    case dnsHijacking = "DNS Hijacking"
    case ipLeak = "IP Leak"
    case dpiThrottling = "DPI Throttling"
    case openPort = "Open Port"
    case tlsTampering = "TLS Tampering"
}

enum LegacyThreatSeverity: String, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
}

// MARK: - Individual Test Results

enum ARPScanResult: Codable {
    case notTested
    case clean(gatewayMAC: String, gatewayIP: String)
    case detected(LegacySecurityThreat)

    var isClean: Bool {
        if case .clean = self { return true }
        return false
    }
}

enum DNSLeakResult: Codable {
    case notTested
    case clean(dnsServers: [String])
    case detected(LegacySecurityThreat)

    var isClean: Bool {
        if case .clean = self { return true }
        return false
    }
}

enum WebRTCLeakResult: Codable {
    case notTested
    case clean(publicIP: String, localIPs: [String])
    case detected(LegacySecurityThreat)

    var isClean: Bool {
        if case .clean = self { return true }
        return false
    }
}

enum DPIThrottlingResult: Codable {
    case notTested
    case clean
    case detected(LegacySecurityThreat)

    var isClean: Bool {
        if case .clean = self { return true }
        return false
    }
}

enum PortScanResult: Codable {
    case notTested
    case clean
    case detected([LegacySecurityThreat])

    var isClean: Bool {
        if case .clean = self { return true }
        return false
    }
}

enum TLSFingerprintResult: Codable {
    case notTested
    case clean(fingerprint: String)
    case detected(LegacySecurityThreat)

    var isClean: Bool {
        if case .clean = self { return true }
        return false
    }
}

// MARK: - Malware Risk Score

struct MalwareRiskScore: Codable {
    let riskScore: Int  // 0-100 (0 = safe, 100 = critical)
    let detectedThreats: [LegacySecurityThreat]
    let suspiciousActivities: [String]

    // Individual risk factors
    let portScanningDetected: Bool
    let arpAnomalies: Int
    let unknownDevices: Int
    let lanFloodDetected: Bool
    let suspiciousTrafficPatterns: Bool

    var riskLevel: MalwareRiskLevel {
        if riskScore >= 80 {
            return .critical
        } else if riskScore >= 60 {
            return .high
        } else if riskScore >= 40 {
            return .medium
        } else if riskScore >= 20 {
            return .low
        } else {
            return .minimal
        }
    }

    var safetyRating: String {
        let score = 100 - riskScore
        return "\(score)/100"
    }
}

enum MalwareRiskLevel: String, Codable {
    case minimal = "Minimal Risk"
    case low = "Low Risk"
    case medium = "Medium Risk"
    case high = "High Risk"
    case critical = "Critical Risk"
}
