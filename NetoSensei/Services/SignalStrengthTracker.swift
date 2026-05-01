//
//  SignalStrengthTracker.swift
//  NetoSensei
//
//  Tracks WiFi signal strength history from NEHotspotNetwork
//

import Foundation

@MainActor
class SignalStrengthTracker: ObservableObject {
    static let shared = SignalStrengthTracker()

    struct SignalSample: Codable, Identifiable {
        let id: UUID
        let timestamp: Date
        let strength: Double      // 0.0 - 1.0
        let quality: WiFiInfo.SignalQuality
        let ssid: String?
    }

    @Published var samples: [SignalSample] = []
    @Published var currentStrength: Double?

    private let maxSamples = 120  // 1 hour at 30s intervals

    private init() {}

    func recordSample(strength: Double, ssid: String?) {
        // FIX (Issue 5): NEHotspotNetwork returns 0.0 when iOS does NOT actually
        // know the signal strength (no entitlement, location denied, simulator,
        // certain iOS releases). 0.0 is "data unavailable", NOT "0% signal".
        // Treat it as no sample so:
        //   - the UI can render "Signal data unavailable" instead of "0% Poor"
        //   - the rolling average isn't dragged toward 0
        //   - the samples count doesn't grow with garbage
        guard strength > 0 else {
            // Don't update currentStrength; keep showing the last real reading
            // (or nil if there hasn't been one).
            return
        }

        let quality = WiFiInfo.SignalQuality(from: strength)

        let sample = SignalSample(
            id: UUID(),
            timestamp: Date(),
            strength: strength,
            quality: quality,
            ssid: ssid
        )

        samples.append(sample)
        currentStrength = strength

        // Trim old samples
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    var averageStrength: Double? {
        // Defensive filter — even if a 0.0 ever sneaks past recordSample, the
        // average should not include it. (See recordSample for why 0.0 is bogus.)
        let valid = samples.map(\.strength).filter { $0 > 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    var trend: SignalTrend {
        guard samples.count >= 6 else { return .stable }
        let recent = samples.suffix(3).map(\.strength).reduce(0, +) / 3.0
        let earlier = samples.prefix(3).map(\.strength).reduce(0, +) / 3.0
        let diff = recent - earlier
        if diff > 0.1 { return .improving }
        if diff < -0.1 { return .degrading }
        return .stable
    }

    enum SignalTrend: String {
        case improving, stable, degrading

        var icon: String {
            switch self {
            case .improving: return "arrow.up.right"
            case .stable: return "arrow.right"
            case .degrading: return "arrow.down.right"
            }
        }
    }
}
