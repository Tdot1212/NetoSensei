//
//  NetworkLatencyProbe.swift
//  NetoSensei
//
//  Network-layer latency probe (the iOS-appropriate equivalent of ICMP ping).
//
//  Measures the TCP three-way-handshake round-trip time using a raw BSD
//  `connect()` made non-blocking and bounded by `poll()`. This is the same
//  proven-stable raw-socket technique already used by
//  NetworkMonitorService.performLocalPing / checkTCPPort — NOT NWConnection.
//
//  Why not NWConnection: every NWConnection-based latency probe in this app
//  (WiFiQualityEstimator, LatencyStabilityScanner, GatewaySecurityScanner,
//  DiagnosticsEngine, VPNBenchmarkEngine, PerformanceEngine) was disabled or
//  replaced because NWConnection repeatedly froze the app. A BSD-socket
//  `connect()` measures the identical quantity (time to complete the TCP
//  handshake) with no freeze risk and no third-party dependency.
//
//  The handshake RTT contains NO HTTP request, NO TLS handshake and NO DNS
//  lookup (targets are dialled by IP literal), so it reflects pure network
//  round-trip time. The dashboard shows this as the primary "Latency".
//  The previous HTTP-HEAD timing is kept separately as "App response time".
//

import Foundation

final class NetworkLatencyProbe: Sendable {
    static let shared = NetworkLatencyProbe()
    private init() {}

    // MARK: - Targets

    /// External anycast resolvers, dialled by IP literal (no DNS dependency).
    /// Port 443 is attempted first: it is almost never firewalled outbound, and
    /// we complete only the TCP handshake (never TLS), so it is a clean
    /// network-RTT sample. Port 53 is the fallback. These hosts run DoH/DoT,
    /// so a TCP handshake on :443 is accepted.
    private static let globalTargets: [(host: String, ports: [UInt16])] = [
        ("1.1.1.1", [443, 53]),   // Cloudflare
        ("8.8.8.8", [443, 53]),   // Google
        ("9.9.9.9", [443, 53])    // Quad9
    ]

    /// Mainland-China-reachable resolvers. Cloudflare / Google / Quad9 are
    /// throttled or blocked there and produce false-negative probe failures
    /// even on healthy connections (see NetworkMonitorService.getInternet),
    /// so when in-China-without-VPN we probe these first, then fall through to
    /// the global list.
    private static let domesticTargets: [(host: String, ports: [UInt16])] = [
        ("223.5.5.5", [443, 53]),        // AliDNS (DoH on 443)
        ("114.114.114.114", [53, 443]),  // 114DNS
        ("119.29.29.29", [53, 443])      // DNSPod / Tencent
    ]

    /// Per-target connect timeout. Kept tight so a blocked target falls through
    /// to the next one quickly rather than stalling the whole status update.
    private static let perTargetTimeout: TimeInterval = 2.0

    // MARK: - Public API

    /// Primary network-layer latency to the internet, in **seconds**.
    /// Returns nil only when every target failed. China-aware target ordering.
    func measureExternalLatency(preferDomestic: Bool) async -> TimeInterval? {
        let targets = preferDomestic
            ? Self.domesticTargets + Self.globalTargets
            : Self.globalTargets

        for target in targets {
            if let rtt = await measureHandshake(
                host: target.host,
                ports: target.ports,
                allowUDPFallback: false,
                timeout: Self.perTargetTimeout
            ) {
                return rtt
            }
        }
        return nil
    }

    /// Time a TCP handshake to `host` on the first port that accepts, in
    /// **seconds**. `allowUDPFallback` adds a last-resort UDP-association probe
    /// (for gateways that expose no open TCP port). Returns nil on total failure.
    func measureHandshake(
        host: String,
        ports: [UInt16],
        allowUDPFallback: Bool,
        timeout: TimeInterval
    ) async -> TimeInterval? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let start = Date()

                for port in ports {
                    if Self.tcpHandshakeSucceeds(host: host, port: port, timeout: timeout) {
                        continuation.resume(returning: Date().timeIntervalSince(start))
                        return
                    }
                }

                if allowUDPFallback, Self.udpReachable(host: host, port: 7, timeout: timeout) {
                    continuation.resume(returning: Date().timeIntervalSince(start))
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Raw socket helpers (non-blocking, poll-bounded)

    /// Non-blocking TCP connect with a hard `poll()` timeout.
    /// Returns true iff the three-way handshake completed within `timeout`.
    private static func tcpHandshakeSucceeds(host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }

        // Switch to non-blocking so connect() returns immediately with EINPROGRESS,
        // letting poll() enforce a real timeout (a blocking connect to a dropped
        // packet can otherwise hang for the OS default ~75s).
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else { return false }

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            return true  // Immediate completion (very fast paths)
        }
        guard errno == EINPROGRESS else { return false }

        // Wait (bounded) for the socket to become writable = handshake complete.
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ms = Int32(min(timeout, Double(Int32.max) / 1000.0) * 1000)
        let polled = poll(&pfd, 1, ms)
        guard polled > 0 else { return false }  // 0 = timeout, <0 = error

        // Confirm there was no asynchronous connect error (e.g. RST → ECONNREFUSED).
        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 else { return false }
        return soError == 0
    }

    /// UDP-association probe — succeeds when the kernel accepts the association.
    /// Used only as a last-resort gateway-reachability signal.
    private static func udpReachable(host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
