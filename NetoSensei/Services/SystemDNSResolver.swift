import Foundation
import Darwin

struct SystemDNSReply: Sendable { let addresses: [String]; let latencyMs: Double }

enum SystemDNSResolver {
    static func resolve(_ domain: String, timeout: TimeInterval = 2) async -> SystemDNSReply? {
        guard TracerouteService.validHostname(domain), timeout.isFinite, timeout > 0, timeout <= 30 else { return nil }
        return await withCheckedContinuation { continuation in
            let completion = TimeoutContinuation(continuation)
            DispatchQueue.global(qos: .utility).async {
                let start = ProcessInfo.processInfo.systemUptime
                var hints = addrinfo(); hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(domain, nil, &hints, &result) == 0, let first = result else {
                    if let result { freeaddrinfo(result) }
                    completion.resume(returning: nil); return
                }
                defer { freeaddrinfo(first) }
                var cursor: UnsafeMutablePointer<addrinfo>? = first, addresses = Set<String>()
                while let item = cursor {
                    if let addr = item.pointee.ai_addr {
                        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(addr, item.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                            addresses.insert(String(cString: buffer))
                        }
                    }
                    cursor = item.pointee.ai_next
                }
                completion.resume(returning: addresses.isEmpty ? nil : SystemDNSReply(addresses: addresses.sorted(), latencyMs: (ProcessInfo.processInfo.systemUptime-start)*1000))
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now()+timeout) { completion.resume(returning: nil) }
        }
    }
}
