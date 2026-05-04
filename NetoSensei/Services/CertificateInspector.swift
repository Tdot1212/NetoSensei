//
//  CertificateInspector.swift
//  NetoSensei
//
//  Multi-host certificate inspection for the Run-Full-Security-Check flow.
//
//  This is a THIN WRAPPER over Services/TLSAnalyzer.swift, which already:
//   • Performs the URLSessionDelegate handshake to capture the chain
//     (SecTrustCopyCertificateChain, iOS 15+)
//   • Parses Subject/Issuer per CertificateInfo
//   • Runs isProxyMITMCert(chain) against the same proxy-CA list the spec
//     asks us to match (Surge/Shadowrocket/Quantumult/Clash/Loon/Stash/
//     mitmproxy/Charles/Proxyman/Fiddler/generated/proxy/debug)
//
//  We do not duplicate that work. CertificateInspector takes a host list,
//  fans out to TLSAnalyzer.shared.analyzeHost in parallel, and maps each
//  result into the compact CertificateInspection struct the security-check
//  sheet wants.
//
//  No certificate pinning. The verdict is "is the issuer a known proxy CA?",
//  not "is the cert exactly the one we expected?" — pinning would require
//  shipping and maintaining a real-cert database we don't want to own.
//

import Foundation

// MARK: - Result

struct CertificateInspection: Identifiable {
    let id = UUID()
    let hostname: String
    /// Issuer CN (best-effort — pulled from the leaf cert's Issuer field).
    /// "—" when the chain is empty / fetch failed.
    let realIssuer: String
    /// True when the leaf or any chain cert is signed by a known
    /// proxy-debugging CA (Surge / Shadowrocket / mitmproxy / etc).
    let isProxyIntercepted: Bool
    /// When `isProxyIntercepted`, our best guess at which app's CA it is.
    let proxyAppName: String?
    /// `info` for proxy MITM under VPN (expected), `warning` for unknown
    /// issuers, `critical` for trust-failure / expired / self-signed.
    let severity: Severity
    /// One-line user-facing label suitable for a row.
    let summary: String

    enum Severity {
        case info       // proxy MITM expected (user installed the CA themselves)
        case warning    // unknown / non-public issuer; user should check
        case critical   // trust failure outside of the proxy explanation
    }
}

// MARK: - Service

@MainActor
final class CertificateInspector {
    static let shared = CertificateInspector()
    private init() {}

    /// Default host list. Mix of:
    ///   • Apple (system trust, almost never proxied — gives us a baseline)
    ///   • Google (universal availability + reliable HTTPS)
    ///   • GitHub (developer staple)
    ///   • A bank — chase.com is widely accessible; we don't ship icbc.com.cn
    ///     by default because most users aren't ICBC customers and an extra
    ///     China-specific lookup adds latency on already-tunneled connections.
    /// `nonisolated` so it can be referenced as a default-argument value
    /// from outside the MainActor (Swift 6).
    nonisolated static let defaultHosts: [String] = [
        "apple.com",
        "google.com",
        "github.com",
        "chase.com",
    ]

