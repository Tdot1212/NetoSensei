import Testing
import Foundation
import Security
@testable import NetoSensei

private final class CertificateFixtureBundle: NSObject {}
struct CertificateVerificationTests {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: CertificateFixtureBundle.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "der") ?? bundle.url(forResource: name, withExtension: "der", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
    @Test func serialDatesKeyAndSelfSignatureUseActualCertificateFields() throws {
        let leafData = try fixture("FixtureLeaf"), rootData = try fixture("FixtureRoot")
        let leaf = try #require(SecCertificateCreateWithData(nil, leafData as CFData)), root = try #require(SecCertificateCreateWithData(nil, rootData as CFData))
        let leafInfo = CertificateDER.info(leaf, trusted: false), rootInfo = CertificateDER.info(root, trusted: false)
        #expect(leafInfo.serialNumber == "2B" && rootInfo.serialNumber == "2A")
        #expect(leafInfo.subject.contains("fixture.example.test") && leafInfo.issuer.contains("NetoSensei Fixture Root"))
        #expect(!leafInfo.isSelfSigned && rootInfo.isSelfSigned && rootInfo.isRootCA)
        #expect(!leafInfo.isTrusted && !rootInfo.isTrusted)
        #expect(leafInfo.publicKeyInfo == "RSA 2048 bits")
        let from = try #require(leafInfo.validFrom), to = try #require(leafInfo.validTo)
        #expect(to.timeIntervalSince(from) == 365*86400)
    }
    @Test func everyTruncatedDERAndMalformedLengthFailsSafely() throws {
        let data = try fixture("FixtureLeaf")
        for count in 0..<data.count { #expect(CertificateDER.metadata(Data(data.prefix(count))) == nil) }
        for invalid in [Data([0x30,0x80]), Data([0x30,0x84,0xFF,0xFF,0xFF,0xFF]), Data([0x30,0x81,0]), Data()] {
            #expect(CertificateDER.metadata(invalid) == nil)
        }
    }
    @Test func systemTrustChecksHostnameAndDoesNotTrustFixtureRootByDefault() throws {
        let leaf = try #require(SecCertificateCreateWithData(nil, try fixture("FixtureLeaf") as CFData))
        let root = try #require(SecCertificateCreateWithData(nil, try fixture("FixtureRoot") as CFData))
        let from = try #require(CertificateDER.info(leaf, trusted: false).validFrom)
        func evaluate(_ hostname: String, anchor: Bool) throws -> Bool {
            var trust: SecTrust?
            #expect(SecTrustCreateWithCertificates([leaf,root] as CFArray, SecPolicyCreateSSL(true, hostname as CFString), &trust) == errSecSuccess)
            let value = try #require(trust)
            SecTrustSetNetworkFetchAllowed(value, false)
            SecTrustSetVerifyDate(value, from.addingTimeInterval(86400) as CFDate)
            if anchor { SecTrustSetAnchorCertificates(value, [root] as CFArray); SecTrustSetAnchorCertificatesOnly(value, true) }
            return SecTrustEvaluateWithError(value, nil)
        }
        #expect(try !evaluate("fixture.example.test", anchor: false))
        #expect(try evaluate("fixture.example.test", anchor: true))
        #expect(try !evaluate("wrong.example.test", anchor: true))
    }
    @MainActor @Test func completeTLSFlowNeverDowngradesTrustFailureForVPNOrProxyName() async throws {
        let cert = try #require(SecCertificateCreateWithData(nil, try fixture("FixtureLeaf") as CFData))
        let leaf = CertificateDER.info(cert, trusted: false)
        let analyzer = TLSAnalyzer(capture: { _,_ in .init(chain: [leaf], trusted: false, handshakeMs: nil, errorCode: -1202, version: .tls13, cipher: nil) })
        let result = await analyzer.analyzeHost("fixture.example.test")
        #expect(result.assessment == .completed && result.securityRating == .critical && !result.isSecure)
        for active in [false,true] {
            let mapped = CertificateInspector.map(host: "fixture.example.test", result: result, vpnActive: active)
            #expect(mapped.severity == .critical)
        }
    }
    @MainActor @Test func successfulCaptureKeepsRealHandshakeAndUnavailableCaptureStaysUnknown() async throws {
        let cert = try #require(SecCertificateCreateWithData(nil, try fixture("FixtureLeaf") as CFData))
        let trusted = CertificateDER.info(cert, trusted: true)
        let measured = await TLSAnalyzer(capture: { _,_ in .init(chain: [trusted], trusted: true, handshakeMs: 25, errorCode: nil, version: .tls13, cipher: "TLS cipher 0x1301") }).analyzeHost("fixture.example.test")
        #expect(measured.handshakeLatencyMs == 25 && measured.tlsVersion == .tls13)
        let unavailable = await TLSAnalyzer(capture: { _,_ in .init(chain: [], trusted: false, handshakeMs: nil, errorCode: -1001, version: .unknown, cipher: nil) }).analyzeHost("unreachable.example.test")
        #expect(unavailable.securityRating == nil && unavailable.handshakeLatencyMs == nil)
        #expect(CertificateInspector.map(host: "x", result: unavailable, vpnActive: true).severity == .unavailable)
    }
    @Test func TLSProtocolCodesAreMappedWithoutGuessing() {
        #expect(TLSCertificateDelegate.protocolVersion(0x0304) == .tls13)
        #expect(TLSCertificateDelegate.protocolVersion(0x0303) == .tls12)
        #expect(TLSCertificateDelegate.protocolVersion(0x0302) == .tls11)
        #expect(TLSCertificateDelegate.protocolVersion(0x0301) == .tls10)
        #expect(TLSCertificateDelegate.protocolVersion(nil) == .unknown)
        #expect(TLSCertificateDelegate.protocolVersion(0xFFFF) == .unknown)
    }
}
