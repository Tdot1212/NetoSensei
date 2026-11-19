import Testing
import Foundation
import Darwin
@testable import NetoSensei

private final class DNSFixtureServer: @unchecked Sendable {
    let port: UInt16
    private let udp: Int32
    private let tcp: Int32
    init(truncated: Bool = false, unrelatedFirst: Bool = false, silent: Bool = false) throws {
        let udpFD = socket(AF_INET, SOCK_DGRAM, 0)
        udp = udpFD
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(udpFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0 else { throw URLError(.cannotConnectToHost) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(udpFD, $0, &length) } }
        port = UInt16(bigEndian: address.sin_port)
        tcp = socket(AF_INET, SOCK_STREAM, 0)
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(tcp, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        _ = listen(tcp, 1)
        let tcpFD = tcp
        DispatchQueue.global().async {
            var ready = pollfd(fd: udpFD, events: Int16(POLLIN), revents: 0)
            guard poll(&ready, 1, 3000) > 0 else { return }
            var bytes = [UInt8](repeating: 0, count: 4096), peer = sockaddr_storage()
            var size = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = withUnsafeMutablePointer(to: &peer) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(udpFD, &bytes, bytes.count, 0, $0, &size) }
            }
            guard count >= 12, !silent else { return }
            let query = Data(bytes.prefix(count))
            var response = DNSVerificationTests.answer(query)
            if truncated { response = query; response[2] = 0x83; response[3] = 0x80 }
            func sendPacket(_ data: Data) {
                data.withUnsafeBytes { dataBytes in
                    withUnsafePointer(to: &peer) { ptr in
                        _ = ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(udpFD, dataBytes.baseAddress, dataBytes.count, 0, $0, size) }
                    }
                }
            }
            if unrelatedFirst { var unrelated = response; unrelated[0] ^= 0xFF; sendPacket(unrelated) }
            sendPacket(response)
            if truncated {
                var tcpReady = pollfd(fd: tcpFD, events: Int16(POLLIN), revents: 0)
                guard poll(&tcpReady, 1, 2000) > 0 else { return }
                let client = accept(tcpFD, nil, nil)
                guard client >= 0 else { return }; defer { close(client) }
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var prefix = [UInt8](repeating: 0, count: 2)
                guard recv(client, &prefix, 2, MSG_WAITALL) == 2 else { return }
                var request = [UInt8](repeating: 0, count: Int(prefix[0]) << 8 | Int(prefix[1]))
                guard recv(client, &request, request.count, MSG_WAITALL) == request.count else { return }
                let answer = DNSVerificationTests.answer(Data(request))
                var framed = Data([UInt8(answer.count >> 8), UInt8(answer.count & 255)]); framed.append(answer)
                _ = framed.withUnsafeBytes { Darwin.send(client, $0.baseAddress, $0.count, 0) }
            }
        }
    }
    deinit { close(udp); close(tcp) }
}

