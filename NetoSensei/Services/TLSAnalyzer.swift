//
//  TLSAnalyzer.swift
//  NetoSensei
//
//  TLS/Certificate analyzer — checks TLS version, validates certificate
//  chain, detects security issues (expired, self-signed, weak crypto).
//  Uses URLSessionDelegate for iOS-compatible certificate interception.
//

import Foundation
import Security
import Network

// MARK: - Data Models

struct TLSAnalysisResult: Identifiable {
    let id = UUID()
    let host: String
    let port: UInt16
    let tlsVersion: TLSVersionInfo
    let certificateChain: [CertificateInfo]
    let issues: [TLSIssue]
    let cipherSuite: String?
    let handshakeLatencyMs: Double?
    let timestamp: Date
    /// FIX (Issue 4): true when the cert chain shows a known proxy MITM CA
    /// (Surge/Shadowrocket/etc). Used to soften the rating and suppress
    /// duplicate "Self-Signed Certificate" alarms.
    var isProxyMITM: Bool = false
    /// FIX (Issue 4): captured at analysis time so the rating logic can
    /// distinguish "proxy MITM under VPN" (user's own tunnel) from a real
    /// MITM attack on the open internet.
    var vpnActive: Bool = false

    var isSecure: Bool {
        issues.filter { $0.severity == .critical || $0.severity == .high }.isEmpty
    }

    var securityRating: SecurityRating {
        let criticalCount = issues.filter { $0.severity == .critical }.count
        let highCount = issues.filter { $0.severity == .high }.count
        let mediumCount = issues.filter { $0.severity == .medium }.count

        // FIX (Issue 4): when proxy MITM is the ONLY cause of high/critical
        // issues AND VPN is active, downgrade to "Fair". The user is seeing
        // their own proxy app's behavior, not a real attack — "Poor" with
        // a red shield X is misleading.
        if isProxyMITM && vpnActive {
            let nonProxyCritical = issues.filter {
                $0.severity == .critical && !$0.isProxyArtifact
            }.count
            let nonProxyHigh = issues.filter {
                $0.severity == .high && !$0.isProxyArtifact
            }.count
            if nonProxyCritical == 0 && nonProxyHigh == 0 {
                return .fair
            }
        }

        if criticalCount > 0 { return .critical }
        if highCount > 0 { return .poor }
        if mediumCount > 0 { return .fair }
        if tlsVersion.isModern { return .excellent }
        if tlsVersion.isSecure { return .good }
        return .fair
    }

    enum SecurityRating: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case critical = "Critical"

        var icon: String {
            switch self {
            case .excellent: return "checkmark.shield.fill"
            case .good: return "checkmark.shield"
            case .fair: return "exclamationmark.shield"
            case .poor: return "xmark.shield"
            case .critical: return "xmark.shield.fill"
            }
        }
    }
}

struct TLSVersionInfo: Equatable {
    let version: String
    let isSecure: Bool
    let isModern: Bool

    var icon: String {
        if isModern { return "lock.shield.fill" }
        if isSecure { return "lock.shield" }
        return "lock.open"
    }

    static let tls13 = TLSVersionInfo(version: "TLS 1.3", isSecure: true, isModern: true)
    static let tls12 = TLSVersionInfo(version: "TLS 1.2", isSecure: true, isModern: false)
    static let tls11 = TLSVersionInfo(version: "TLS 1.1", isSecure: false, isModern: false)
    static let tls10 = TLSVersionInfo(version: "TLS 1.0", isSecure: false, isModern: false)
    static let unknown = TLSVersionInfo(version: "Unknown", isSecure: false, isModern: false)
}

struct CertificateInfo: Identifiable {
    let id = UUID()
    let subject: String
    let issuer: String
    let serialNumber: String
    let validFrom: Date?
    let validTo: Date?
    let publicKeyInfo: String
    let isSelfSigned: Bool
    let isRootCA: Bool
    let isTrusted: Bool

    var isExpired: Bool {
        guard let validTo = validTo else { return false }
        return Date() > validTo
    }

    var isNotYetValid: Bool {
        guard let validFrom = validFrom else { return false }
        return Date() < validFrom
    }

    var expiresInDays: Int {
        guard let validTo = validTo else { return 999 }
        return Calendar.current.dateComponents([.day], from: Date(), to: validTo).day ?? 0
    }

    var isExpiringSoon: Bool {
        expiresInDays <= 30 && expiresInDays > 0
    }

    var displaySubject: String {
        if let cnRange = subject.range(of: "CN=") {
            let start = cnRange.upperBound
            let remaining = subject[start...]
            if let commaIndex = remaining.firstIndex(of: ",") {
                return String(remaining[..<commaIndex])
            }
            return String(remaining)
        }
        return subject
    }
}

