import Testing
import Foundation
@testable import NetoSensei

private final class EndpointFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if url.host == "timeout.test" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        } else {
            let code = url.host == "error.test" ? 503 : 200
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

struct EndpointTransportTests {
    @Test func responseTimingRequiresAResponseAndDoesNotTurnTimeoutIntoLatency() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EndpointFixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let success = await TracerouteService.responseTime(host: "ok.test", session: session)
        #expect(success != nil && success!.isFinite && success! >= 0)
        #expect(await TracerouteService.responseTime(host: "timeout.test", session: session) == nil)
        // A 503 is a real server response, not a successful throughput test.
        #expect(await TracerouteService.responseTime(host: "error.test", session: session) != nil)
        #expect(await TracerouteService.responseTime(host: "invalid/path", session: session) == nil)
    }
}