struct DNSVerificationTests {
    static func answer(_ query: Data, code: UInt8 = 0) -> Data {
        var data = query
        data[2] = 0x81; data[3] = 0x80 | code
        data[6] = 0; data[7] = 1
        data.append(contentsOf: [0xC0,0x0C,0,1,0,1,0,0,0,60,0,4,203,0,113,9])
        return data
    }
    @Test func queryEncodingAndValidatedReply() throws {
        let query = try DNSWireCodec.query(domain: "example.com", id: 0x1234)
        #expect(Array(query.prefix(12)) == [0x12,0x34,1,0,0,1,0,0,0,0,0,0])
        #expect(Array(query.dropFirst(12)) == [7,101,120,97,109,112,108,101,3,99,111,109,0,0,1,0,1])
        let parsed = try DNSWireCodec.parse(Self.answer(query), matching: query)
        #expect(parsed.code == 0 && parsed.addresses == ["203.0.113.9"])
    }
    @Test func malformedTruncatedAndUnrelatedPacketsCannotPass() throws {
        let query = try DNSWireCodec.query(domain: "example.com", id: 42), response = Self.answer(query)
        for length in 0..<response.count {
            #expect(throws: (any Error).self) { try DNSWireCodec.parse(Data(response.prefix(length)), matching: query) }
        }
        var wrong = response; wrong[0] ^= 1
        #expect(throws: (any Error).self) { try DNSWireCodec.parse(wrong, matching: query) }
        var cycle = response; cycle[12] = 0xC0; cycle[13] = 12
        #expect(throws: (any Error).self) { try DNSWireCodec.parse(cycle, matching: query) }
        for invalid in ["", "a..com", String(repeating: "a", count: 64)+".com", "https://example.com"] {
            #expect(throws: (any Error).self) { try DNSWireCodec.query(domain: invalid, id: 1) }
        }
    }
    @Test func actualUDPQueryRoundTripAndTCPFallback() async throws {
        for tcp in [false, true] {
            let server = try DNSFixtureServer(truncated: tcp, unrelatedFirst: !tcp)
            let reply = await DNSWireClient().query(server: "127.0.0.1", port: server.port, domain: "example.com", timeout: 2)
            #expect(reply?.resolved == true && reply?.addresses == ["203.0.113.9"])
            #expect(reply?.latencyMs.isFinite == true)
            #expect(reply?.transport.contains(tcp ? "TCP" : "UDP") == true)
            withExtendedLifetime(server) {}
        }
    }
    @Test func unansweredDNSRequestIsUnavailableNotFast() async throws {
        let server = try DNSFixtureServer(silent: true)
        #expect(await DNSWireClient().query(server: "127.0.0.1", port: server.port, domain: "example.com", timeout: 0.05) == nil)
        #expect(await DNSWireClient().query(server: "not an address", domain: "example.com") == nil)
        withExtendedLifetime(server) {}
    }
    @Test func providerFailureNeverFallsBackToSystemAndIsNotRanked() async {
        let service = DNSBenchmarkService(environment: .init(query: { _,_ in nil },
            system: { _ in SystemDNSReply(addresses: ["1.2.3.4"], latencyMs: 1) }, vpn: { (true,"US") }))
        let result = await service.benchmark()
        #expect(result.fastestServer == nil)
        #expect(result.results.filter { $0.address != "system" }.allSatisfy { $0.failed && $0.latencyMs == nil })
        #expect(result.results.first?.latencyMs == 1)
        #expect(!result.results.contains { $0.isCached })
    }
    @Test func directMeanTieAndReliabilityAreHandled() async {
        let service = DNSBenchmarkService(environment: .init(query: { _,_ in DNSWireReply(responseCode: 0, addresses: ["1.2.3.4"], latencyMs: 20, transport: "UDP") },
            system: { _ in nil }, vpn: { (false,nil) }))
        let result = await service.benchmark()
        #expect(result.fastestServer == nil) // Equal observations do not establish a unique winner.
        #expect(result.results.filter { $0.address != "system" }.allSatisfy { $0.successRate == 1 && $0.latencyMs == 20 })
        let empty = DNSBenchmarkService.result(server: DNSBenchmarkService.servers[0], samples: [.nan, .infinity, -1], total: 3, fastest: false)
        #expect(empty.failed && empty.latencyMs == nil && empty.successRate == 0)
    }
    @MainActor @Test func DNSMetadataDoesNotInventGatewayResolverEncryptionOrLeak() async {
        let empty = await DNSAnalyzer(resolver: { nil }).runFullAnalysis()
        #expect(empty.systemDNS.isEmpty && empty.isEncryptedDNS == nil && empty.hasLeak == nil && empty.securityRating == .unknown)
        let known = await DNSAnalyzer(resolver: { "1.1.1.1" }).runFullAnalysis()
        #expect(known.systemDNS.first?.provider == .cloudflare && known.isEncryptedDNS == nil)
        #expect(DNSAnalyzer.identifyProvider(ip: "172.217.1.1") == .unknown)
        #expect(DNSAnalyzer.identifyProvider(ip: "172.16.1.1") == .local)
        #expect(DNSAnalyzer.identifyProvider(ip: "202.1.2.3") == .unknown)
    }
    @Test func DoHRequiresContentTypeAndMatchingDNSBody() throws {
        let query = try DNSWireCodec.query(domain: "example.com", id: 0)
        let url = URL(string: "https://example.test/dns-query")!
        let valid = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/dns-message"])!
        let html = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"text/html"])!
        #expect(DNSEncryptionChecker.validDoHResponse(data: Self.answer(query), response: valid, query: query))
        #expect(!DNSEncryptionChecker.validDoHResponse(data: Data(repeating: 65, count: 30), response: valid, query: query))
        #expect(!DNSEncryptionChecker.validDoHResponse(data: Self.answer(query), response: html, query: query))
    }
}

struct SystemDNSVerificationTests {
    @Test func systemResolverUsesActualAddressesAndRejectsInvalidDeadlines() async {
        let reply = await SystemDNSResolver.resolve("localhost")
        #expect(reply?.addresses.contains("127.0.0.1") == true || reply?.addresses.contains("::1") == true)
        #expect(reply.map { $0.latencyMs >= 0 } == true)
        #expect(await SystemDNSResolver.resolve("invalid/path") == nil)
        #expect(await SystemDNSResolver.resolve("localhost", timeout: 0) == nil)
        #expect(await SystemDNSResolver.resolve("localhost", timeout: .infinity) == nil)
    }
}
