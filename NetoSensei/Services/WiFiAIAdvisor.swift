import Foundation

/// An allowlist of fields. Never pass the network status or discovery records
/// themselves to the provider, since they contain addresses and device names.
struct WiFiAdviceEvidence: Encodable, Equatable {
    let gatewayMs: Double?
    let dnsMs: Double?
    let internetMs: Double?
    let vpnDetected: Bool?
    let beforeMbps: Double?
    let afterMbps: Double?
    let throughputRangesOverlap: Bool?
    let beforeIdleMs: Double?
    let afterIdleMs: Double?
    let respondingAddressCount: Int?
    let idleHTTPSBeforeMs: Double?
    let idleHTTPSAfterMs: Double?
    let downloadHTTPSBeforeMs: Double?
    let downloadHTTPSAfterMs: Double?
    let uploadHTTPSBeforeMs: Double?
    let uploadHTTPSAfterMs: Double?
    let currentIdleHTTPSMs: Double?
    let currentDownloadHTTPSMs: Double?
    let currentUploadHTTPSMs: Double?

    init(status: NetworkStatus?, comparison: WiFiSpeedComparison?, respondingAddressCount: Int?, response: HTTPSResponsiveness? = nil) {
        gatewayMs = Self.valid(status?.router.displayableLatency)
        dnsMs = Self.valid(status?.dns.displayableLatency)
        internetMs = Self.valid(status?.internet.displayableLatency)
        vpnDetected = status?.vpn.isActive
        beforeMbps = Self.valid(comparison?.beforeMbps)
        afterMbps = Self.valid(comparison?.afterMbps)
        throughputRangesOverlap = comparison?.rangesOverlap
        beforeIdleMs = Self.valid(comparison?.beforeLatencyMs)
        afterIdleMs = Self.valid(comparison?.afterLatencyMs)
        self.respondingAddressCount = respondingAddressCount
        idleHTTPSBeforeMs = Self.valid(comparison?.response?.idle?.before)
        idleHTTPSAfterMs = Self.valid(comparison?.response?.idle?.after)
        downloadHTTPSBeforeMs = Self.valid(comparison?.response?.download?.before)
        downloadHTTPSAfterMs = Self.valid(comparison?.response?.download?.after)
        uploadHTTPSBeforeMs = Self.valid(comparison?.response?.upload?.before)
        uploadHTTPSAfterMs = Self.valid(comparison?.response?.upload?.after)
        currentIdleHTTPSMs = Self.valid(response?.idleMs)
        currentDownloadHTTPSMs = Self.valid(response?.downloadMs)
        currentUploadHTTPSMs = Self.valid(response?.uploadMs)
    }

    private static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

enum WiFiAIAdvisor {
    struct Recommendation: Decodable {
        let step: Int
    }

    enum Failure: LocalizedError {
        case rejected(Int), invalidReply

        var errorDescription: String? {
            switch self {
            case .rejected(401), .rejected(403): return "DeepSeek rejected the key. Check it in AI Settings."
            case .rejected(402): return "DeepSeek reports insufficient balance."
            case .rejected(429): return "DeepSeek is rate limiting requests. Try again shortly."
            case .rejected(let status): return "DeepSeek returned HTTP \(status)."
            case .invalidReply: return "DeepSeek did not return a usable recommendation."
            }
        }
    }

    static func request(for guide: WiFiRepairGuide, evidence: WiFiAdviceEvidence, key: String) throws -> URLRequest {
        let context = try JSONEncoder().encode(evidence)
        let steps = guide.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let system = """
        Prioritize one existing troubleshooting step based on the selected concern and diagnostic measurements.
        Treat missing metrics as unknown. Address counts are partial. Do not infer device ownership, attacks,
        radio interference, or causes from these values. Pick the safest helpful next step. If evidence is
        insufficient, prioritize gathering it. HTTPS timings include server time. Never claim they locate the bottleneck. Return only JSON in the form {"step":1}, using a listed index.
        """
        var request = URLRequest(url: URL(string: AIProvider.deepseek.baseURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": AIProvider.deepseek.defaultModel,
            "thinking": ["type": "disabled"],
            "response_format": ["type": "json_object"],
            "max_tokens": 96,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": "Concern: \(guide.rawValue)\nMeasurements: \(String(decoding: context, as: UTF8.self))\nSteps:\n\(steps)"]
            ]
        ])
        return request
    }

    static func decode(_ data: Data, stepCount: Int) throws -> Int {
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
                let finish_reason: String?
            }
            let choices: [Choice]
        }
        guard let choice = (try? JSONDecoder().decode(Completion.self, from: data))?.choices.first,
              choice.finish_reason == "stop", let content = choice.message.content,
              let result = try? JSONDecoder().decode(Recommendation.self, from: Data(content.utf8)),
              result.step > 0, result.step <= stepCount else { throw Failure.invalidReply }
        return result.step - 1
    }

    static func prioritize(_ guide: WiFiRepairGuide, evidence: WiFiAdviceEvidence, key: String) async throws -> Int {
        let request = try request(for: guide, evidence: evidence, key: key)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidReply }
        guard http.statusCode == 200 else { throw Failure.rejected(http.statusCode) }
        return try decode(data, stepCount: guide.steps.count)
    }
}
