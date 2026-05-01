//
//  DNSEncryptionChecker.swift
//  NetoSensei
//
//  Probes DoH (port 443) and DoT (port 853) endpoints to verify they are
//  REACHABLE from this network. Honest about what it cannot detect:
//
//    On iOS, third-party apps cannot read the system's resolver
//    configuration. We CANNOT detect whether the user's device is
//    actually configured to USE encrypted DNS. We can only detect
//    whether DoH/DoT endpoints are reachable from this network — i.e.
//    whether the user COULD use them.
//
//  This service answers "can I use encrypted DNS here?", not "am I using
//  encrypted DNS?". The user-facing result must say so.
//

import Foundation
import Network

// MARK: - Result

struct DNSEncryptionResult {
    let dohReachable: Bool                  // any DoH endpoint succeeded
    let dotReachable: Bool                  // any DoT endpoint succeeded
    let probedDoHEndpoints: [String]
    let probedDoTEndpoints: [String]
    /// Always false on iOS today — we keep the field as documentation, so
    /// callers can't accidentally claim more than we know.
    let userConfigDetectable: Bool
    let recommendation: String
    let probedAt: Date
}

// MARK: - Service

@MainActor
final class DNSEncryptionChecker {
    static let shared = DNSEncryptionChecker()
    private init() {}

    private let dohEndpoints = [
        "https://1.1.1.1/dns-query",       // Cloudflare
        "https://dns.google/dns-query",    // Google
    ]
    private let dotEndpoints: [(host: String, port: UInt16)] = [
        ("1.1.1.1", 853),
        ("dns.google", 853),
    ]

    func checkDNSEncryption() async -> DNSEncryptionResult {
        async let dohResult = probeAllDoH()
        async let dotResult = probeAllDoT()
        let (dohReachable, dotReachable) = await (dohResult, dotResult)

        let recommendation: String = {
            switch (dohReachable, dotReachable) {
            case (true, true):
                return "Both DoH and DoT endpoints are reachable from this network. Whether your system is CONFIGURED to use them is not detectable from third-party apps on iOS. To verify or enable: Settings → General → VPN, DNS & Device Management → DNS → check active profile. Or install a DNS profile (NextDNS, Cloudflare 1.1.1.1 app, AdGuard)."
            case (true, false):
                return "DoH (port 443) reachable; DoT (port 853) is blocked on this network. Use a DoH-based DNS profile rather than DoT here."
            case (false, true):
                return "DoT (port 853) reachable; DoH endpoints unreachable — unusual. Check if HTTPS to 1.1.1.1 / dns.google is blocked."
            case (false, false):
                return "Neither DoH nor DoT endpoints reachable. This network may block encrypted DNS — your queries will fall back to plaintext. Consider a VPN to tunnel DNS."
            }
        }()

        return DNSEncryptionResult(
            dohReachable: dohReachable,
            dotReachable: dotReachable,
            probedDoHEndpoints: dohEndpoints,
            probedDoTEndpoints: dotEndpoints.map { "\($0.host):\($0.port)" },
            userConfigDetectable: false,   // iOS limit — see file header
            recommendation: recommendation,
            probedAt: Date()
        )
    }

    // MARK: - DoH probe

    /// Returns true if ANY DoH endpoint successfully answers a real DNS query.
    private func probeAllDoH() async -> Bool {
        // RFC 8484 GET form: /dns-query?dns=<base64url(query)> with
        // Accept: application/dns-message. Build a minimal A-record query for
        // example.com — small, well-known, every public resolver answers it.
        let query = buildDNSQuery(domain: "example.com")
        let base64 = query.base64URLEncodedString()

        async let r1 = probeOneDoH(endpoint: dohEndpoints[0], dnsParam: base64)
        async let r2 = probeOneDoH(endpoint: dohEndpoints[1], dnsParam: base64)
        let (a, b) = await (r1, r2)
        return a || b
    }

    private func probeOneDoH(endpoint: String, dnsParam: String) async -> Bool {
        guard var components = URLComponents(string: endpoint) else { return false }
        components.queryItems = [URLQueryItem(name: "dns", value: dnsParam)]
        guard let url = components.url else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 4

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            // Sanity-check the response is a DNS message: RFC 8484 §6 says
            // body MUST start with the 2-byte transaction ID followed by
            // flags. At minimum it should have the 12-byte DNS header.
            return data.count >= 12
        } catch {
            return false
        }
    }

    // MARK: - DoT probe

    /// Returns true if ANY DoT endpoint completes a TLS handshake on port 853.
    /// We don't send a query — just verifying the port is open + TLS works
    /// is enough to know "DoT is reachable from this network".
    private func probeAllDoT() async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            for endpoint in dotEndpoints {
                group.addTask {
                    await self.probeOneDoT(host: endpoint.host, port: endpoint.port)
                }
            }
            var any = false
            for await result in group {
                if result { any = true }
            }
            return any
        }
    }

    private func probeOneDoT(host: String, port: UInt16) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: false)
                return
            }
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
            let connection = NWConnection(to: endpoint, using: .tls)
            let flag = OnceFlag()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if flag.claim() {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled, .waiting:
                    if flag.claim() {
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                if flag.claim() {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Minimal DNS query builder

    /// Builds an A-record DNS query for `domain` per RFC 1035. Just enough to
    /// be a valid DoH payload — no compression, no EDNS.
    private func buildDNSQuery(domain: String) -> Data {
        var data = Data()
        // Header: random ID, standard query, recursion desired.
        let id = UInt16.random(in: 1...UInt16.max)
        data.append(UInt8(id >> 8))
        data.append(UInt8(id & 0xFF))
        data.append(contentsOf: [0x01, 0x00])  // flags: RD=1
        data.append(contentsOf: [0x00, 0x01])  // QDCOUNT=1
        data.append(contentsOf: [0x00, 0x00])  // ANCOUNT=0
        data.append(contentsOf: [0x00, 0x00])  // NSCOUNT=0
        data.append(contentsOf: [0x00, 0x00])  // ARCOUNT=0

        // QNAME: each label prefixed by length byte, terminated by 0x00.
        for label in domain.split(separator: ".") {
            let bytes = Array(label.utf8)
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        data.append(0x00)

        data.append(contentsOf: [0x00, 0x01])  // QTYPE=A
        data.append(contentsOf: [0x00, 0x01])  // QCLASS=IN
        return data
    }

    // MARK: - Once-guard for NWConnection callbacks

    private final class OnceFlag: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }
}

// MARK: - Base64URL helper (RFC 4648 §5: + → -, / → _, no padding)

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
