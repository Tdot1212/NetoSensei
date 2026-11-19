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
    /// Issuer-name hint only; never establishes trust or user consent.
    var isProxyMITM: Bool = false
    /// VPN context does not relax certificate trust validation.
    var vpnActive: Bool = false

    /// A presented chain is assessed even when system trust fails. Missing chains remain unavailable.
    var assessment: Assessment = .completed

    enum Assessment: Equatable {
        case completed
        case unavailable(UnavailableReason)

        var isCompleted: Bool { self == .completed }
    }

    enum UnavailableReason: Equatable {
        /// -1001 / -1004 / -1005 / no TLS handshake and no certificates.
        case unreachable(code: Int?)
        /// Chain retrieved but iOS trust evaluation failed and no known proxy
        /// CA explains it — the connection was intercepted or blocked before
        /// the real server; the site's own TLS could not be seen.
        case interceptedOrBlocked

        /// Plain language, same register as the Phase 2.1/3 captions.
        var text: String {
            switch self {
            case .unreachable(let code):
                let suffix = code.map { " (error \($0))" } ?? ""
                return "Couldn't assess — host unreachable from this network\(suffix)"
            case .interceptedOrBlocked:
                return "Couldn't assess — connection intercepted or blocked before reaching the site"
            }
        }
    }

    var unavailableReason: UnavailableReason? {
        if case .unavailable(let r) = assessment { return r }
        return nil
    }

    var isSecure: Bool {
        assessment.isCompleted && tlsVersion.isSecure && !certificateChain.isEmpty && certificateChain.allSatisfy(\.isTrusted) && issues.filter { $0.severity == .critical || $0.severity == .high }.isEmpty
    }

    /// nil when the assessment could not be completed — grades come only from
    /// completed assessments (Commit 7). Renders as "Couldn't assess".
    var securityRating: SecurityRating? {
        guard assessment.isCompleted else { return nil }
        return completedRating
    }

    /// The grade label as the UI shows it — a band word, or the unavailable reason.
    var ratingText: String { securityRating?.rawValue ?? "Couldn't assess" }

    private var completedRating: SecurityRating {
        let criticalCount = issues.filter { $0.severity == .critical }.count
        let highCount = issues.filter { $0.severity == .high }.count
        let mediumCount = issues.filter { $0.severity == .medium }.count

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

struct TLSVersionInfo: Equatable, Sendable {
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

struct CertificateInfo: Identifiable, Sendable {
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

    var expiresInDays: Int? {
        guard let validTo = validTo else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: validTo).day ?? 0
    }

    var isExpiringSoon: Bool {
        expiresInDays.map { $0 <= 30 && $0 > 0 } ?? false
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

    struct Capture: Sendable {
        let chain: [CertificateInfo]
        let trusted: Bool
        let handshakeMs: Double?
        let errorCode: Int?
        let version: TLSVersionInfo
        let cipher: String?
    }
    private let capture: @Sendable (String, UInt16) async -> Capture
    private var activeAnalyses = 0
    init(capture: (@Sendable (String, UInt16) async -> Capture)? = nil) {
        self.capture = capture ?? { host, port in await TLSAnalyzer.fetchCertificateChain(host: host, port: port) }
    }


    // MARK: - Analyze Single Host

    func analyzeHost(_ host: String, port: UInt16 = 443) async -> TLSAnalysisResult {
        return await BackgroundTaskManager.shared.runInBackground(
            id: "tlsAnalysis",
            name: "TLS Analysis: \(host)",
            operation: {
                return await self.performAnalyzeHost(host, port: port)
            },
            resultFormatter: { result in
                result.unavailableReason.map { "\($0.text)" } ?? "Security: \(result.ratingText)"
            }
        )
    }

    private func performAnalyzeHost(_ host: String, port: UInt16 = 443) async -> TLSAnalysisResult {
        activeAnalyses += 1; isAnalyzing = true
        let loadID = "tlsAnalysis-" + UUID().uuidString
        AppLoadTracker.shared.begin(loadID)
        defer { activeAnalyses -= 1; isAnalyzing = activeAnalyses > 0; AppLoadTracker.shared.end(loadID) }
        progress = 0; error = nil

        var cleanHost = host
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if let slashIndex = cleanHost.firstIndex(of: "/") {
            cleanHost = String(cleanHost[..<slashIndex])
        }

        currentStep = "Connecting to \(cleanHost)..."
        progress = 0.1

        // Version, cipher, certificate and handshake duration describe one
        // connection. Redirects are not followed during inspection.
        let captured = await capture(cleanHost, port)
        let (chain, isTrusted, handshakeMs, fetchErrorCode, tlsVersion, cipherSuite) =
            (captured.chain, captured.trusted, captured.handshakeMs, captured.errorCode, captured.version, captured.cipher)

        // Step 3: Was the site's TLS actually assessed? (Commit 7)
        currentStep = "Analyzing security..."
        progress = 0.8
        let proxyMITM = isProxyMITMCert(chain)
        let assessment = Self.classifyAssessment(
            chain: chain,
            isTrusted: isTrusted,
            isProxyMITM: proxyMITM,
            fetchErrorCode: fetchErrorCode
        )

        let issues: [TLSIssue]
        if case .unavailable(let reason) = assessment {
            // Not assessed: one explanatory, non-graded issue. No "Certificate
            // Not Trusted — possible MITM" and no "No Certificates Retrieved"
            // alarms for a host we never actually reached.
            issues = [TLSIssue(
                title: "Couldn't assess this site",
                description: reason.text + ".",
                severity: .info,
                recommendation: reason == .interceptedOrBlocked
                    ? "Retry with your VPN on (or off) to see whether the site itself answers. If it still fails everywhere, the site may genuinely be presenting an untrusted certificate."
                    : "Retry later or on another network. Unreachable is not the same as insecure."
            )]
            debugLog("🔐 TLS \(cleanHost): \(reason.text)")
        } else {
            issues = analyzeIssues(
                host: cleanHost,
                tlsVersion: tlsVersion,
                chain: chain,
                isTrusted: isTrusted
            )
        }

        progress = 1.0
        currentStep = "Complete"

        // Preserve context without weakening trust requirements.
        let vpnIsActive = NetworkMonitorService.shared.currentStatus.vpn.isActive

        var analysisResult = TLSAnalysisResult(
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
        analysisResult.assessment = assessment

        result = analysisResult

        if let idx = recentResults.firstIndex(where: { $0.host == cleanHost }) {
            recentResults[idx] = analysisResult
        } else {
            recentResults.insert(analysisResult, at: 0)
            if recentResults.count > 10 {
                recentResults.removeLast()
            }
        }

        return analysisResult
    }

    // MARK: - Assessment classification (pure, unit-tested — Commit 7)

    /// A presented chain permits reporting trust failures; no chain means unavailable.
    nonisolated static func classifyAssessment(
        chain: [CertificateInfo],
        isTrusted: Bool,
        isProxyMITM: Bool,
        fetchErrorCode: Int?
    ) -> TLSAnalysisResult.Assessment {
        if chain.isEmpty {
            // Nothing came back from the site. A negotiated TLS version alone
            // (NWConnection reached .ready) is still not an assessment of the
            // certificate the site presents.
            return .unavailable(.unreachable(code: fetchErrorCode))
        }
        return .completed // A presented but untrusted chain is an assessed failure, not missing evidence.
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

    // MARK: - Fetch Certificate Chain via URLSession

    /// Fourth element (Commit 7): the URLSession error code (URLError.Code raw
    /// value) when the request failed — nil on success.
    nonisolated private static func fetchCertificateChain(host: String, port: UInt16) async -> Capture {
        let delegate = TLSCertificateDelegate(targetHost: host)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let urlString = port == 443
            ? "https://\(host)/"
            : "https://\(host):\(port)/"
        guard let url = URL(string: urlString) else {
            return Capture(chain: [], trusted: false, handshakeMs: nil, errorCode: URLError.badURL.rawValue, version: .unknown, cipher: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        var errorCode: Int?

        do {
            let (_, _) = try await session.data(for: request)
        } catch {
            // Connection may fail but delegate still captures certs.
            // Commit 7: keep the code so the assessment can name the reason.
            errorCode = (error as? URLError)?.code.rawValue ?? (error as NSError).code
        }

        // Commit 7: a handshake time is only a measurement when the request
        // completed — a 10 s timeout is not a 10 000 ms handshake.
        session.invalidateAndCancel()

        return Capture(chain: delegate.certificates, trusted: delegate.isTrusted, handshakeMs: delegate.handshakeMs, errorCode: errorCode, version: delegate.version, cipher: delegate.cipher)
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

        if !isTrusted && !chain.isEmpty {
            issues.append(TLSIssue(title: "Certificate Not Trusted",
                description: "System trust evaluation failed for this hostname. A VPN or proxy-like issuer name does not override this failure.",
                severity: .critical, recommendation: "Review the certificate and hostname. Do not bypass trust validation."))
        }
        if isProxyMITM {
            issues.append(TLSIssue(title: "Proxy-like Certificate Name",
                description: "A certificate name resembles a debugging proxy. Names alone do not establish who controls the certificate or whether decryption was authorized.",
                severity: .medium, recommendation: "Review locally installed roots and proxy settings.", isProxyArtifact: true))
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
                    description: leaf.expiresInDays.map { "The certificate expires in \($0) days." } ?? "Certificate expiration unavailable.",
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

final class TLSCertificateDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let targetHost: String
    var certificates: [CertificateInfo] = []
    var isTrusted = false
    var version: TLSVersionInfo = .unknown
    var cipher: String?
    var handshakeMs: Double?

    init(targetHost: String) {
        self.targetHost = targetHost
        super.init()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Inspect exactly the requested host, not a redirected site's certificate.
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last else { return }
        version = Self.protocolVersion(transaction.negotiatedTLSProtocolVersion?.rawValue)
        if let identifier = transaction.negotiatedTLSCipherSuite?.rawValue {
            cipher = String(format: "TLS cipher 0x%04X", identifier)
        }
        if let start = transaction.secureConnectionStartDate, let end = transaction.secureConnectionEndDate {
            let duration = end.timeIntervalSince(start)*1000
            handshakeMs = duration.isFinite && duration >= 0 ? duration : nil
        }
    }

    static func protocolVersion(_ value: UInt16?) -> TLSVersionInfo {
        switch value {
        case 0x0304: return .tls13
        case 0x0303: return .tls12
        case 0x0302: return .tls11
        case 0x0301: return .tls10
        default: return .unknown
        }
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

        if let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] {
            certificates = chain.map { CertificateDER.info($0, trusted: isTrusted) }
        }
        if isTrusted {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

}
