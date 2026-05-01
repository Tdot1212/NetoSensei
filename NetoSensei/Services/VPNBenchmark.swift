//
//  VPNBenchmark.swift
//  NetoSensei
//
//  VPN destination benchmark - tests reachability and latency to popular
//  services that are typically blocked in China without VPN
//

import Foundation

@MainActor
class VPNBenchmark: ObservableObject {

    struct BenchmarkResult: Identifiable {
        let id = UUID()
        let destination: Destination
        let latencyMs: Double?      // nil = failed/timeout
        let reachable: Bool
        let httpStatus: Int?
        let responseTimeMs: Double?  // Full HTTP response time
        let error: String?
        let timestamp: Date

        // FIX (Speed Issue 5): These thresholds reflect that VPN site
        // reachability times include FULL HTTP round-trip through the tunnel —
        // not raw TCP RTT. International VPN (e.g. China → US) commonly sits
        // 500-2000ms even for a healthy tunnel. The previous thresholds
        // labeled everything > 400ms "Very Slow" and turned the whole table
        // red.
        var qualityRating: String {
            guard let latency = latencyMs else { return "Unreachable" }
            switch latency {
            case ..<500: return "Fast"
            case ..<1000: return "Normal"
            case ..<2000: return "Slow"
            default: return "Very Slow"
            }
        }
    }

    enum Destination: String, CaseIterable, Identifiable {
        case google = "Google"
        case youtube = "YouTube"
        case twitter = "X (Twitter)"
        case chatgpt = "ChatGPT"
        case github = "GitHub"
        case instagram = "Instagram"
        case whatsapp = "WhatsApp"

        var id: String { rawValue }

        var testURL: String {
            switch self {
            case .google: return "https://www.google.com/generate_204"
            case .youtube: return "https://www.youtube.com/favicon.ico"
            case .twitter: return "https://x.com/favicon.ico"
            case .chatgpt: return "https://chat.openai.com/favicon.ico"
            case .github: return "https://github.com/favicon.ico"
            case .instagram: return "https://www.instagram.com/favicon.ico"
            case .whatsapp: return "https://web.whatsapp.com/favicon.ico"
            }
        }

        var icon: String {
            switch self {
            case .google: return "globe"
            case .youtube: return "play.rectangle.fill"
            case .twitter: return "at.circle.fill"
            case .chatgpt: return "bubble.left.fill"
            case .github: return "chevron.left.forwardslash.chevron.right"
            case .instagram: return "camera.fill"
            case .whatsapp: return "phone.fill"
            }
        }

        /// Destinations that are blocked in China without VPN
        var blockedInChina: Bool {
            switch self {
            case .google, .youtube, .twitter, .chatgpt, .instagram, .whatsapp: return true
            case .github: return false
            }
        }
    }

    @Published var results: [BenchmarkResult] = []
    @Published var isRunning = false
    @Published var progress: Double = 0

    func runBenchmark(destinations: [Destination] = Destination.allCases) async {
        isRunning = true
        results = []
        progress = 0

        for (index, dest) in destinations.enumerated() {
            let result = await testDestination(dest)
            results.append(result)
            progress = Double(index + 1) / Double(destinations.count)
        }

        isRunning = false
    }

    private func testDestination(_ destination: Destination) async -> BenchmarkResult {
        guard let url = URL(string: destination.testURL) else {
            return BenchmarkResult(
                destination: destination, latencyMs: nil, reachable: false,
                httpStatus: nil, responseTimeMs: nil, error: "Invalid URL", timestamp: Date()
            )
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config)

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (_, response) = try await session.data(from: url)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let httpResponse = response as? HTTPURLResponse

            return BenchmarkResult(
                destination: destination,
                latencyMs: elapsed,
                reachable: true,
                httpStatus: httpResponse?.statusCode,
                responseTimeMs: elapsed,
                error: nil,
                timestamp: Date()
            )
        } catch {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

            let errorDesc: String
            let nsError = error as NSError
            switch nsError.code {
            case -1001: errorDesc = "Timeout (likely blocked or geo-restricted)"
            case -1003: errorDesc = "Cannot find host"
            case -1004: errorDesc = "Cannot connect"
            case -1200: errorDesc = "TLS/SSL error (proxy may be intercepting)"
            default: errorDesc = error.localizedDescription
            }

            return BenchmarkResult(
                destination: destination,
                latencyMs: elapsed > 9500 ? nil : elapsed,
                reachable: false,
                httpStatus: nil,
                responseTimeMs: nil,
                error: errorDesc,
                timestamp: Date()
            )
        }
    }
}