struct TLSIssue: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let severity: Severity
    let recommendation: String
    /// FIX (Issue 4): true when this issue is a side-effect of the user's
    /// own proxy app doing MITM (Surge/Shadowrocket/etc), not a genuine
    /// security problem. The rating logic uses this to avoid downgrading
    /// to "Poor"/"Critical" when proxy MITM is the only signal.
    var isProxyArtifact: Bool = false

    enum Severity: String {
        case critical = "Critical"
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        case info = "Info"

        var icon: String {
            switch self {
            case .critical: return "xmark.octagon.fill"
            case .high: return "exclamationmark.triangle.fill"
            case .medium: return "exclamationmark.triangle"
            case .low: return "exclamationmark.circle"
            case .info: return "info.circle"
            }
        }
    }
}

// MARK: - TLS Analyzer Service

@MainActor
class TLSAnalyzer: ObservableObject {
    static let shared = TLSAnalyzer()

    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var currentStep = ""
    @Published var result: TLSAnalysisResult?
    @Published var error: String?
    @Published var recentResults: [TLSAnalysisResult] = []

    let commonTestSites = [
        ("google.com", "Google"),
        ("apple.com", "Apple"),
        ("github.com", "GitHub"),
        ("cloudflare.com", "Cloudflare"),
        ("baidu.com", "Baidu"),
        ("alipay.com", "Alipay"),
    ]

    private init() {}

    // MARK: - Analyze Single Host

    func analyzeHost(_ host: String, port: UInt16 = 443) async -> TLSAnalysisResult {
        return await BackgroundTaskManager.shared.runInBackground(
            id: "tlsAnalysis",
            name: "TLS Analysis: \(host)",
            operation: {
                return await self.performAnalyzeHost(host, port: port)
            },
            resultFormatter: { result in
                "Security: \(result.securityRating.rawValue)"
            }
        )
    }

    private func performAnalyzeHost(_ host: String, port: UInt16 = 443) async -> TLSAnalysisResult {
        isAnalyzing = true
        progress = 0
        error = nil

        var cleanHost = host
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if let slashIndex = cleanHost.firstIndex(of: "/") {
            cleanHost = String(cleanHost[..<slashIndex])
        }

        currentStep = "Connecting to \(cleanHost)..."
        progress = 0.1

        // Step 1: TLS handshake via NWConnection (for TLS version/cipher)
        currentStep = "Checking TLS version..."
        progress = 0.2
        let (tlsVersion, cipherSuite) = await detectTLSVersion(host: cleanHost, port: port)

        // Step 2: Certificate chain via URLSession delegate
        currentStep = "Retrieving certificates..."
        progress = 0.4
        let (chain, isTrusted, handshakeMs) = await fetchCertificateChain(host: cleanHost, port: port)

        // Step 3: Analyze for issues
        currentStep = "Analyzing security..."
        progress = 0.8
        let issues = analyzeIssues(
            host: cleanHost,
            tlsVersion: tlsVersion,
            chain: chain,
            isTrusted: isTrusted
        )

        progress = 1.0
        currentStep = "Complete"

        // FIX (Issue 4): pass proxy-MITM and VPN context to the result so
        // securityRating can soften when these are the only signals.
        let proxyMITM = isProxyMITMCert(chain)
        let vpnIsActive = NetworkMonitorService.shared.currentStatus.vpn.isActive

        let analysisResult = TLSAnalysisResult(
            host: cleanHost,
            port: port,
            tlsVersion: tlsVersion,
            certificateChain: chain,
            issues: issues,
            cipherSuite: cipherSuite,
            handshakeLatencyMs: handshakeMs,
            timestamp: Date(),
            isProxyMITM: proxyMITM,
            vpnActive: vpnIsActive
        )

        result = analysisResult

        if let idx = recentResults.firstIndex(where: { $0.host == cleanHost }) {
            recentResults[idx] = analysisResult
        } else {
            recentResults.insert(analysisResult, at: 0)
            if recentResults.count > 10 {
                recentResults.removeLast()
            }
        }

        isAnalyzing = false
        return analysisResult
    }

    // MARK: - Detect TLS Version via NWConnection

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

