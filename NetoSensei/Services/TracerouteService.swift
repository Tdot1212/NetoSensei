//
//  TracerouteService.swift
//  NetoSensei
//
//  Network path visualization using practical latency probes.
//  iOS cannot do true ICMP traceroute, so we measure latency
//  to known waypoints (gateway, DNS, CDN edge, VPN exit, destination).
//
//  Uses existing TracerouteHop / TracerouteResult models from
//  AdvancedDiagnosticResult.swift.
//

import Foundation
import Network

// MARK: - Service

@MainActor
class TracerouteService: ObservableObject {
    static let shared = TracerouteService()

    @Published var isRunning = false
    @Published var currentHop = 0
    @Published var hops: [TracerouteHop] = []
    @Published var result: TracerouteResult?
    @Published var error: String?

    private let maxHops = 30
    private let timeout: TimeInterval = 3.0
    private let probesPerHop = 3

    private init() {}

    // MARK: - True Traceroute (TCP TTL)

    /// Attempt real traceroute using TCP connect with incrementing TTL.
    /// Limited on iOS — cannot read intermediate router IPs from ICMP Time Exceeded,
    /// but can detect whether each hop responds and measure latency.
    func runTraceroute(to destination: String) async -> TracerouteResult {
        return await BackgroundTaskManager.shared.runInBackground(
            id: "traceroute",
            name: "Traceroute: \(destination)",
            operation: {
                return await self.performRunTraceroute(to: destination)
            },
            resultFormatter: { result in
                "\(result.hops.count) hops, \(String(format: "%.0f", result.totalLatency))ms"
            }
        )
    }

    private func performRunTraceroute(to destination: String) async -> TracerouteResult {
        isRunning = true
        currentHop = 0
        hops = []
        error = nil

        let resolvedIP = await resolveHostname(destination)
        let targetIP = resolvedIP ?? destination
        var collectedHops: [TracerouteHop] = []
        var previousLatency = 0.0

        for ttl in 1...maxHops {
            guard isRunning else { break }
            currentHop = ttl

            let (address, medianLatency) = await probeWithTTL(ttl: ttl, destination: targetIP)

            let latency = medianLatency ?? 0
            let hop = TracerouteHop(
                hopNumber: ttl,
                ipAddress: address ?? "*",
                hostname: nil,
                latency: latency,
                latencyChange: latency - previousLatency,
                asn: nil,
                isp: nil,
                location: nil
            )
            previousLatency = latency

            collectedHops.append(hop)
            hops = collectedHops

            // Reached destination
            if let addr = address, addr == targetIP { break }
        }

        // Enrich public hops with ASN info
        let enrichedHops = await enrichHopsWithASN(collectedHops)
        hops = enrichedHops

        let totalLatency = enrichedHops.last?.latency ?? 0

        let finalResult = TracerouteResult(
            timestamp: Date(),
            destination: destination,
            hops: enrichedHops,
            totalLatency: totalLatency
        )

        result = finalResult
        isRunning = false
        return finalResult
    }

    // MARK: - Practical Traceroute

    /// Reliable path visualization by probing known waypoints.
    /// Works within iOS sandbox limitations.
    func runPracticalTraceroute(vpnActive: Bool) async -> TracerouteResult {
        return await BackgroundTaskManager.shared.runInBackground(
            id: "traceroute",
            name: "Traceroute",
            operation: {
                return await self.performPracticalTraceroute(vpnActive: vpnActive)
            },
            resultFormatter: { result in
                "\(result.hops.count) hops, \(String(format: "%.0f", result.totalLatency))ms"
            }
        )
    }

