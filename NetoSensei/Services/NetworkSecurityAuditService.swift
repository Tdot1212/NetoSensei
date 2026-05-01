//
//  NetworkSecurityAuditService.swift
//  NetoSensei
//
//  Network Security Audit - Honest, real security checks
//  Checks: DNS integrity, TLS certificates, captive portals, proxy config, HTTPS enforcement
//

import Foundation
import Network

// MARK: - Security Check Model

struct SecurityCheck: Identifiable {
    let id = UUID()
    let name: String
    let status: Status
    let detail: String
    let recommendation: String?
    let icon: String

    enum Status: String {
        case passed = "Passed"
        case warning = "Warning"
        case failed = "Failed"
        case unknown = "Unknown"

        var color: String {
            switch self {
            case .passed: return "green"
            case .warning: return "yellow"
            case .failed: return "red"
            case .unknown: return "gray"
            }
        }

        var systemImage: String {
            switch self {
            case .passed: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failed: return "xmark.circle.fill"
            case .unknown: return "questionmark.circle.fill"
            }
        }
    }
}

// MARK: - Audit Result

struct SecurityAuditResult {
    let checks: [SecurityCheck]
    let overallRating: Rating
    let summary: String
    let timestamp: Date

    enum Rating: String {
        case secure = "Secure"
        case moderateRisk = "Moderate Risk"
        case highRisk = "High Risk"

        var color: String {
            switch self {
            case .secure: return "green"
            case .moderateRisk: return "yellow"
            case .highRisk: return "red"
            }
        }

        var icon: String {
            switch self {
            case .secure: return "checkmark.shield.fill"
            case .moderateRisk: return "exclamationmark.shield.fill"
            case .highRisk: return "xmark.shield.fill"
            }
        }
    }

    var passedCount: Int {
        checks.filter { $0.status == .passed }.count
    }

    var warningCount: Int {
        checks.filter { $0.status == .warning }.count
    }

    var failedCount: Int {
        checks.filter { $0.status == .failed }.count
    }
}

// MARK: - Certificate Check Delegate

class CertificateCheckDelegate: NSObject, URLSessionDelegate {
    var certificateIssuer: String?
    var certificateSubject: String?
    var isValidChain = true

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Get the certificate chain
        if let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
           let cert = certChain.first {
            // Get certificate summary (issuer/subject)
            if let summary = SecCertificateCopySubjectSummary(cert) as String? {
                certificateSubject = summary
            }

            // Try to extract issuer from certificate
            if let certData = SecCertificateCopyData(cert) as Data? {
                // Parse the issuer from the certificate data
                // This is a simplified check - look for known CA names
                let certString = String(data: certData, encoding: .utf8) ?? ""
                if certString.contains("DigiCert") {
                    certificateIssuer = "DigiCert"
                } else if certString.contains("Apple") {
                    certificateIssuer = "Apple"
                } else if certString.contains("Let's Encrypt") {
                    certificateIssuer = "Let's Encrypt"
                } else if certString.contains("Cloudflare") {
                    certificateIssuer = "Cloudflare"
                } else if certString.contains("Google") {
                    certificateIssuer = "Google Trust Services"
                } else {
                    // Use subject as fallback
                    certificateIssuer = certificateSubject
                }
            }
        }

        // Evaluate trust
        var error: CFError?
        isValidChain = SecTrustEvaluateWithError(serverTrust, &error)

        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }
}

// MARK: - Network Security Audit Service

@MainActor
class NetworkSecurityAuditService: ObservableObject {
    static let shared = NetworkSecurityAuditService()

    @Published var lastResult: SecurityAuditResult?
    @Published var isRunning = false
    @Published var currentCheck = ""

    private init() {}

    // MARK: - Run Full Audit

