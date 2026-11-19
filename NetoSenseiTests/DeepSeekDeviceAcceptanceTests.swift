#if DEEPSEEK_ACCEPTANCE && !targetEnvironment(simulator)
import Testing
@testable import NetoSensei

struct DeepSeekDeviceAcceptanceTests {
    @MainActor @Test func onDeviceCredentialCanPrioritizeAStep() async throws {
        guard let key = AIKeyManager.shared.getKey(for: .deepseek) else {
            print("DEEPSEEK_ACCEPTANCE: No key is configured in the iPhone app.")
            return
        }
        // Synthetic inputs exercise the provider without sending this device's measurements.
        let comparison = WiFiSpeedComparison(beforeMbps: 52, afterMbps: 54, changePercent: 3.8,
                                             rangesOverlap: true, beforeLatencyMs: 60, afterLatencyMs: 58)
        let evidence = WiFiAdviceEvidence(status: nil, comparison: comparison, respondingAddressCount: nil)
        let step = try await WiFiAIAdvisor.prioritize(.lag, evidence: evidence, key: key)
        #expect(WiFiRepairGuide.lag.steps.indices.contains(step))
        print("DEEPSEEK_ACCEPTANCE: Live provider returned a valid repair step.")
    }
    @MainActor @Test func onDeviceChatUnderstandsUnverifiedProtection() async throws {
        guard AIKeyManager.shared.getKey(for: .deepseek) != nil else {
            print("DEEPSEEK_CHAT_ACCEPTANCE: No key is configured in the iPhone app.")
            return
        }

        let evidence = """
        {"vpnState":"onInferred","vpnLeakVerdict":"unverified",
        "vpnPrivacyCoverage":"DNS routing, public IP bypass, IPv6 bypass and browser WebRTC were not measured end to end.",
        "featuresTested":{"vpn_leak":false,"speed_test":true},"downloadMbps":84.4,"uploadMbps":29.1}
        """
        let response = try await AIChatService.shared.sendMessage(
            "Can you confirm there are no leaks? What should I do next?",
            conversationHistory: [], provider: .deepseek, preflightJSON: evidence
        )
        let answer = response.lowercased()
        #expect(answer.contains("unverified") || answer.contains("can't confirm") ||
                answer.contains("cannot confirm") || answer.contains("not measured"))
        #expect(!answer.contains("no leaks detected"))
        #expect(!answer.contains("your network is secure"))
        #expect(answer.contains("baseline") || answer.contains("documented") || answer.contains("provider"))
        #expect(!answer.contains("against this baseline"))
        print("DEEPSEEK_CHAT_ACCEPTANCE: \(response)")
    }
}
#endif
