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

    struct Counts {
        let proxyLike: Int, otherTrusted: Int, untrusted: Int, unavailable: Int
    }
    static func counts(_ inspections: [CertificateInspection]) -> Counts {
        let untrusted = inspections.filter { $0.severity == .critical }.count
        let unavailable = inspections.filter { $0.severity == .unavailable }.count
        let proxyLike = inspections.filter { $0.isProxyIntercepted && $0.severity != .critical && $0.severity != .unavailable }.count
        return Counts(proxyLike: proxyLike, otherTrusted: inspections.count-untrusted-unavailable-proxyLike,
                      untrusted: untrusted, unavailable: unavailable)
    }

    enum Severity {
        case info        // proxy MITM expected (user installed the CA themselves)
        case warning     // unknown / non-public issuer; user should check
        case critical    // trust failure outside of the proxy explanation
        case unavailable // Commit 7: host unreachable or intercepted — NOT assessed; never counts toward the verdict
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

    nonisolated static func map(host: String, result: TLSAnalysisResult, vpnActive: Bool) -> CertificateInspection {
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

        if let reason = result.unavailableReason {
            severity = .unavailable; summary = reason.text + "."
        } else if result.securityRating == .critical || result.certificateChain.contains(where: { !$0.isTrusted }) {
            severity = .critical
            summary = "Certificate trust evaluation failed. VPN state and issuer names do not establish trust."
        } else if result.isProxyMITM {
            severity = .warning
            summary = "The chain passed system trust, but a name resembles a proxy CA. Review whether local HTTPS decryption was intended."
        } else if result.securityRating == .poor || result.securityRating == .fair {
            severity = .warning; summary = "Review the assessed TLS configuration issues."
        } else {
            severity = .info; summary = "System trust evaluation passed for this hostname."
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