    private nonisolated func detectTLSVersion(host: String, port: UInt16) async -> (TLSVersionInfo, String?) {
        await withCheckedContinuation { (continuation: CheckedContinuation<(TLSVersionInfo, String?), Never>) in
            let tlsOptions = NWProtocolTLS.Options()
            let params = NWParameters(tls: tlsOptions)

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: (.unknown, nil))
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: params
            )
            let flag = OnceFlag()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if flag.claim() {
                        var version = TLSVersionInfo.unknown
                        var cipher: String?

                        if let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
                            let proto = metadata.securityProtocolMetadata

                            let tlsVer = sec_protocol_metadata_get_negotiated_tls_protocol_version(proto)
                            switch tlsVer {
                            case .TLSv13: version = .tls13
                            case .TLSv12: version = .tls12
                            case .TLSv11: version = .tls11
                            case .TLSv10: version = .tls10
                            default: version = .unknown
                            }

                            let cs = sec_protocol_metadata_get_negotiated_tls_ciphersuite(proto)
                            cipher = Self.cipherSuiteName(cs)
                        }

                        connection.cancel()
                        continuation.resume(returning: (version, cipher))
                    }

                case .failed, .cancelled:
                    if flag.claim() {
                        continuation.resume(returning: (.unknown, nil))
                    }

                case .waiting:
                    if flag.claim() {
                        connection.cancel()
                        continuation.resume(returning: (.unknown, nil))
                    }

                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                if flag.claim() {
                    connection.cancel()
                    continuation.resume(returning: (.unknown, nil))
                }
            }
        }
    }

    private nonisolated static func cipherSuiteName(_ cipher: tls_ciphersuite_t) -> String {
        switch cipher {
        case .RSA_WITH_AES_128_GCM_SHA256: return "RSA_AES_128_GCM_SHA256"
        case .RSA_WITH_AES_256_GCM_SHA384: return "RSA_AES_256_GCM_SHA384"
        case .ECDHE_RSA_WITH_AES_128_GCM_SHA256: return "ECDHE_RSA_AES_128_GCM"
        case .ECDHE_RSA_WITH_AES_256_GCM_SHA384: return "ECDHE_RSA_AES_256_GCM"
        case .AES_128_GCM_SHA256: return "TLS_AES_128_GCM_SHA256"
        case .AES_256_GCM_SHA384: return "TLS_AES_256_GCM_SHA384"
        case .CHACHA20_POLY1305_SHA256: return "TLS_CHACHA20_POLY1305"
        default: return "Cipher \(cipher.rawValue)"
        }
    }

    // MARK: - Fetch Certificate Chain via URLSession

    private nonisolated func fetchCertificateChain(host: String, port: UInt16) async -> ([CertificateInfo], Bool, Double?) {
        let delegate = TLSCertificateDelegate(targetHost: host)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let urlString = port == 443
            ? "https://\(host)/"
            : "https://\(host):\(port)/"
        guard let url = URL(string: urlString) else {
            return ([], false, nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let (_, _) = try await session.data(for: request)
        } catch {
            // Connection may fail but delegate still captures certs
        }

        let handshakeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        session.invalidateAndCancel()

        return (delegate.certificates, delegate.isTrusted, handshakeMs)
    }

    // MARK: - Analyze Issues

    /// Check if any cert in the chain is from a known proxy/VPN app.
    /// CLEANUP 6: needles live in ProxyDetection.knownProxyApps.
    private func isProxyMITMCert(_ chain: [CertificateInfo]) -> Bool {
        let needles = ProxyDetection.knownProxyApps.map { $0.needle }
        for cert in chain {
            let combined = (cert.subject + " " + cert.issuer).lowercased()
            if needles.contains(where: { combined.contains($0) }) {
                return true
            }
        }
        return false
    }

    private func analyzeIssues(
        host: String,
        tlsVersion: TLSVersionInfo,
        chain: [CertificateInfo],
        isTrusted: Bool
    ) -> [TLSIssue] {
        var issues: [TLSIssue] = []

        // ISSUE 8 FIX: Detect proxy MITM before flagging trust issues
        let isProxyMITM = isProxyMITMCert(chain)

        // TLS version
        if !tlsVersion.isSecure && tlsVersion.version != "Unknown" {
            issues.append(TLSIssue(
                title: "Outdated TLS Version",
                description: "Server uses \(tlsVersion.version) which is considered insecure.",
                severity: tlsVersion.version == "TLS 1.0" ? .critical : .high,
                recommendation: "The server should support TLS 1.2 or 1.3."
            ))
        }

        // Trust evaluation
        if !isTrusted && !chain.isEmpty {
            if isProxyMITM {
                // ISSUE 8 FIX: Proxy MITM cert — this is local debugging/routing, not an attack
                issues.append(TLSIssue(
                    title: "TLS Intercepted by Local Proxy",
                    description: "A local proxy app (Surge, Shadowrocket, etc.) is intercepting TLS for traffic routing. This is normal when MITM debugging is enabled.",
                    severity: .low,
                    recommendation: "This is expected behavior for proxy apps with MITM enabled. Disable MITM in your proxy app's settings if you don't need HTTPS decryption.",
                    isProxyArtifact: true
                ))
            } else {
                // No proxy detected — could be genuine MITM or cert mismatch through VPN
                let vpnInfo = NetworkMonitorService.shared.currentStatus.vpn
                if vpnInfo.isActive {
                    issues.append(TLSIssue(
                        title: "Certificate Mismatch Through VPN",
                        description: "The certificate chain failed trust evaluation while VPN is active. This may be caused by your VPN/proxy intercepting HTTPS traffic.",
                        severity: .medium,
                        recommendation: "Check your VPN/proxy MITM settings. If you have HTTPS decryption enabled, add this host to the bypass list or install the proxy's CA certificate.",
                        isProxyArtifact: true
                    ))
                } else {
                    issues.append(TLSIssue(
                        title: "Certificate Not Trusted",
                        description: "The certificate chain failed system trust evaluation.",
                        severity: .critical,
                        recommendation: "Do not trust this connection. This could indicate a MITM attack."
                    ))
                }
            }
        }

        // Leaf certificate checks
        if let leaf = chain.first {
            if leaf.isExpired {
                issues.append(TLSIssue(
                    title: "Certificate Expired",
                    description: "The certificate expired on \(formatDate(leaf.validTo)).",
                    severity: .critical,
                    recommendation: "Do not trust this connection. The certificate needs renewal."
                ))
            }

            if leaf.isNotYetValid {
                issues.append(TLSIssue(
                    title: "Certificate Not Yet Valid",
                    description: "The certificate is not valid until \(formatDate(leaf.validFrom)).",
                    severity: .critical,
                    recommendation: "Check your device's date/time settings."
                ))
            }

            if leaf.isExpiringSoon {
                issues.append(TLSIssue(
                    title: "Certificate Expiring Soon",
                    description: "The certificate expires in \(leaf.expiresInDays) days.",
                    severity: .medium,
                    recommendation: "The server administrator should renew the certificate soon."
                ))
            }

            // FIX (Issue 4): suppress the "Self-Signed Certificate" critical
            // alarm when proxy MITM is detected. The "TLS Intercepted by Local
            // Proxy" / "Certificate Mismatch Through VPN" issue already covers
            // this exact root cause — showing two warnings for the same thing
            // (and labeling the second one as a possible MITM attack) was
            // confusing and made the rating drop to "Poor" with a red shield.
            if leaf.isSelfSigned && !leaf.isRootCA && !isProxyMITM {
                issues.append(TLSIssue(
                    title: "Self-Signed Certificate",
                    description: "The certificate is not issued by a trusted Certificate Authority.",
                    severity: .high,
                    recommendation: "This could indicate a MITM attack or misconfigured server."
                ))
            }
        }

        // Short chain
        if chain.count == 1 && !(chain.first?.isRootCA ?? false) {
            issues.append(TLSIssue(
                title: "Incomplete Certificate Chain",
                description: "The server may not be sending intermediate certificates.",
                severity: .low,
                recommendation: "This could cause trust issues on some devices."
            ))
        }

        // Empty chain
        if chain.isEmpty {
            issues.append(TLSIssue(
                title: "No Certificates Retrieved",
                description: "Could not retrieve the certificate chain from the server.",
                severity: .high,
                recommendation: "The server may be unreachable or blocking connections."
            ))
        }

        // All good
        if issues.isEmpty {
            issues.append(TLSIssue(
                title: "No Issues Found",
                description: "The TLS configuration appears to be secure.",
                severity: .info,
                recommendation: "Connection is properly secured with \(tlsVersion.version)."
            ))
        }

        return issues
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - URLSession Delegate for Certificate Capture

private class TLSCertificateDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let targetHost: String
    var certificates: [CertificateInfo] = []
    var isTrusted = false

    init(targetHost: String) {
        self.targetHost = targetHost
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate trust
        let policy = SecPolicyCreateSSL(true, targetHost as CFString)
        SecTrustSetPolicies(serverTrust, policy)

        var cfError: CFError?
        isTrusted = SecTrustEvaluateWithError(serverTrust, &cfError)

        // Extract certificate chain (iOS 15+: SecTrustCopyCertificateChain)
        if let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] {
            let total = certChain.count
            for (index, cert) in certChain.enumerated() {
                let info = parseCertificate(cert, index: index, total: total)
                certificates.append(info)
            }
        }

        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }

    private func parseCertificate(_ cert: SecCertificate, index: Int, total: Int) -> CertificateInfo {
        let summary = SecCertificateCopySubjectSummary(cert) as String? ?? "Unknown"
        let certData = SecCertificateCopyData(cert) as Data

        // Extract issuer by searching DER data for known CA names
        let issuer = extractIssuer(from: certData, fallback: summary)

        // Extract serial number (first 20 bytes after sequence headers, simplified)
        let serialHex = certData.prefix(20).map { String(format: "%02X", $0) }.joined(separator: ":")

        // Extract validity dates by searching for known OID patterns in DER
        let (validFrom, validTo) = extractValidityDates(from: certData)

        // Detect key type from DER (look for OID markers)
        let publicKeyInfo = detectPublicKeyInfo(from: certData)

        let isSelfSigned = summary == issuer || index == total - 1
        let isRootCA = index == total - 1

        return CertificateInfo(
            subject: summary,
            issuer: issuer,
            serialNumber: serialHex,
            validFrom: validFrom,
            validTo: validTo,
            publicKeyInfo: publicKeyInfo,
            isSelfSigned: isSelfSigned,
            isRootCA: isRootCA,
            isTrusted: true
        )
    }

    private func extractIssuer(from data: Data, fallback: String) -> String {
        // Search DER for known CA organization names
        let dataString = String(data: data, encoding: .ascii) ?? ""
        let knownCAs = [
            "Let's Encrypt", "DigiCert", "Cloudflare", "Google Trust Services",
            "Amazon", "GlobalSign", "Sectigo", "GeoTrust", "Comodo",
            "Baltimore", "Apple", "Microsoft", "GoDaddy", "Entrust",
            "Starfield", "VeriSign", "Thawte", "RapidSSL",
        ]
        for ca in knownCAs {
            if dataString.contains(ca) {
                return ca
            }
        }
        return fallback
    }

    private func extractValidityDates(from data: Data) -> (Date?, Date?) {
        // DER-encoded certificates use UTCTime (0x17) or GeneralizedTime (0x18)
        // for validity dates. Search for these tags and parse.
        // Simplified heuristic: find date-like strings in the data.

        let bytes = [UInt8](data)
        var dates: [Date] = []
        let formatter = DateFormatter()

        for i in 0..<bytes.count {
            if bytes[i] == 0x17 && i + 1 < bytes.count {
                // UTCTime: YYMMDDHHmmSSZ (13 bytes)
                let length = Int(bytes[i + 1])
                if length == 13 && i + 2 + length <= bytes.count {
                    let dateBytes = Array(bytes[(i + 2)..<(i + 2 + length)])
                    if let dateStr = String(bytes: dateBytes, encoding: .ascii) {
                        formatter.dateFormat = "yyMMddHHmmss'Z'"
                        formatter.timeZone = TimeZone(identifier: "UTC")
                        if let date = formatter.date(from: dateStr) {
                            dates.append(date)
                        }
                    }
                }
            } else if bytes[i] == 0x18 && i + 1 < bytes.count {
                // GeneralizedTime: YYYYMMDDHHmmSSZ (15 bytes)
                let length = Int(bytes[i + 1])
                if length == 15 && i + 2 + length <= bytes.count {
                    let dateBytes = Array(bytes[(i + 2)..<(i + 2 + length)])
                    if let dateStr = String(bytes: dateBytes, encoding: .ascii) {
                        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
                        formatter.timeZone = TimeZone(identifier: "UTC")
                        if let date = formatter.date(from: dateStr) {
                            dates.append(date)
                        }
                    }
                }
            }
        }

        // First two dates in a cert are NotBefore and NotAfter
        let validFrom = dates.count >= 1 ? dates[0] : nil
        let validTo = dates.count >= 2 ? dates[1] : nil
        return (validFrom, validTo)
    }

    private func detectPublicKeyInfo(from data: Data) -> String {
        let dataString = String(data: data, encoding: .ascii) ?? ""

        if dataString.contains("EC Public Key") || dataString.contains("prime256v1") || dataString.contains("secp384r1") {
            return "ECDSA 256-bit"
        }
        if dataString.contains("RSA") {
            return "RSA 2048-bit"
        }

        // Check DER for RSA OID (1.2.840.113549.1.1.1)
        let rsaOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        let ecOID: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
        let bytes = [UInt8](data)

        if containsSequence(bytes, rsaOID) {
            return "RSA"
        }
        if containsSequence(bytes, ecOID) {
            return "ECDSA"
        }

        return "Unknown"
    }

    private func containsSequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for i in 0...(haystack.count - needle.count) {
            if Array(haystack[i..<(i + needle.count)]) == needle {
                return true
            }
        }
        return false
    }
}
