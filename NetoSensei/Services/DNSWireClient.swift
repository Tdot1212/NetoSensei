import Foundation
import Darwin

struct DNSWireReply: Sendable {
    let responseCode: UInt8
    let addresses: [String]
    let latencyMs: Double
    let transport: String
    var resolved: Bool { responseCode == 0 && !addresses.isEmpty }
}

enum DNSWireError: Error { case invalidDomain, malformed, mismatched, truncated }

/// RFC 1035 A queries. The transport measures a validated reply, never socket setup.
enum DNSWireCodec {
    static func query(domain: String, id: UInt16) throws -> Data {
        guard TracerouteService.validHostname(domain), domain.utf8.count <= 253 else { throw DNSWireError.invalidDomain }
        var bytes: [UInt8] = [UInt8(id >> 8), UInt8(id & 255), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in domain.lowercased().split(separator: ".") {
            bytes.append(UInt8(label.utf8.count)); bytes.append(contentsOf: label.utf8)
        }
        bytes.append(contentsOf: [0, 0, 1, 0, 1])
        return Data(bytes)
    }

    static func parse(_ data: Data, matching query: Data) throws -> (code: UInt8, addresses: [String]) {
        let bytes = Array(data), sent = Array(query)
        guard bytes.count >= 12, sent.count >= 17 else { throw DNSWireError.malformed }
        func word(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
        guard bytes[0] == sent[0], bytes[1] == sent[1], word(2) & 0xF800 == 0x8000 else { throw DNSWireError.mismatched }
        if word(2) & 0x0200 != 0 { throw DNSWireError.truncated }
        guard word(4) == 1 else { throw DNSWireError.malformed }
        var offset = 12, expectedOffset = 12
        let question = try name(bytes, offset: &offset)
        let expected = try name(sent, offset: &expectedOffset)
        guard offset + 4 <= bytes.count, expectedOffset + 4 <= sent.count,
              question == expected, Array(bytes[offset..<offset+4]) == Array(sent[expectedOffset..<expectedOffset+4]) else { throw DNSWireError.mismatched }
        offset += 4
        let answers = word(6), recordCount = answers + word(8) + word(10)
        var addresses: [String] = []
        for index in 0..<recordCount {
            _ = try name(bytes, offset: &offset)
            guard offset + 10 <= bytes.count else { throw DNSWireError.malformed }
            let type = word(offset), klass = word(offset+2), count = word(offset+8)
            offset += 10
            guard offset + count <= bytes.count else { throw DNSWireError.malformed }
            if index < answers, klass == 1, type == 1, count == 4 {
                addresses.append(bytes[offset..<offset+4].map(String.init).joined(separator: "."))
            }
            offset += count
        }
        return (UInt8(word(2) & 15), addresses)
    }

    private static func name(_ bytes: [UInt8], offset: inout Int) throws -> String {
        var labels: [String] = [], cursor = offset, jumped = false, visited = Set<Int>(), length = 0
        while true {
            guard cursor < bytes.count, visited.insert(cursor).inserted else { throw DNSWireError.malformed }
            let size = Int(bytes[cursor])
            if size & 0xC0 == 0xC0 {
                guard cursor + 1 < bytes.count else { throw DNSWireError.malformed }
                let target = (size & 63) << 8 | Int(bytes[cursor + 1])
                guard target < cursor else { throw DNSWireError.malformed }
                if !jumped { offset = cursor + 2; jumped = true }
                cursor = target; continue
            }
            guard size <= 63 else { throw DNSWireError.malformed }
            cursor += 1
            if size == 0 { if !jumped { offset = cursor }; break }
            guard cursor + size <= bytes.count else { throw DNSWireError.malformed }
            length += size + 1
            guard length <= 254, let label = String(bytes: bytes[cursor..<cursor+size], encoding: .ascii) else { throw DNSWireError.malformed }
            labels.append(label.lowercased()); cursor += size
        }
        return labels.joined(separator: ".")
    }
}

struct DNSWireClient: Sendable {
    func query(server: String, port: UInt16 = 53, domain: String, timeout: TimeInterval = 2) async -> DNSWireReply? {
        guard timeout.isFinite, timeout > 0, timeout <= 30, port > 0,
              let packet = try? DNSWireCodec.query(domain: domain, id: UInt16.random(in: 1...UInt16.max)) else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.perform(server: server, port: port, packet: packet, timeout: timeout))
            }
        }
    }

    private static func perform(server: String, port: UInt16, packet: Data, timeout: TimeInterval) -> DNSWireReply? {
        let start = ProcessInfo.processInfo.systemUptime, deadline = start + timeout
        guard let fd = open(server: server, port: port, stream: false, deadline: deadline) else { return nil }
        defer { close(fd) }
        let sent = packet.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
        guard sent == packet.count else { return nil }
        var buffer = [UInt8](repeating: 0, count: 65535)
        while ready(fd, event: Int16(POLLIN), deadline: deadline) {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { return nil }
            do {
                let parsed = try DNSWireCodec.parse(Data(buffer.prefix(count)), matching: packet)
                return DNSWireReply(responseCode: parsed.code, addresses: parsed.addresses,
                    latencyMs: (ProcessInfo.processInfo.systemUptime-start)*1000, transport: "UDP")
            } catch DNSWireError.truncated {
                return tcp(server: server, port: port, packet: packet, start: start, deadline: deadline)
            } catch { continue } // Ignore unrelated or malformed datagrams until the budget expires.
        }
        return nil
    }

    private static func tcp(server: String, port: UInt16, packet: Data, start: Double, deadline: Double) -> DNSWireReply? {
        guard let fd = open(server: server, port: port, stream: true, deadline: deadline) else { return nil }
        defer { close(fd) }
        var outgoing = Data([UInt8(packet.count >> 8), UInt8(packet.count & 255)])
        outgoing.append(packet)
        var sent = 0
        while sent < outgoing.count, ready(fd, event: Int16(POLLOUT), deadline: deadline) {
            let count = outgoing.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!.advanced(by: sent), $0.count-sent, 0) }
            guard count > 0 else { return nil }; sent += count
        }
        guard sent == outgoing.count, let prefix = read(fd, count: 2, deadline: deadline) else { return nil }
        let count = Int(prefix[0]) << 8 | Int(prefix[1])
        guard count >= 12, let response = read(fd, count: count, deadline: deadline),
              let parsed = try? DNSWireCodec.parse(response, matching: packet) else { return nil }
        return DNSWireReply(responseCode: parsed.code, addresses: parsed.addresses,
            latencyMs: (ProcessInfo.processInfo.systemUptime-start)*1000, transport: "TCP (after UDP truncation)")
    }

    private static func read(_ fd: Int32, count: Int, deadline: Double) -> Data? {
        var data = Data(), buffer = [UInt8](repeating: 0, count: count)
        while data.count < count, ready(fd, event: Int16(POLLIN), deadline: deadline) {
            let received = recv(fd, &buffer, count-data.count, 0)
            guard received > 0 else { return nil }
            data.append(contentsOf: buffer.prefix(received))
        }
        return data.count == count ? data : nil
    }

    private static func ready(_ fd: Int32, event: Int16, deadline: Double) -> Bool {
        var pfd = pollfd(fd: fd, events: event, revents: 0)
        let remaining = deadline-ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return false }
        return poll(&pfd, 1, Int32(min(remaining*1000, 30_000).rounded(.up))) > 0 && pfd.revents & event != 0
    }

    private static func open(server: String, port: UInt16, stream: Bool, deadline: Double) -> Int32? {
        var v4 = sockaddr_in(), v6 = sockaddr_in6()
        let family: Int32
        if inet_pton(AF_INET, server, &v4.sin_addr) == 1 {
            family = AF_INET; v4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); v4.sin_family = sa_family_t(AF_INET); v4.sin_port = port.bigEndian
        } else if inet_pton(AF_INET6, server, &v6.sin6_addr) == 1 {
            family = AF_INET6; v6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size); v6.sin6_family = sa_family_t(AF_INET6); v6.sin6_port = port.bigEndian
        } else { return nil }
        let fd = socket(family, stream ? SOCK_STREAM : SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        let result: Int32
        if family == AF_INET {
            result = withUnsafePointer(to: &v4) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        } else {
            result = withUnsafePointer(to: &v6) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) } }
        }
        if result != 0 {
            guard errno == EINPROGRESS, ready(fd, event: Int16(POLLOUT), deadline: deadline) else { close(fd); return nil }
            var error: Int32 = 0, size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { close(fd); return nil }
        }
        return fd
    }
}