    /// Inspect each host in parallel. Total wall-clock ≈ slowest single
    /// analyzeHost call (~3-6s per host, but they run concurrently).
    func inspectCertificates(hosts: [String] = defaultHosts) async -> [CertificateInspection] {
        // Capture VPN-active state on the MainActor before fan-out. The mapper
        // is nonisolated and can't read SmartVPNDetector.shared directly.
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false

        return await withTaskGroup(of: (Int, CertificateInspection).self) { group in
            for (index, host) in hosts.enumerated() {
                group.addTask {
                    let result = await TLSAnalyzer.shared.analyzeHost(host)
                    return (index, Self.map(host: host, result: result, vpnActive: vpnActive))
                }
            }

            var collected: [(Int, CertificateInspection)] = []
            for await pair in group {
                collected.append(pair)
            }
            // Preserve input order so the UI is stable across runs.
            return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // MARK: - TLSAnalysisResult → CertificateInspection
    // `nonisolated` because it's pure mapping — no MainActor state touched —
    // and the task group above calls it from a non-isolated context.

    private nonisolated static func map(host: String, result: TLSAnalysisResult, vpnActive: Bool) -> CertificateInspection {
        // Leaf cert is the first entry in the chain (TLSAnalyzer's contract).
        let leaf = result.certificateChain.first
        let issuerRaw = leaf?.issuer ?? "—"
        let issuerCN = extractCN(from: issuerRaw) ?? issuerRaw

        let proxyApp: String? = result.isProxyMITM
            ? identifyProxyApp(in: result.certificateChain)
            : nil

        // Severity tiering:
        //  • Proxy MITM detected by needle list → .info
        //  • Trust failed AND VPN active → reclassify as proxy interception
        //    (the proxy's CA is just not on our needle list)
        //  • Trust failed without VPN explanation → .critical
        //  • Good rating + known public CA → .info
        //  • Unknown issuer → .warning
        let severity: CertificateInspection.Severity
        let summary: String
        var displayIssuer = issuerCN
        var isProxyIntercepted = result.isProxyMITM

        if result.isProxyMITM {
            severity = .info
            let appLabel = proxyApp.map { " (\($0))" } ?? ""
            summary = "Proxy-intercepted\(appLabel) — your local proxy is decrypting and re-signing this connection. Normal if you installed the proxy CA. Concerning if you didn't."
        } else if result.certificateChain.isEmpty {
            severity = .critical
            summary = "Could not retrieve the certificate chain — the host may be unreachable or blocking inspection."
        } else if result.securityRating == .critical {
            // Trust failed. If VPN is active, the most likely cause is a proxy
            // re-signing certs with a CA not in our needle list. Treat as
            // proxy-intercepted (info), not critical.
            if vpnActive {
                severity = .info
                isProxyIntercepted = true
                displayIssuer = "Modified by VPN/proxy"
                summary = "Cert chain modified by VPN/proxy. This is normal if you installed the proxy's CA. Concerning if you didn't."
            } else {
                severity = .critical
                summary = "Trust evaluation failed. \(result.issues.first?.title ?? "Inspect details before trusting this connection.")"
            }
        } else if isKnownPublicIssuer(issuerCN) {
            severity = .info
            summary = "Real cert — issued by \(issuerCN)."
        } else {
            severity = .warning
            summary = "Unknown issuer (\(issuerCN)). Not on the known-public-CA list. Review before trusting."
        }

        return CertificateInspection(
            hostname: host,
            realIssuer: displayIssuer,
            isProxyIntercepted: isProxyIntercepted,
            proxyAppName: proxyApp,
            severity: severity,
            summary: summary
        )
    }

    // MARK: - Issuer classification helpers

    /// A short list of well-known public CAs we trust to render as "Real cert"
    /// without further qualification. Not a pinning database — just enough to
    /// avoid yellow-flagging every Let's Encrypt cert as "unknown issuer".
    private nonisolated static let knownPublicCANeedles: [String] = [
        "digicert", "let's encrypt", "lets encrypt", "isrg", "sectigo",
        "globalsign", "amazon", "google trust services", "gts ", "godaddy",
        "starfield", "entrust", "comodo", "thawte", "geotrust",
        "buypass", "actalis", "certum", "ssl.com", "trustcor",
        "apple", "microsoft",
    ]

    private nonisolated static func isKnownPublicIssuer(_ issuerCN: String) -> Bool {
        let lower = issuerCN.lowercased()
        return knownPublicCANeedles.contains { lower.contains($0) }
    }

    /// Walk the chain looking for a proxy-CA name. Returns the first match.
    /// CLEANUP 6: needles live in ProxyDetection.knownProxyApps.
    private nonisolated static func identifyProxyApp(in chain: [CertificateInfo]) -> String? {
        for cert in chain {
            let combined = (cert.subject + " " + cert.issuer).lowercased()
            if let match = ProxyDetection.detectProxyApp(in: combined) {
                return match.app
            }
        }
        return nil
    }

    /// Extract CN= value from an X.500 DN string. Handles the common case
    /// "CN=Some Name, O=..., C=US". Returns nil if no CN= field present.
    private nonisolated static func extractCN(from dn: String) -> String? {
        guard let range = dn.range(of: "CN=") else { return nil }
        let after = dn[range.upperBound...]
        if let comma = after.firstIndex(of: ",") {
            return String(after[..<comma]).trimmingCharacters(in: .whitespaces)
        }
        return String(after).trimmingCharacters(in: .whitespaces)
    }
}
