import Testing
import Foundation
import Darwin
@testable import NetoSensei

private final class LocalHTTPFixture: @unchecked Sendable {
    let port: UInt16
    private let fd: Int32
    init(earlyResponse: Bool = false, probeOnly: Bool = false) throws {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw FixtureError.socket }
        fd = socketFD
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(socketFD, 2) == 0 else { close(socketFD); throw FixtureError.socket }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &length) } }
        port = UInt16(bigEndian: address.sin_port)
        DispatchQueue.global().async {
            var pollFD = pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0)
            guard poll(&pollFD, 1, 10000) > 0 else { return }
            let client = accept(socketFD, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            if probeOnly { return }
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var received = Data(), buffer = [UInt8](repeating: 0, count: 65536)
            var expected: Int?
            while received.count < 25_000_000 {
                let n = recv(client, &buffer, buffer.count, 0)
                guard n > 0 else { break }
                received.append(contentsOf: buffer.prefix(n))
                if expected == nil, let range = received.range(of: Data("\r\n\r\n".utf8)) {
                    let headers = String(data: received[..<range.lowerBound], encoding: .utf8) ?? ""
                    let contentLength = headers.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                        .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                    expected = range.upperBound + contentLength
                    if earlyResponse { break }
                }
                if let expected, received.count >= expected { break }
            }
            let response = Array("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK".utf8)
            _ = response.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
        }
    }
    deinit { close(fd) }
    enum FixtureError: Error { case socket }
}
struct LocalTransferVerificationTests {
    @Test func uploadCountsBytesActuallySentOverLocalSocket() async throws {
        let server = try LocalHTTPFixture()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/upload")!)
        request.httpMethod = "POST"; request.httpBody = Data(repeating: 0x55, count: 2_000_000)
        let (response, sent) = try await UploadTransfer.perform(session: session, request: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(sent == 2_000_000)
        withExtendedLifetime(server) {}
    }
    @Test func earlySuccessResponseDoesNotProveFullUpload() async throws {
        let server = try LocalHTTPFixture(earlyResponse: true)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/early")!)
        request.httpMethod = "POST"; request.httpBody = Data(repeating: 0x55, count: 20_000_000)
        do {
            let (_, sent) = try await UploadTransfer.perform(session: session, request: request)
            #expect(sent < 20_000_000)
        } catch { #expect(error is URLError) }
        withExtendedLifetime(server) {}
    }
    @MainActor @Test func scannerDetectsActualListenerAndDoesNotCallSilenceSafe() async throws {
        let server = try LocalHTTPFixture(probeOnly: true)
        let scanner = PortScanner()
        let result = await scanner.scanDevice(ip: "127.0.0.1", ports: [server.port, server.port, 0])
        #expect(result.openPorts.count == 1 && result.openPorts.first?.port == server.port)
        #expect(result.openPorts.first?.responseTimeMs.map { $0 >= 0 } == true)
        #expect(scanner.progress == 1 && !scanner.isScanning)
        scanner.clearResults(); #expect(scanner.results.isEmpty && scanner.currentDeviceResult == nil)
        let empty = DeviceScanResult(ipAddress: "127.0.0.1", hostname: nil, openPorts: [], scanDuration: 1, timestamp: Date())
        #expect(empty.riskLevel == .info && empty.riskSummary.contains("responded"))
        withExtendedLifetime(server) {}
    }
}
