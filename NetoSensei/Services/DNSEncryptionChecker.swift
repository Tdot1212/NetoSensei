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
                return "Both transport tests returned validated DNS replies. Current DNS configuration is not verified. Review the active system DNS profile or your VPN app’s DNS settings."
            case (true, false):
                return "A DoH test returned a validated DNS reply. No DoT test completed successfully; blocking and system DNS configuration are unverified."
            case (false, true):
                return "A DoT test returned a validated DNS reply. No DoH test completed successfully; cause and system DNS configuration are unverified."
            case (false, false):
                return "No tested endpoint returned a validated encrypted-DNS reply. This does not establish blocking, plaintext fallback, or the transport used by other apps. Check the configured DNS profile."
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
        guard let query = try? DNSWireCodec.query(domain: "example.com", id: 0) else { return false }
        let base64 = query.base64URLEncodedString()

        async let r1 = probeOneDoH(endpoint: dohEndpoints[0], dnsParam: base64, query: query)
        async let r2 = probeOneDoH(endpoint: dohEndpoints[1], dnsParam: base64, query: query)
        let (a, b) = await (r1, r2)
        return a || b
    }

    private func probeOneDoH(endpoint: String, dnsParam: String, query: Data) async -> Bool {
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
            return Self.validDoHResponse(data: data, response: http, query: query)
        } catch {
            return false
        }
    }

    // MARK: - DoT probe

    /// Requires a validated DNS reply over the same system-trusted TLS connection.
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
        guard let query = try? DNSWireCodec.query(domain: "example.com", id: 0),
              let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(to: .hostPort(host: NWEndpoint.Host(host), port: nwPort), using: .tls)
            let flag = OnceFlag()
            let finish: @Sendable (Bool) -> Void = { success in
                if flag.claim() { connection.cancel(); continuation.resume(returning: success) }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let framed = Data([UInt8(query.count >> 8),UInt8(query.count & 255)]) + query
                    connection.send(content: framed, completion: .contentProcessed { error in
                        guard error == nil else { finish(false); return }
                        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { prefix,_,_,_ in
                            guard let prefix, prefix.count == 2 else { finish(false); return }
                            let size = Int(prefix[prefix.startIndex])*256 + Int(prefix[prefix.startIndex+1])
                            guard size >= 12 else { finish(false); return }
                            connection.receive(minimumIncompleteLength: size, maximumLength: size) { body,_,_,_ in
                                finish(body.map { Self.validDoTResponse(prefix: prefix, body: $0, query: query) } ?? false)
                            }
                        }
                    })
                case .failed, .cancelled, .waiting: finish(false)
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now()+4) { finish(false) }
        }
    }

    nonisolated static func validDoTResponse(prefix: Data, body: Data, query: Data) -> Bool {
        guard prefix.count == 2, body.count == Int(prefix[prefix.startIndex])*256 + Int(prefix[prefix.startIndex+1]),
              let reply = try? DNSWireCodec.parse(body, matching: query) else { return false }
        return reply.code == 0 && !reply.addresses.isEmpty
    }

    nonisolated static func validDoHResponse(data: Data, response: HTTPURLResponse, query: Data) -> Bool {
        guard response.statusCode == 200, response.mimeType?.lowercased() == "application/dns-message" else { return false }
        guard let reply = try? DNSWireCodec.parse(data, matching: query) else { return false }
        return reply.code == 0 && !reply.addresses.isEmpty
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