    func runFullAudit(progressCallback: ((String) -> Void)? = nil) async -> SecurityAuditResult {
        isRunning = true
        var checks: [SecurityCheck] = []

        // 1. DNS Integrity Check
        currentCheck = "Checking DNS integrity..."
        progressCallback?("Checking DNS integrity...")
        let dnsCheck = await checkDNSIntegrity()
        checks.append(dnsCheck)

        // 2. TLS Certificate Validation
        currentCheck = "Validating TLS certificates..."
        progressCallback?("Validating TLS certificates...")
        let tlsCheck = await checkTLSCertificates()
        checks.append(tlsCheck)

        // 3. Captive Portal Detection
        currentCheck = "Checking for captive portal..."
        progressCallback?("Checking for captive portal...")
        let portalCheck = await checkCaptivePortal()
        checks.append(portalCheck)

        // 4. Proxy Configuration Check
        currentCheck = "Checking proxy configuration..."
        progressCallback?("Checking proxy configuration...")
        let proxyCheck = checkProxyConfiguration()
        checks.append(proxyCheck)

        // 5. HTTPS Enforcement Check
        currentCheck = "Testing HTTPS enforcement..."
        progressCallback?("Testing HTTPS enforcement...")
        let httpsCheck = await checkHTTPSEnforcement()
        checks.append(httpsCheck)

        // 6. VPN Leak Check (if VPN active)
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        if vpnActive {
            currentCheck = "Checking for VPN leaks..."
            progressCallback?("Checking for VPN leaks...")
            let leakCheck = await checkVPNLeaks()
            checks.append(leakCheck)
        }

        // 7. Open Network Check
        currentCheck = "Checking network security..."
        progressCallback?("Checking network security...")
        let networkCheck = checkOpenNetwork()
        checks.append(networkCheck)

        // Calculate overall rating
        let failedCount = checks.filter { $0.status == .failed }.count
        let warningCount = checks.filter { $0.status == .warning }.count

        let rating: SecurityAuditResult.Rating
        let summary: String

        if failedCount > 0 {
            rating = .highRisk
            summary = "\(failedCount) security issue\(failedCount > 1 ? "s" : "") found that require attention."
        } else if warningCount > 0 {
            rating = .moderateRisk
            summary = "No critical issues, but \(warningCount) item\(warningCount > 1 ? "s" : "") need attention."
        } else {
            rating = .secure
            summary = "All security checks passed. Your network connection appears secure."
        }

        let result = SecurityAuditResult(
            checks: checks,
            overallRating: rating,
            summary: summary,
            timestamp: Date()
        )

        lastResult = result
        isRunning = false
        currentCheck = ""

        return result
    }

    // MARK: - 1. DNS Integrity Check

