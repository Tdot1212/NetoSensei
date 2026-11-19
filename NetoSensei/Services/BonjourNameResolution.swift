import Foundation
import Darwin

/// Resolves advertised instances through the OS DNS-SD resolver. The caller
/// associates names only with addresses it already observed on the same scan.
@MainActor
final class BonjourNameResolution: NSObject, NetServiceDelegate {
    private let service: NetService
    private var result: CheckedContinuation<[String], Never>?

    init(advertisement: NetworkDeviceDiscovery.BonjourDevice) {
        let type = advertisement.serviceType
        service = NetService(domain: advertisement.domain, type: type.hasSuffix(".") ? type : type + ".", name: advertisement.name)
    }

    func resolve() async -> [String] {
        await withCheckedContinuation { continuation in
            result = continuation
            service.delegate = self
            service.resolve(withTimeout: 2)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2.5))
                self?.finish([])
            }
        }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let addresses = (sender.addresses ?? []).compactMap(Self.ipv4)
        Task { @MainActor in finish(addresses) }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Task { @MainActor in finish([]) }
    }

    private func finish(_ addresses: [String]) {
        guard let result else { return }
        self.result = nil
        service.delegate = nil
        service.stop()
        result.resume(returning: addresses)
    }

    nonisolated private static func ipv4(_ data: Data) -> String? {
        guard data.count >= MemoryLayout<sockaddr_in>.size else { return nil }
        let address = data.withUnsafeBytes { $0.loadUnaligned(as: sockaddr_in.self) }
        guard address.sin_family == sa_family_t(AF_INET) else { return nil }
        return IPv4Subnet.string(UInt32(bigEndian: address.sin_addr.s_addr))
    }
}
