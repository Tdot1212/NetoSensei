import Foundation
import Darwin

struct IPv4Subnet: Equatable {
    let address: UInt32
    let mask: UInt32
    init?(address: String, netmask: String) {
        guard let ip = Self.number(address), let bits = Self.number(netmask) else { return nil }
        let inverse = ~bits
        guard inverse & (inverse &+ 1) == 0 else { return nil }
        self.address = ip; mask = bits
    }
    var network: UInt32 { address & mask }
    var broadcast: UInt32 { network | ~mask }
    /// At most the local /24 slice, intersected with the actual interface mask.
    /// A partial scan is explicitly labelled; it never extends outside the subnet.
    var candidates: [String] {
        let low = max(network, address & 0xFFFFFF00)
        let high = min(broadcast, (address & 0xFFFFFF00) | 255)
        guard low <= high else { return [] }
        return (UInt64(low)...UInt64(high)).compactMap { wide in
            let value = UInt32(wide)
            guard value != address else { return nil }
            if ~mask > 1, value == network || value == broadcast { return nil }
            return Self.string(value)
        }
    }
    static func number(_ value: String) -> UInt32? {
        var address = in_addr()
        guard inet_pton(AF_INET, value, &address) == 1 else { return nil }
        return UInt32(bigEndian: address.s_addr)
    }
    static func string(_ value: UInt32) -> String {
        [24,16,8,0].map { String((value >> $0) & 255) }.joined(separator: ".")
    }
    static func activeWiFi() -> IPv4Subnet? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var cursor = list
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard String(cString: item.pointee.ifa_name) == "en0", let addr = item.pointee.ifa_addr,
                  let mask = item.pointee.ifa_netmask, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var addressText = [CChar](repeating: 0, count: Int(NI_MAXHOST)), maskText = addressText
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &addressText, socklen_t(addressText.count), nil, 0, NI_NUMERICHOST) == 0,
                  getnameinfo(mask, socklen_t(mask.pointee.sa_len), &maskText, socklen_t(maskText.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return IPv4Subnet(address: String(cString: addressText), netmask: String(cString: maskText))
        }
        return nil
    }
}