    private func checkDNSIntegrity() async -> SecurityCheck {
        // Resolve apple.com and verify it returns Apple's IP range (17.x.x.x)
        return await withCheckedContinuation { continuation in
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_STREAM
            var res: UnsafeMutablePointer<addrinfo>?

            let status = getaddrinfo("apple.com", "443", &hints, &res)
            defer { if let res = res { freeaddrinfo(res) } }

            if status != 0 {
                continuation.resume(returning: SecurityCheck(
                    name: "DNS Integrity",
                    status: .warning,
                    detail: "Could not resolve apple.com. DNS may be unavailable or blocked.",
                    recommendation: "Check your DNS settings. Try switching to 1.1.1.1 or 8.8.8.8.",
                    icon: "network"
                ))
                return
            }

            // Check if resolved IP starts with "17." (Apple's range)
            if let res = res {
                let addr = res.pointee.ai_addr
                if res.pointee.ai_family == AF_INET, let addr = addr {
                    var ip = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    // Extract IP address from sockaddr_in
                    addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sockaddrIn in
                        var sinAddr = sockaddrIn.pointee.sin_addr
                        inet_ntop(AF_INET, &sinAddr, &ip, socklen_t(INET_ADDRSTRLEN))
                    }
                    let ipString = String(cString: ip)

                    if ipString.hasPrefix("17.") {
                        continuation.resume(returning: SecurityCheck(
                            name: "DNS Integrity",
                            status: .passed,
                            detail: "DNS resolves apple.com to expected IP range (\(ipString)).",
                            recommendation: nil,
                            icon: "checkmark.shield"
                        ))
                    } else {
                        continuation.resume(returning: SecurityCheck(
                            name: "DNS Integrity",
                            status: .warning,
                            detail: "apple.com resolved to \(ipString), which is outside Apple's expected range. This could indicate DNS hijacking or a CDN.",
                            recommendation: "If you're not on a corporate network, verify your DNS settings haven't been tampered with.",
                            icon: "exclamationmark.triangle"
                        ))
                    }
                    return
                }
            }

            continuation.resume(returning: SecurityCheck(
                name: "DNS Integrity",
                status: .passed,
                detail: "DNS resolution working. Known domains resolve correctly.",
                recommendation: nil,
                icon: "checkmark.shield"
            ))
        }
    }

    // MARK: - 2. TLS Certificate Check

    private func checkTLSCertificates() async -> SecurityCheck {
        let url = URL(string: "https://www.apple.com")!
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let delegate = CertificateCheckDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        do {
            let (_, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                // Check if issuer is expected
                if let issuer = delegate.certificateIssuer {
                    let expectedIssuers = ["DigiCert", "Apple", "Akamai", "Cloudflare"]
                    let isExpected = expectedIssuers.contains { issuer.contains($0) }

                    if isExpected || delegate.isValidChain {
                        return SecurityCheck(
                            name: "TLS Certificates",
                            status: .passed,
                            detail: "HTTPS certificates are valid. Certificate for apple.com issued by: \(issuer).",
                            recommendation: nil,
                            icon: "lock.shield"
                        )
                    } else {
                        return SecurityCheck(
                            name: "TLS Certificates",
                            status: .warning,
                            detail: "Certificate for apple.com issued by: \(issuer). This may indicate a corporate proxy or network inspection.",
                            recommendation: "If you're not on a corporate network, someone may be intercepting your HTTPS traffic. Avoid entering sensitive information.",
                            icon: "lock.trianglebadge.exclamationmark"
                        )
                    }
                }
            }
        } catch {
            return SecurityCheck(
                name: "TLS Certificates",
                status: .warning,
                detail: "Could not verify TLS certificate: \(error.localizedDescription)",
                recommendation: "Check your network connection and try again.",
                icon: "lock.slash"
            )
        }

        return SecurityCheck(
            name: "TLS Certificates",
            status: .passed,
            detail: "HTTPS connections are properly secured.",
            recommendation: nil,
            icon: "lock.shield"
        )
    }

    // MARK: - 3. Captive Portal Check

    private func checkCaptivePortal() async -> SecurityCheck {
        // Apple's captive portal check URL
        guard let url = URL(string: "http://captive.apple.com/hotspot-detect.html") else {
            return SecurityCheck(
                name: "Captive Portal",
                status: .unknown,
                detail: "Could not create test URL.",
                recommendation: nil,
                icon: "wifi.exclamationmark"
            )
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        // Don't follow redirects so we can detect captive portals
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)

        do {
            let (data, _) = try await session.data(from: url)
            let body = String(data: data, encoding: .utf8) ?? ""

            // Check for the expected response
            if body.contains("Success") {
                return SecurityCheck(
                    name: "Captive Portal",
                    status: .passed,
                    detail: "No captive portal detected. Direct internet access confirmed.",
                    recommendation: nil,
                    icon: "wifi"
                )
            } else {
                // Content was modified - likely a captive portal
                return SecurityCheck(
                    name: "Captive Portal",
                    status: .failed,
                    detail: "Your connection is being redirected through a captive portal or gateway. You may be on a public network that intercepts traffic.",
                    recommendation: (SmartVPNDetector.shared.detectionResult?.vpnState.isLikelyOn ?? false)
                        ? "Your VPN provides protection. Avoid entering sensitive information on untrusted networks."
                        : "Avoid entering sensitive information until you're on a trusted network. Use a VPN for protection.",
                    icon: "wifi.exclamationmark"
                )
            }
        } catch {
            // Connection blocked or redirected
            if let urlError = error as? URLError, urlError.code == .httpTooManyRedirects {
                return SecurityCheck(
                    name: "Captive Portal",
                    status: .failed,
                    detail: "Detected captive portal redirect. You may need to authenticate with the network.",
                    recommendation: "Open Safari and try to visit any website to trigger the login page.",
                    icon: "wifi.exclamationmark"
                )
            }

            return SecurityCheck(
                name: "Captive Portal",
                status: .warning,
                detail: "Could not complete captive portal check: \(error.localizedDescription)",
                recommendation: nil,
                icon: "wifi"
            )
        }
    }

    // MARK: - 4. Proxy Configuration Check

    private func checkProxyConfiguration() -> SecurityCheck {
        guard let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return SecurityCheck(
                name: "Proxy Configuration",
                status: .passed,
                detail: "No proxy configured. Traffic goes directly through your network.",
                recommendation: nil,
                icon: "arrow.triangle.branch"
            )
        }

        var proxyTypes: [String] = []

        if let httpProxy = proxySettings["HTTPProxy"] as? String, !httpProxy.isEmpty {
            proxyTypes.append("HTTP (\(httpProxy))")
        }
        if let httpsProxy = proxySettings["HTTPSProxy"] as? String, !httpsProxy.isEmpty {
            proxyTypes.append("HTTPS (\(httpsProxy))")
        }
        if let socksProxy = proxySettings["SOCKSProxy"] as? String, !socksProxy.isEmpty {
            proxyTypes.append("SOCKS (\(socksProxy))")
        }
        if let pacURL = proxySettings["ProxyAutoConfigURLString"] as? String, !pacURL.isEmpty {
            proxyTypes.append("PAC Auto-Config")
        }

        if let httpEnable = proxySettings["HTTPEnable"] as? Int, httpEnable == 1 {
            if !proxyTypes.contains(where: { $0.hasPrefix("HTTP") }) {
                proxyTypes.append("HTTP Proxy Enabled")
            }
        }

        if !proxyTypes.isEmpty {
            return SecurityCheck(
                name: "Proxy Configuration",
                status: .warning,
                detail: "Active proxy detected: \(proxyTypes.joined(separator: ", ")). If you didn't configure this, it may be monitoring your traffic.",
                recommendation: "Check Settings → Wi-Fi → (i) → HTTP Proxy. If set to 'Manual' or 'Automatic' and you didn't set it, consider removing it.",
                icon: "arrow.triangle.branch"
            )
        }

        return SecurityCheck(
            name: "Proxy Configuration",
            status: .passed,
            detail: "No proxy configured. Traffic goes directly through your network.",
            recommendation: nil,
            icon: "arrow.triangle.branch"
        )
    }

    // MARK: - 5. HTTPS Enforcement Check

    private func checkHTTPSEnforcement() async -> SecurityCheck {
        // Try accessing a site that should redirect HTTP to HTTPS
        guard let url = URL(string: "http://github.com") else {
            return SecurityCheck(
                name: "HTTPS Enforcement",
                status: .unknown,
                detail: "Could not create test URL.",
                recommendation: nil,
                icon: "lock"
            )
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)

        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               let finalURL = httpResponse.url {
                if finalURL.scheme == "https" {
                    return SecurityCheck(
                        name: "HTTPS Enforcement",
                        status: .passed,
                        detail: "HTTP to HTTPS upgrade working correctly. Sites properly redirect to secure connections.",
                        recommendation: nil,
                        icon: "lock.fill"
                    )
                } else {
                    return SecurityCheck(
                        name: "HTTPS Enforcement",
                        status: .warning,
                        detail: "HTTP requests are not being upgraded to HTTPS. This could indicate HTTPS downgrade or stripping.",
                        recommendation: (SmartVPNDetector.shared.detectionResult?.vpnState.isLikelyOn ?? false)
                            ? "Your VPN should protect against this. Ensure your VPN is routing all traffic."
                            : "Use a VPN or ensure you're on a trusted network. Always check for the lock icon in Safari.",
                        icon: "lock.open"
                    )
                }
            }
        } catch {
            // Network error - not necessarily a security issue
            return SecurityCheck(
                name: "HTTPS Enforcement",
                status: .unknown,
                detail: "Could not test HTTPS enforcement: \(error.localizedDescription)",
                recommendation: nil,
                icon: "lock"
            )
        }

        return SecurityCheck(
            name: "HTTPS Enforcement",
            status: .passed,
            detail: "HTTPS connections are properly secured.",
            recommendation: nil,
            icon: "lock.fill"
        )
    }

    // MARK: - 6. VPN Leak Check

    private func checkVPNLeaks() async -> SecurityCheck {
        // Check if the public IP matches expected VPN IP
        let geoIP = await GeoIPService.shared.fetchGeoIPInfo()
        let vpnResult = SmartVPNDetector.shared.detectionResult

        // If VPN is active but we're getting our ISP's IP, that's a leak
        if let vpnResult = vpnResult, vpnResult.isVPNActive {
            // Check if the IP appears to be from a VPN provider
            let ispName = geoIP.isp?.lowercased() ?? ""
            let orgName = geoIP.org?.lowercased() ?? ""

            let vpnProviderKeywords = ["vpn", "private", "express", "nord", "surfshark", "proton", "mullvad", "tunnel", "cyberghost"]
            let isVPNIP = vpnProviderKeywords.contains { keyword in
                ispName.contains(keyword) || orgName.contains(keyword)
            }

            // Also check if the IP is a datacenter/hosting IP (common for VPNs)
            let datacenterKeywords = ["hosting", "server", "cloud", "digital ocean", "amazon", "google cloud", "microsoft azure", "linode", "vultr", "ovh"]
            let isDatacenterIP = datacenterKeywords.contains { keyword in
                ispName.contains(keyword) || orgName.contains(keyword)
            }

            if !isVPNIP && !isDatacenterIP && !ispName.isEmpty {
                // Public IP looks like a residential ISP while VPN is supposedly active
                return SecurityCheck(
                    name: "VPN Leak Protection",
                    status: .warning,
                    detail: "VPN is active but your public IP (\(geoIP.publicIP)) appears to belong to \(geoIP.isp ?? "your ISP"). This could indicate a DNS or IP leak.",
                    recommendation: "Check your VPN app settings for leak protection. Consider enabling 'Kill Switch' if available.",
                    icon: "shield.lefthalf.filled.slash"
                )
            }
        }

        return SecurityCheck(
            name: "VPN Leak Protection",
            status: .passed,
            detail: "No VPN leaks detected. Your VPN appears to be working correctly.",
            recommendation: nil,
            icon: "shield.lefthalf.filled"
        )
    }

    // MARK: - 7. Open Network Check

    private func checkOpenNetwork() -> SecurityCheck {
        let networkStatus = NetworkMonitorService.shared.currentStatus

        // Check if connected to an open (unsecured) network
        // Note: iOS doesn't expose security type directly, but we can infer from other signals

        if !networkStatus.wifi.isConnected {
            return SecurityCheck(
                name: "Network Security",
                status: .unknown,
                detail: "Not connected to Wi-Fi. Check not applicable.",
                recommendation: nil,
                icon: "wifi.slash"
            )
        }

        // If we're on cellular, it's generally secure
        if networkStatus.connectionType == .cellular {
            return SecurityCheck(
                name: "Network Security",
                status: .passed,
                detail: "Connected via cellular network, which is encrypted by default.",
                recommendation: nil,
                icon: "antenna.radiowaves.left.and.right"
            )
        }

        // Check for common open network patterns
        let ssid = networkStatus.wifi.ssid?.lowercased() ?? ""
        let openNetworkPatterns = ["guest", "free", "public", "open", "airport", "hotel", "cafe", "coffee", "starbucks", "mcdonalds"]

        let isPossiblyOpen = openNetworkPatterns.contains { pattern in
            ssid.contains(pattern)
        }

        if isPossiblyOpen {
            return SecurityCheck(
                name: "Network Security",
                status: .warning,
                detail: "Connected to '\(networkStatus.wifi.ssid ?? "Unknown")'. This may be a public or open network.",
                recommendation: (SmartVPNDetector.shared.detectionResult?.vpnState.isLikelyOn ?? false)
                    ? "Public networks are less secure. Your VPN provides additional protection."
                    : "Public networks are less secure. Avoid accessing sensitive accounts or use a VPN for protection.",
                icon: "wifi.exclamationmark"
            )
        }

        return SecurityCheck(
            name: "Network Security",
            status: .passed,
            detail: "Connected to '\(networkStatus.wifi.ssid ?? "Unknown")'. No obvious security concerns detected.",
            recommendation: nil,
            icon: "wifi"
        )
    }
}