    private func performPracticalTraceroute(vpnActive: Bool) async -> TracerouteResult {
        isRunning = true
        hops = []
        currentHop = 0
        error = nil

        var collectedHops: [TracerouteHop] = []
        var previousLatency = 0.0

        // Hop 1: Gateway (local router)
        currentHop = 1
        let gatewayIP = NetworkMonitorService.shared.currentStatus.router.gatewayIP ?? "192.168.1.1"
        let gatewayLatency = await measureLatency(to: gatewayIP, port: 80) ?? 0
        collectedHops.append(TracerouteHop(
            hopNumber: 1,
            ipAddress: gatewayIP,
            hostname: "Gateway",
            latency: gatewayLatency,
            latencyChange: gatewayLatency,
            asn: nil,
            isp: "Local Network",
            location: nil
        ))
        previousLatency = gatewayLatency
        hops = collectedHops

        // Hop 2: ISP DNS (measures DNS resolver round-trip)
        currentHop = 2
        let dnsLatency = await measureDNSLatency() ?? 0
        collectedHops.append(TracerouteHop(
            hopNumber: 2,
            ipAddress: "DNS",
            hostname: "DNS Resolver",
            latency: dnsLatency,
            latencyChange: dnsLatency - previousLatency,
            asn: nil,
            isp: "ISP DNS",
            location: nil
        ))
        previousLatency = dnsLatency
        hops = collectedHops

        // Hop 3: Cloudflare edge (nearest CDN PoP)
        currentHop = 3
        let cfLatency = await measureLatency(to: "1.1.1.1", port: 443) ?? 0
        collectedHops.append(TracerouteHop(
            hopNumber: 3,
            ipAddress: "1.1.1.1",
            hostname: "Cloudflare Edge",
            latency: cfLatency,
            latencyChange: cfLatency - previousLatency,
            asn: "AS13335",
            isp: "Cloudflare",
            location: nil
        ))
        previousLatency = cfLatency
        hops = collectedHops

        // Hop 4: VPN exit (if VPN active)
        if vpnActive {
            currentHop = 4
            let publicIP = NetworkMonitorService.shared.currentStatus.publicIP ?? ""
            var vpnISP: String? = "VPN Provider"
            var vpnASN: String?
            var vpnLocation: String?

            if !publicIP.isEmpty {
                let info = await lookupASN(ip: publicIP)
                vpnISP = info.isp ?? vpnISP
                vpnASN = info.asn
                vpnLocation = info.country
            }

            let vpnLatency = await measureHTTPLatency(to: "https://1.1.1.1/cdn-cgi/trace") ?? 0

            collectedHops.append(TracerouteHop(
                hopNumber: 4,
                ipAddress: publicIP.isEmpty ? "VPN" : publicIP,
                hostname: "VPN Exit",
                latency: vpnLatency,
                latencyChange: vpnLatency - previousLatency,
                asn: vpnASN,
                isp: vpnISP,
                location: vpnLocation
            ))
            previousLatency = vpnLatency
            hops = collectedHops
        }

        // Final hop: Internet destination
        let finalHopNum = collectedHops.count + 1
        currentHop = finalHopNum
        let finalLatency = await measureLatency(to: "www.google.com", port: 443) ?? 0
        collectedHops.append(TracerouteHop(
            hopNumber: finalHopNum,
            ipAddress: "www.google.com",
            hostname: "Destination",
            latency: finalLatency,
            latencyChange: finalLatency - previousLatency,
            asn: "AS15169",
            isp: "Google",
            location: "US"
        ))
        hops = collectedHops

        let totalLatency = collectedHops.last?.latency ?? 0

        let finalResult = TracerouteResult(
            timestamp: Date(),
            destination: "www.google.com",
            hops: collectedHops,
            totalLatency: totalLatency
        )

        result = finalResult
        isRunning = false
        return finalResult
    }

    func cancel() {
        isRunning = false
    }

    // MARK: - DNS Resolution

    private nonisolated func resolveHostname(_ hostname: String) async -> String? {
        if isValidIPv4(hostname) { return hostname }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let host = CFHostCreateWithName(nil, hostname as CFString).takeRetainedValue()
                CFHostStartInfoResolution(host, .addresses, nil)

                var success: DarwinBoolean = false
                if let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as? [Data],
                   success.boolValue {
                    for addressData in addresses {
                        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        addressData.withUnsafeBytes { ptr in
                            let sa = ptr.baseAddress!.assumingMemoryBound(to: sockaddr.self)
                            getnameinfo(sa, socklen_t(addressData.count),
                                        &buf, socklen_t(buf.count),
                                        nil, 0, NI_NUMERICHOST)
                        }
                        let ip = String(cString: buf)
                        if self.isValidIPv4(ip) {
                            continuation.resume(returning: ip)
                            return
                        }
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - TTL Probing

    private nonisolated func probeWithTTL(ttl: Int, destination: String) async -> (address: String?, latency: Double?) {
        var latencies: [Double] = []
        var respondingAddress: String?

        for _ in 0..<probesPerHop {
            let (addr, latency) = await tcpProbeWithTTL(ttl: ttl, destination: destination)
            if let lat = latency {
                latencies.append(lat)
            }
            if let a = addr, a != "*" {
                respondingAddress = a
            }
        }

        let median = latencies.isEmpty ? nil : latencies.sorted()[latencies.count / 2]
        return (respondingAddress, median)
    }

    private nonisolated func tcpProbeWithTTL(ttl: Int, destination: String) async -> (address: String?, latency: Double?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
                guard sock >= 0 else {
                    continuation.resume(returning: (nil, nil))
                    return
                }
                defer { close(sock) }

                // Set TTL
                var ttlValue = Int32(ttl)
                setsockopt(sock, IPPROTO_IP, IP_TTL, &ttlValue, socklen_t(MemoryLayout<Int32>.size))

                // Non-blocking
                let flags = fcntl(sock, F_GETFL, 0)
                _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

                // Destination
                var destAddr = sockaddr_in()
                destAddr.sin_family = sa_family_t(AF_INET)
                destAddr.sin_port = UInt16(80).bigEndian
                inet_pton(AF_INET, destination, &destAddr.sin_addr)

                let startTime = CFAbsoluteTimeGetCurrent()

                _ = withUnsafePointer(to: &destAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
                let pollResult = poll(&pfd, 1, Int32(self.timeout * 1000))

                let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

                if pollResult > 0 {
                    var err: Int32 = 0
                    var errLen = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &errLen)

                    if err == 0 {
                        continuation.resume(returning: (destination, latency))
                    } else if err == EHOSTUNREACH || err == ENETUNREACH {
                        continuation.resume(returning: ("*", latency))
                    } else {
                        continuation.resume(returning: ("*", latency))
                    }
                } else {
                    continuation.resume(returning: (nil, nil))
                }
            }
        }
    }

    // MARK: - Latency Measurement

    /// Thread-safe resume-once wrapper for NWConnection probes.
    private final class OnceGuard: @unchecked Sendable {
        private var _resumed = false
        private let lock = NSLock()

        func tryResume() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if _resumed { return false }
            _resumed = true
            return true
        }
    }

