//
//  TLSIntegrityScanner.swift
//  NetoSensei
//
//  TLS/HTTPS Integrity Detection - 100% Real Detection
//  Detects: TLS MITM, certificate mismatches, SSL handshake failures, HTTPS interception
//

import Foundation
import Network

actor TLSIntegrityScanner {
    static let shared = TLSIntegrityScanner()

    private init() {}

    // MARK: - TLS Integrity Scan

    func performTLSIntegrityScan() async -> TLSIntegrityStatus {
        // Test multiple trusted HTTPS endpoints
        let testEndpoints = [
            "www.google.com",
            "www.cloudflare.com",
            "www.apple.com",
            "www.github.com",
            "www.amazon.com"
        ]

        var successfulHandshakes = 0
        var failedHandshakes = 0
        var certificateMismatches = 0
        var handshakeLatencies: [Double] = []

        for endpoint in testEndpoints {
            let result = await testTLSHandshake(endpoint: endpoint)

            switch result {
            case .success(let latency):
                successfulHandshakes += 1
                handshakeLatencies.append(latency)
            case .certificateMismatch:
                failedHandshakes += 1
                certificateMismatches += 1
            case .handshakeFailed:
                failedHandshakes += 1
            }
        }

        // Calculate average latency
        let avgLatency = handshakeLatencies.isEmpty ? 0.0 : handshakeLatencies.reduce(0, +) / Double(handshakeLatencies.count)

        // Normal TLS handshake should be < 500ms
        let handshakeLatencyNormal = avgLatency < 500.0

        // Calculate integrity score
        let integrityScore = calculateIntegrityScore(
            successCount: successfulHandshakes,
            failCount: failedHandshakes,
            certMismatches: certificateMismatches,
            avgLatency: avgLatency
        )

        return TLSIntegrityStatus(
            testEndpointCount: testEndpoints.count,
            successfulHandshakes: successfulHandshakes,
            failedHandshakes: failedHandshakes,
            certificateMismatches: certificateMismatches,
            handshakeLatencyAverage: avgLatency,
            handshakeLatencyNormal: handshakeLatencyNormal,
            integrityScore: integrityScore
        )
    }

    // MARK: - Test TLS Handshake

    fileprivate enum TLSTestResult {
        case success(latency: Double)
        case certificateMismatch
        case handshakeFailed
    }

    private func testTLSHandshake(endpoint: String) async -> TLSTestResult {
        return await withCheckedContinuation { continuation in
            // Use URLSession with certificate validation
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            let session = URLSession(configuration: config, delegate: TLSValidationDelegate { result in
                continuation.resume(returning: result)
            }, delegateQueue: nil)

            guard let url = URL(string: "https://\(endpoint)") else {
                continuation.resume(returning: .handshakeFailed)
                return
            }

            let startTime = Date()
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"  // Only headers, no body

            let task = session.dataTask(with: request) { _, response, error in
                _ = Date().timeIntervalSince(startTime) * 1000  // Convert to ms

                if error != nil {
                    // Error already handled by delegate
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 400 {
                        // Success - but result already sent by delegate
                        return
                    }
                }

                // If we get here and delegate hasn't responded, it's a failure
                // (but delegate should have already handled it)
            }

            task.resume()

            // Timeout after 10 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                session.invalidateAndCancel()
            }
        }
    }

    // MARK: - Calculate Integrity Score

    private func calculateIntegrityScore(
        successCount: Int,
        failCount: Int,
        certMismatches: Int,
        avgLatency: Double
    ) -> Int {
        var score = 100

        // Certificate mismatches are critical
        if certMismatches > 0 {
            score -= certMismatches * 30
        }

        // Failed handshakes are suspicious
        if failCount > 0 {
            score -= failCount * 15
        }

        // High latency is concerning
        if avgLatency > 1000 {
            score -= 20
        } else if avgLatency > 500 {
            score -= 10
        }

        // Success rate matters
        let totalTests = successCount + failCount
        if totalTests > 0 {
            let successRate = Double(successCount) / Double(totalTests)
            if successRate < 0.5 {
                score -= 25
            } else if successRate < 0.8 {
                score -= 10
            }
        }

        return max(0, min(100, score))
    }
}

// MARK: - TLS Validation Delegate

private class TLSValidationDelegate: NSObject, URLSessionDelegate {
    private let completion: (TLSIntegrityScanner.TLSTestResult) -> Void
    private var completed = false
    private var startTime = Date()

    init(completion: @escaping (TLSIntegrityScanner.TLSTestResult) -> Void) {
        self.completion = completion
        self.startTime = Date()
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard !completed else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check if this is a server trust challenge
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            guard let serverTrust = challenge.protectionSpace.serverTrust else {
                completed = true
                completion(.handshakeFailed)
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            // Evaluate server trust
            let policy = SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)
            SecTrustSetPolicies(serverTrust, policy)

            var cfError: CFError?
            let isValid = SecTrustEvaluateWithError(serverTrust, &cfError)

            if isValid {
                // Certificate is valid
                let latency = Date().timeIntervalSince(startTime) * 1000
                completed = true
                completion(.success(latency: latency))
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            } else {
                // Certificate validation failed - possible MITM
                completed = true
                completion(.certificateMismatch)
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        // For other authentication challenges, proceed with default handling
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed else { return }

        if let error = error {
            let nsError = error as NSError

            // Check for specific SSL errors
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorServerCertificateHasBadDate,
                     NSURLErrorServerCertificateUntrusted,
                     NSURLErrorServerCertificateHasUnknownRoot,
                     NSURLErrorServerCertificateNotYetValid:
                    completed = true
                    completion(.certificateMismatch)
                    return

                case NSURLErrorSecureConnectionFailed,
                     NSURLErrorClientCertificateRejected,
                     NSURLErrorClientCertificateRequired:
                    completed = true
                    completion(.handshakeFailed)
                    return

                default:
                    break
                }
            }

            // Generic error
            completed = true
            completion(.handshakeFailed)
        } else {
            // Success without error
            if !completed {
                let latency = Date().timeIntervalSince(startTime) * 1000
                completed = true
                completion(.success(latency: latency))
            }
        }
    }
}
