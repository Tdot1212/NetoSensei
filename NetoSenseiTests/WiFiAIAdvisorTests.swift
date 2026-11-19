import Foundation
import Testing
@testable import NetoSensei

struct WiFiAIAdvisorTests {
    @Test func sendsOnlyAllowlistedEvidenceAndUsesCurrentDeepSeekModel() throws {
        var status = NetworkStatus.empty
        status.wifi.ssid = "private-ssid-fixture"
        status.localIP = "192.0.2.21"
        status.publicIP = "203.0.113.21"
        let response = HTTPSResponsiveness(endpoint: "https://private-test-host.test", idleMs: 112,
                                           downloadMs: 390, uploadMs: nil)
        let evidence = WiFiAdviceEvidence(status: status, comparison: nil, respondingAddressCount: 7,
                                           response: response)
        let request = try WiFiAIAdvisor.request(for: .lag, evidence: evidence, key: "fixture-key")
        let data = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let raw = String(decoding: data, as: UTF8.self)
        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(json["model"] as? String == "deepseek-flash")
        #expect(raw.contains("respondingAddressCount"))
        #expect(raw.contains("currentDownloadHTTPSMs"))
        #expect(!raw.contains("currentUploadHTTPSMs"))
        for privateValue in ["private-test-host.test", "private-ssid-fixture", "192.0.2.21", "203.0.113.21", "fixture-key"] {
            #expect(!raw.contains(privateValue))
        }
    }

    @Test func acceptsOnlyACompletedReplySelectingAnExistingStep() throws {
        func completion(_ content: String, reason: String = "stop") throws -> Data {
            try JSONSerialization.data(withJSONObject: ["choices": [
                ["message": ["content": content], "finish_reason": reason]
            ]])
        }
        #expect(try WiFiAIAdvisor.decode(completion("{\"step\":2}"), stepCount: 3) == 1)
        for invalid in ["", "{\"step\":0}", "{\"step\":4}", "{\"step\":\"2\"}", "Disable security"] {
            let data = try completion(invalid)
            #expect(throws: WiFiAIAdvisor.Failure.self) { try WiFiAIAdvisor.decode(data, stepCount: 3) }
        }
        let truncated = try completion("{\"step\":1}", reason: "length")
        #expect(throws: WiFiAIAdvisor.Failure.self) { try WiFiAIAdvisor.decode(truncated, stepCount: 3) }
    }
}
