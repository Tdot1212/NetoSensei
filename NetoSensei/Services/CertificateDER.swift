import Foundation
import Security

/// Bounded DER parsing of X.509 fields; bytes inside unrelated extensions are not dates/serials.
enum CertificateDER {
    struct Metadata {
        let subject: String
        let issuer: String
        let serial: String
        let validFrom: Date?
        let validTo: Date?
        let isCA: Bool
        let tbs: Data
        let signatureOID: [UInt8]
        let signature: Data
    }
    private struct Node {
        let tag: UInt8
        let encoded: Range<Int>
        let content: Range<Int>
    }
    static func metadata(_ data: Data) -> Metadata? {
        let bytes = Array(data)
        guard let root = node(bytes, at: 0, limit: bytes.count), root.tag == 0x30, root.encoded.upperBound == bytes.count,
              let certificate = children(bytes, root), certificate.count == 3,
              let fields = children(bytes, certificate[0]), certificate[0].tag == 0x30 else { return nil }
        let base = fields.first?.tag == 0xA0 ? 1 : 0
        guard fields.count >= base+6, fields[base].tag == 0x02,
              let validity = children(bytes, fields[base+3]), validity.count == 2,
              let signatureFields = children(bytes, certificate[1]), let oid = signatureFields.first, oid.tag == 0x06,
              certificate[2].tag == 0x03, bytes[certificate[2].content].first == 0 else { return nil }
        var serial = Array(bytes[fields[base].content])
        while serial.count > 1 && serial.first == 0 { serial.removeFirst() }
        guard !serial.isEmpty else { return nil }
        var isCA = false
        for field in fields.dropFirst(base+6) where field.tag == 0xA3 {
            guard let wrapped = children(bytes, field), let extensions = wrapped.first,
                  let entries = children(bytes, extensions) else { return nil }
            for item in entries {
                guard let parts = children(bytes, item), let key = parts.first, let value = parts.last else { return nil }
                if key.tag == 6, Array(bytes[key.content]) == [0x55,0x1D,0x13], value.tag == 4,
                   let sequence = node(bytes, at: value.content.lowerBound, limit: value.content.upperBound),
                   let constraints = children(bytes, sequence), let flag = constraints.first, flag.tag == 1 {
                    isCA = Array(bytes[flag.content]) == [0xFF]
                }
            }
        }
        return Metadata(subject: distinguishedName(bytes, fields[base+4]), issuer: distinguishedName(bytes, fields[base+2]),
            serial: serial.map { String(format: "%02X", $0) }.joined(separator: ":"),
            validFrom: time(bytes, validity[0]), validTo: time(bytes, validity[1]), isCA: isCA,
            tbs: Data(bytes[certificate[0].encoded]), signatureOID: Array(bytes[oid.content]),
            signature: Data(bytes[certificate[2].content.dropFirst()]))
    }
    static func info(_ certificate: SecCertificate, trusted: Bool) -> CertificateInfo {
        let parsed = metadata(SecCertificateCopyData(certificate) as Data)
        var keyInfo = "Unavailable", selfSigned = false
        if let key = SecCertificateCopyKey(certificate) {
            if let attributes = SecKeyCopyAttributes(key) as? [String: Any],
               let size = attributes[kSecAttrKeySizeInBits as String] as? Int {
                let type = attributes[kSecAttrKeyType as String] as? String
                let name = type == (kSecAttrKeyTypeRSA as String) ? "RSA" : type == (kSecAttrKeyTypeECSECPrimeRandom as String) ? "EC" : "Key"
                keyInfo = "\(name) \(size) bits"
            }
            if let parsed, parsed.subject == parsed.issuer, let algorithm = signatureAlgorithm(parsed.signatureOID),
               SecKeyIsAlgorithmSupported(key, .verify, algorithm) {
                selfSigned = SecKeyVerifySignature(key, algorithm, parsed.tbs as CFData, parsed.signature as CFData, nil)
            }
        }
        return CertificateInfo(subject: parsed?.subject ?? (SecCertificateCopySubjectSummary(certificate) as String? ?? "Unavailable"),
            issuer: parsed?.issuer ?? "Unavailable", serialNumber: parsed?.serial ?? "Unavailable",
            validFrom: parsed?.validFrom, validTo: parsed?.validTo, publicKeyInfo: keyInfo,
            isSelfSigned: selfSigned, isRootCA: selfSigned && parsed?.isCA == true, isTrusted: trusted)
    }
    private static func signatureAlgorithm(_ oid: [UInt8]) -> SecKeyAlgorithm? {
        switch oid {
        case [0x2A,0x86,0x48,0x86,0xF7,0x0D,1,1,5]: return .rsaSignatureMessagePKCS1v15SHA1
        case [0x2A,0x86,0x48,0x86,0xF7,0x0D,1,1,11]: return .rsaSignatureMessagePKCS1v15SHA256
        case [0x2A,0x86,0x48,0x86,0xF7,0x0D,1,1,12]: return .rsaSignatureMessagePKCS1v15SHA384
        case [0x2A,0x86,0x48,0x86,0xF7,0x0D,1,1,13]: return .rsaSignatureMessagePKCS1v15SHA512
        case [0x2A,0x86,0x48,0xCE,0x3D,4,3,2]: return .ecdsaSignatureMessageX962SHA256
        case [0x2A,0x86,0x48,0xCE,0x3D,4,3,3]: return .ecdsaSignatureMessageX962SHA384
        case [0x2A,0x86,0x48,0xCE,0x3D,4,3,4]: return .ecdsaSignatureMessageX962SHA512
        default: return nil
        }
    }
    private static func node(_ bytes: [UInt8], at start: Int, limit: Int) -> Node? {
        guard start >= 0, limit <= bytes.count, start+2 <= limit else { return nil }
        var cursor = start+2, length = Int(bytes[start+1])
        if length & 128 != 0 {
            let count = length & 127
            guard count > 0, count <= 4, cursor+count <= limit, bytes[cursor] != 0 else { return nil }
            length = 0
            for b in bytes[cursor..<cursor+count] { length = length*256+Int(b) }
            cursor += count
            guard length >= 128 else { return nil }
        }
        guard length <= limit-cursor else { return nil }
        return Node(tag: bytes[start], encoded: start..<cursor+length, content: cursor..<cursor+length)
    }
    private static func children(_ bytes: [UInt8], _ parent: Node) -> [Node]? {
        var cursor = parent.content.lowerBound, result: [Node] = []
        while cursor < parent.content.upperBound {
            guard let child = node(bytes, at: cursor, limit: parent.content.upperBound) else { return nil }
            result.append(child); cursor = child.encoded.upperBound
        }
        return result
    }
    private static func distinguishedName(_ bytes: [UInt8], _ name: Node) -> String {
        guard let sets = children(bytes, name) else { return "Unavailable" }
        var values: [String] = []
        for set in sets {
            guard let attributes = children(bytes, set) else { continue }
            for attribute in attributes {
                guard let parts = children(bytes, attribute), parts.count == 2, parts[0].tag == 6 else { continue }
                let oid = Array(bytes[parts[0].content])
                let title: String
                switch oid {
                case [0x55,4,3]: title = "CN"
                case [0x55,4,6]: title = "C"
                case [0x55,4,10]: title = "O"
                case [0x55,4,11]: title = "OU"
                default: continue
                }
                let encoding: String.Encoding = parts[1].tag == 0x1E ? .utf16BigEndian : .utf8
                if let value = String(bytes: bytes[parts[1].content], encoding: encoding) {
                    values.append("\(title)=\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,"))")
                }
            }
        }
        return values.isEmpty ? "Unavailable" : values.joined(separator: ", ")
    }
    private static func time(_ bytes: [UInt8], _ node: Node) -> Date? {
        guard let text = String(bytes: bytes[node.content], encoding: .ascii), text.hasSuffix("Z") else { return nil }
        let normalized: String
        if node.tag == 0x17, text.count == 13, let year = Int(text.prefix(2)) {
            normalized = String(year >= 50 ? 1900+year : 2000+year)+text.dropFirst(2)
        } else if node.tag == 0x18, text.count == 15 { normalized = text } else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"; formatter.isLenient = false
        guard let date = formatter.date(from: normalized), formatter.string(from: date) == normalized else { return nil }
        return date
    }
}
