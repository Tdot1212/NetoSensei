//
//  CaptivePortalDetector.swift
//  NetoSensei
//
//  Detects captive-portal interception by probing two well-known "is the
//  internet really open?" endpoints (Apple + Cloudflare) and comparing the
//  responses against the expected fingerprints.
//
//  Why a new file when PrivacyShieldService already has a captive-portal
//  helper? The existing helper is a private Bool-returning function used
//  inside a single check. The Run-Full-Security-Check flow needs a richer
//  result (URL, confidence, VPN-aware skip) — building a separate service
//  keeps that surface clean and reusable elsewhere.
//
//  iOS limits respected:
//   - No private network APIs: probes use plain HTTP via URLSession.
//   - Cannot inspect captive-portal HTML reliably; we judge by status
//     code, redirect target, and the presence of the expected body.
//

import Foundation

// MARK: - Result Types

struct CaptivePortalResult {
    enum Verdict {
        case noPortal               // direct internet
        case portalDetected         // probe redirected / body mismatched
        case inconclusiveVPNActive  // can't tell — traffic is tunneled
        case probeFailed            // network unreachable / timeout
    }

    enum Confidence: String {
        case high     // both probes agree
        case medium   // one probe agreed, one was inconclusive
        case low      // probes disagreed
    }

    let verdict: Verdict
    let portalURL: String?      // best-guess login URL (final redirect target)
    let confidence: Confidence
    let recommendation: String
    let probedAt: Date

    var isPortal: Bool { verdict == .portalDetected }
}

// MARK: - Service

@MainActor
final class CaptivePortalDetector {
    static let shared = CaptivePortalDetector()
    private init() {}

    // The two canonical endpoints. Both expose plaintext HTTP intentionally
    // (HTTPS would defeat captive-portal detection — the portal can't
    // intercept HTTPS without breaking trust).
    private struct Probe {
        let url: URL
        let expectedBodyContains: String
        let label: String
    }

    private let probes: [Probe] = [
        Probe(
            url: URL(string: "http://captive.apple.com/hotspot-detect.html")!,
            expectedBodyContains: "Success",
            label: "Apple"
        ),
        Probe(
            url: URL(string: "http://cp.cloudflare.com/")!,
            // Cloudflare returns a tiny success body. Empty 204 is also "no portal".
            expectedBodyContains: "",
            label: "Cloudflare"
        ),
    ]

    /// Detect captive-portal interception. When VPN is active we return
    /// `.inconclusiveVPNActive` rather than guess — the tunnel will route the
    /// probe through the VPN exit, where there's no portal to find.
    func detectCaptivePortal() async -> CaptivePortalResult {
        // VPN-aware skip: a captive portal sits between the device and the
        // upstream gateway, BEFORE any tunnel can be established. If a VPN
        // is reporting active, the tunnel either came up despite a portal
        // (possible if the user already logged in) or routes around it. Either
        // way the probe results would be misleading.
        let vpnActive = SmartVPNDetector.shared.detectionResult?.vpnState.isLikelyOn ?? false
        if vpnActive {
            return CaptivePortalResult(
                verdict: .inconclusiveVPNActive,
                portalURL: nil,
                confidence: .medium,
                recommendation: "Captive portal check is inconclusive while VPN is active. Disconnect VPN momentarily on a new network to test for a captive portal.",
                probedAt: Date()
            )
        }

        // Run both probes in parallel.
        async let appleResult = runProbe(probes[0])
        async let cloudflareResult = runProbe(probes[1])
        let (apple, cloudflare) = await (appleResult, cloudflareResult)

        return mergeProbes(apple: apple, cloudflare: cloudflare)
    }

    // MARK: - Per-probe outcome

    private enum ProbeOutcome {
        case open                        // expected body / 204
        case redirected(to: String)      // 3xx or 200 with mismatched body
        case failed                      // timeout / network error
    }

    private func runProbe(_ probe: Probe) async -> ProbeOutcome {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Don't follow redirects — we want to SEE the redirect target.
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: probe.url)
        request.httpMethod = "GET"
        // Some captive portals key off Apple's User-Agent. Mirror it for the
        // Apple probe; leave Cloudflare's default.
        if probe.label == "Apple" {
            request.setValue("CaptiveNetworkSupport-407.0.1 wispr", forHTTPHeaderField: "User-Agent")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed
            }

            // Captured redirect from delegate (if any).
            if let captured = delegate.capturedRedirectLocation {
                return .redirected(to: captured)
            }

            // 3xx without delegate fire (rare, but be defensive).
            if (300..<400).contains(http.statusCode) {
                let location = http.value(forHTTPHeaderField: "Location") ?? probe.url.absoluteString
                return .redirected(to: location)
            }

            // 204 No Content == "open" for Cloudflare-style probes.
            if http.statusCode == 204 {
                return .open
            }

            if http.statusCode == 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                if probe.expectedBodyContains.isEmpty || body.contains(probe.expectedBodyContains) {
                    return .open
                }
                // 200 with unexpected body == portal-served HTML.
                return .redirected(to: probe.url.absoluteString)
            }

            // Any other status (4xx/5xx) — probe failed; no claim either way.
            return .failed
        } catch {
            return .failed
        }
    }

    // MARK: - Merge two probe outcomes

    private func mergeProbes(apple: ProbeOutcome, cloudflare: ProbeOutcome) -> CaptivePortalResult {
        switch (apple, cloudflare) {
        case (.open, .open):
            return CaptivePortalResult(
                verdict: .noPortal, portalURL: nil, confidence: .high,
                recommendation: "No captive portal — the network grants direct internet access.",
                probedAt: Date()
            )

        case (.redirected(let url), .redirected):
            return CaptivePortalResult(
                verdict: .portalDetected, portalURL: url, confidence: .high,
                recommendation: "Captive portal redirect detected. Open the page in Safari to log in BEFORE enabling VPN — most VPNs can't connect through a captive portal.",
                probedAt: Date()
            )

        case (.redirected(let url), _), (_, .redirected(let url)):
            // One probe says portal, one says open or failed. Lean toward portal.
            return CaptivePortalResult(
                verdict: .portalDetected, portalURL: url, confidence: .low,
                recommendation: "One probe detected a captive portal redirect; the other was inconclusive. Try opening Safari — if a login page appears, the network requires authentication.",
                probedAt: Date()
            )

        case (.open, .failed), (.failed, .open):
            return CaptivePortalResult(
                verdict: .noPortal, portalURL: nil, confidence: .medium,
                recommendation: "No captive portal detected (one probe failed, one passed). Network appears open.",
                probedAt: Date()
            )

        case (.failed, .failed):
            return CaptivePortalResult(
                verdict: .probeFailed, portalURL: nil, confidence: .low,
                recommendation: "Could not reach captive-portal probe endpoints. Either you have no network connectivity, or both http://captive.apple.com and http://cp.cloudflare.com are blocked here.",
                probedAt: Date()
            )
        }
    }
}

// MARK: - URLSessionDelegate that captures (and blocks) redirects

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private(set) var capturedRedirectLocation: String?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        capturedRedirectLocation = request.url?.absoluteString
        // Returning nil cancels the redirect — we want to inspect, not follow.
        completionHandler(nil)
    }
}
