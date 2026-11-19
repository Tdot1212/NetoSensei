import Testing
import Foundation
@testable import NetoSensei

private final class TransferFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let mode = request.value(forHTTPHeaderField: "X-Fixture-Mode") ?? "success"
        let isUpload = request.httpMethod == "POST"
        let count = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "bytes" })?.value ?? "0") ?? 0
        let status = mode == "unreachable" ? 503 : (mode == "rejected" && isUpload ? 405 : 200)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: mode == "compressed" ? ["Content-Encoding": "gzip", "Content-Type": "application/octet-stream"] : ["Content-Type": mode == "html" ? "text/html" : "application/octet-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !isUpload && count > 0 {
            client?.urlProtocol(self, didLoad: Data(repeating: 0x55, count: mode == "rejected" ? 32 : count))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class TransferClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func tick() -> Double {
        lock.lock(); defer { lock.unlock() }
        value += 0.5
        return value
    }
}

@Suite(.serialized)
struct SpeedTransportTests {
    @MainActor @Test func fullPipelineMeasuresKnownBytesAndClockIntervals() async {
        let engine = makeEngine(mode: "success")
        let result = await engine.runSpeedTest()
        #expect(result.testUnavailableReason == nil)
        #expect(result.downloadSpeed == 400) // 25 MB * 8 / 0.5 s / 1e6
        #expect(result.measuredUploadSpeed == nil) // URLProtocol cannot prove transmission of body bytes.
        #expect(result.ping == 20 && result.jitter == 5 && result.packetLoss == nil)
        #expect(result.testDuration > 0 && result.measurementVersion == 2)
        #expect(!engine.isRunning && engine.currentPhase == .idle)
    }

    @MainActor @Test func rejectedUploadAndShortDownloadCannotBecomeHugeOrZeroSpeed() async {
        let engine = makeEngine(mode: "rejected")
        let result = await engine.runSpeedTest()
        #expect(result.testUnavailableReason != nil)
        #expect(result.measuredUploadSpeed == nil)
        #expect(!engine.isRunning)
    }

    @MainActor @Test func noReachableCandidateReturnsUnavailableWithoutTransfers() async {
        let result = await makeEngine(mode: "unreachable").runSpeedTest()
        #expect(result.testUnavailableReason != nil && result.ping == nil)
    }

    @MainActor @Test func overlappingRunCannotCorruptActiveTransferSession() async {
        let engine = makeEngine(mode: "success")
        let first = Task { await engine.runSpeedTest() }
        for _ in 0..<100 where !engine.isRunning { await Task.yield() }
        let second = await engine.runSpeedTest()
        #expect(second.testUnavailableReason == "Another speed test is already running.")
        #expect(await first.value.testUnavailableReason == nil)
    }

    @MainActor @Test func cancellationStopsWithoutPublishingAMeasurement() async {
        let engine = makeEngine(mode: "success")
        let task = Task { await engine.runSpeedTest() }
        task.cancel()
        let result = await task.value
        #expect(result.testUnavailableReason != nil)
        #expect(!engine.isRunning)
    }

    @MainActor @Test func decompressedBodyCannotInflateWireThroughput() async {
        for mode in ["compressed", "html"] {
            let result = await makeEngine(mode: mode).runSpeedTest()
            #expect(result.testUnavailableReason != nil)
        }
    }

    @MainActor @Test func unavailableBaselineServerCannotFallBackToADifferentServer() async {
        let engine = makeEngine(mode: "success")
        let result = await engine.runSpeedTest(comparisonServer: "Unavailable baseline server")
        #expect(result.testUnavailableReason?.contains("baseline test server") == true)
        #expect(result.serverUsed == nil && result.ping == nil)
    }

    @MainActor private func makeEngine(mode: String) -> SpeedTestEngine {
        var status = NetworkMonitorService.shared.currentStatus
        status.connectionType = .wifi
        status.wifi.ssid = "Fixture"
        status.localIP = "192.168.10.2"
        status.publicIP = "203.0.113.1"
        let snapshot = status
        let clock = TransferClock()
        return SpeedTestEngine(environment: .init(status: { snapshot },
            exit: { .resolved(country: "US", vpnActive: false) },
            latency: { (20, 5, false) }, pathChange: { .distantPast },
            makeSession: {
                let config = URLSessionConfiguration.ephemeral
                config.protocolClasses = [TransferFixture.self]
                config.httpAdditionalHeaders = ["X-Fixture-Mode": mode]
                return URLSession(configuration: config)
            }, now: { clock.tick() }))
    }
}
