//
//  ConnectionCapabilityAnalyzer.swift
//  NetoSensei
//
//  Single source of truth for "what can my connection do" decisions.
//
//  Background: the Speed Test tab, the Streaming tab's icon row, and the
//  Streaming tab's per-service detail used to each compute their own answer
//  to the same question — and disagree. The icon row would call streaming
//  "broken" while the per-service rows promised 4K UHD on Netflix; the Speed
//  Test tab would green-check Video Calls while the Streaming tab downgraded
//  them to SD. All three now read from `ConnectionCapability` produced here.
//
//  Methodology:
//   • 4K and HD are bandwidth-bound (latency doesn't matter for buffered
//     playback). The previous icon row gated 4K on latency and turned green
//     X under perfectly normal VPN ping.
//   • Video Calls are bandwidth + latency + jitter bound (real-time).
//   • Gaming is latency + bandwidth bound.
//

import Foundation

// MARK: - Output Model

struct ConnectionCapability {
    var web: ActivityRating          // browsing, email
    var streamingSD: ActivityRating  // 480p
    var streamingHD: ActivityRating  // 720p-1080p
    var streaming4K: ActivityRating  // 4K UHD
    var videoCalls: ActivityRating
    var gaming: ActivityRating
    var maxStreamingQuality: StreamingQuality

    enum StreamingQuality: String {
        case uhd4K = "4K UHD"
        case fullHD = "1080p Full HD"
        case hd720 = "720p HD"
        case sd480 = "480p SD"
        case audioOnly = "Audio Only"
        case none = "Cannot Stream"
    }
}

enum ActivityRating {
    case excellent  // ✓ green - works flawlessly
    case good       // ✓ green - works well
    case degraded   // ⚠️ yellow - works with limitations
    case poor       // ❌ red - doesn't work well

    /// Convenience: true when the activity works (excellent or good).
    /// Use this for the green-check / red-X icon row.
    var isCapable: Bool {
        self == .excellent || self == .good
    }

    var emoji: String {
        switch self {
        case .excellent: return "✓"
        case .good: return "✓"
        case .degraded: return "⚠️"
        case .poor: return "✗"
        }
    }

    /// SF Symbol used in the icon row. Yellow `degraded` shows a triangle so it
    /// visually differs from a flat red X — the user's complaint was that the
    /// icon row collapsed everything to red regardless of nuance.
    var sfSymbol: String {
        switch self {
        case .excellent, .good: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .poor: return "xmark.circle.fill"
        }
    }
}

// MARK: - Analyzer

enum ConnectionCapabilityAnalyzer {

    /// Compute capabilities from raw measurements. All inputs are nullable so
    /// callers can pass `nil` when a value wasn't measured — those activities
    /// fall back to bandwidth-only judgments where possible.
    static func analyze(
        downloadMbps: Double,
        uploadMbps: Double,
        pingMs: Double,
        jitterMs: Double,
        packetLossPercent: Double = 0
    ) -> ConnectionCapability {

        // --- Web browsing ---
        // Bandwidth + latency. Anything modern handles this; only flag poor
        // when bandwidth is genuinely unusable.
        let web: ActivityRating
        if downloadMbps >= 5 && pingMs < 200 { web = .excellent }
        else if downloadMbps >= 1 && pingMs < 500 { web = .good }
        else if downloadMbps >= 0.5 { web = .degraded }
        else { web = .poor }

        // --- 4K streaming ---
        // BANDWIDTH ONLY. A 121 Mbps connection streams 4K regardless of
        // 170ms ping; the player buffers ahead of playback.
        let streaming4K: ActivityRating
        if downloadMbps >= 50 && packetLossPercent < 1 { streaming4K = .excellent }
        else if downloadMbps >= 25 { streaming4K = .good }
        else if downloadMbps >= 15 { streaming4K = .degraded }  // upscale or buffer
        else { streaming4K = .poor }

        // --- HD streaming (720p-1080p) ---
        let streamingHD: ActivityRating
        if downloadMbps >= 25 { streamingHD = .excellent }
        else if downloadMbps >= 8 { streamingHD = .good }
        else if downloadMbps >= 3 { streamingHD = .degraded }
        else { streamingHD = .poor }

        // --- SD streaming (480p) ---
        let streamingSD: ActivityRating
        if downloadMbps >= 8 { streamingSD = .excellent }
        else if downloadMbps >= 3 { streamingSD = .good }
        else if downloadMbps >= 1 { streamingSD = .degraded }
        else { streamingSD = .poor }

        // --- Video calls ---
        // Real-time → needs bandwidth, low latency, low jitter.
        let videoCalls: ActivityRating
        if downloadMbps >= 5 && pingMs <= 50 && jitterMs <= 15 && packetLossPercent < 1 {
            videoCalls = .excellent
        } else if downloadMbps >= 5 && pingMs <= 150 && jitterMs <= 30 && packetLossPercent < 2 {
            videoCalls = .good
        } else if downloadMbps >= 1 && pingMs <= 300 {
            // Audio quality possible; HD video will struggle.
            videoCalls = .degraded
        } else {
            videoCalls = .poor
        }

        // --- Gaming ---
        // Latency-dominant. Gaming over a high-ping link feels broken even
        // with 1 Gbps bandwidth.
        let gaming: ActivityRating
        if downloadMbps >= 10 && pingMs <= 30 && jitterMs <= 10 && packetLossPercent < 0.5 {
            gaming = .excellent
        } else if downloadMbps >= 10 && pingMs <= 50 && jitterMs <= 20 {
            gaming = .good
        } else if pingMs <= 100 && downloadMbps >= 5 {
            gaming = .degraded  // single-player / casual only
        } else {
            gaming = .poor
        }

        // --- Max streaming quality ---
        // Highest tier the connection can SUSTAIN, derived from the activity
        // ratings above so it can never contradict them.
        let maxQuality: ConnectionCapability.StreamingQuality
        if streaming4K.isCapable { maxQuality = .uhd4K }
        else if streamingHD.isCapable { maxQuality = .fullHD }
        else if streamingSD.isCapable { maxQuality = .hd720 }
        else if downloadMbps >= 1.5 { maxQuality = .sd480 }
        else if downloadMbps >= 0.5 { maxQuality = .audioOnly }
        else { maxQuality = .none }

        return ConnectionCapability(
            web: web,
            streamingSD: streamingSD,
            streamingHD: streamingHD,
            streaming4K: streaming4K,
            videoCalls: videoCalls,
            gaming: gaming,
            maxStreamingQuality: maxQuality
        )
    }

    /// Convenience: analyze from a SpeedTestResult.
    static func analyze(from result: SpeedTestResult) -> ConnectionCapability {
        analyze(
            downloadMbps: result.downloadSpeed,
            uploadMbps: result.uploadSpeed,
            pingMs: result.ping,
            jitterMs: result.jitter,
            packetLossPercent: result.packetLoss
        )
    }
}