    private nonisolated func measureLatency(to host: String, port: UInt16) async -> Double? {
        let start = CFAbsoluteTimeGetCurrent()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let connection = NWConnection(to: endpoint, using: .tcp)

        return await withCheckedContinuation { continuation in
            let guard_ = OnceGuard()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
                    connection.cancel()
                    if guard_.tryResume() {
                        continuation.resume(returning: latency)
                    }
                case .failed, .cancelled:
                    if guard_.tryResume() {
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                connection.cancel()
                if guard_.tryResume() {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private nonisolated func measureHTTPLatency(to urlString: String) async -> Double? {
        guard let url = URL(string: urlString) else { return nil }
        let start = CFAbsoluteTimeGetCurrent()
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let _ = try await URLSession.shared.data(for: request)
            return (CFAbsoluteTimeGetCurrent() - start) * 1000
        } catch {
            return nil
        }
    }

    private nonisolated func measureDNSLatency() async -> Double? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let start = CFAbsoluteTimeGetCurrent()
                let randomHost = "traceroute-\(UInt32.random(in: 0...999999)).cloudflare.com"

                var hints = addrinfo(
                    ai_flags: AI_DEFAULT,
                    ai_family: AF_UNSPEC,
                    ai_socktype: SOCK_STREAM,
                    ai_protocol: 0,
                    ai_addrlen: 0,
                    ai_canonname: nil,
                    ai_addr: nil,
                    ai_next: nil
                )

                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(randomHost, nil, &hints, &result)
                if result != nil { freeaddrinfo(result) }

                let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
                continuation.resume(returning: (status == 0 || status == EAI_NONAME) ? latency : nil)
            }
        }
    }

    // MARK: - ASN Enrichment

    private nonisolated func enrichHopsWithASN(_ hops: [TracerouteHop]) async -> [TracerouteHop] {
        var enriched: [TracerouteHop] = []

        for hop in hops {
            let ip = hop.ipAddress
            guard ip != "*", !isPrivateIP(ip) else {
                enriched.append(hop)
                continue
            }

            let info = await lookupASN(ip: ip)

            enriched.append(TracerouteHop(
                hopNumber: hop.hopNumber,
                ipAddress: hop.ipAddress,
                hostname: info.hostname ?? hop.hostname,
                latency: hop.latency,
                latencyChange: hop.latencyChange,
                asn: info.asn ?? hop.asn,
                isp: info.isp ?? hop.isp,
                location: info.country ?? hop.location
            ))
        }

        return enriched
    }

    private nonisolated func lookupASN(ip: String) async -> (asn: String?, isp: String?, country: String?, hostname: String?) {
        guard let url = URL(string: "http://ip-api.com/json/\(ip)?fields=as,isp,countryCode,reverse") else {
            return (nil, nil, nil, nil)
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return (
                    json["as"] as? String,
                    json["isp"] as? String,
                    json["countryCode"] as? String,
                    json["reverse"] as? String
                )
            }
        } catch {}

        return (nil, nil, nil, nil)
    }

    // MARK: - Helpers

    private nonisolated func isValidIPv4(_ string: String) -> Bool {
        var addr = in_addr()
        return inet_pton(AF_INET, string, &addr) == 1
    }

    private nonisolated func isPrivateIP(_ ip: String) -> Bool {
        if ip.hasPrefix("10.") { return true }
        if ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        if ip.hasPrefix("169.254.") { return true }
        if ip.hasPrefix("127.") { return true }
        return false
    }
}
