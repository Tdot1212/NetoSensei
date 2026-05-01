//
//  CongestionAnalysis.swift
//  NetoSensei
//
//  Distinguishes channel congestion (RF) from router congestion (hardware)
//  Critical: "Is delivery stable?" not "Is speed high?"
//

import Foundation

// MARK: - Congestion Type

enum CongestionType: String, Codable {
    case channelCongestion = "Channel Congestion"  // RF layer - multiple APs fighting
    case routerCongestion = "Router Congestion"    // Hardware - CPU/memory overload
    case compoundCongestion = "Compound Congestion"  // Both (very common in China)
    case noCongestion = "No Congestion"
}

// MARK: - Stability Metrics

struct StabilityMetrics: Codable, Equatable {
    // What matters for video buffering
    let jitter: Double  // ms - packet delay variation (CRITICAL)
    let latencyStdDev: Double?  // ms - ping consistency
    let txRateStability: String  // "Stable", "Unstable", "Fluctuating"
    let mcsStability: String  // "Stable", "Fluctuating"
    let packetDeliveryPredictable: Bool

    var isDeliveryStable: Bool {
        // Video needs stable delivery, not just high speed
        return jitter < 20 &&  // Low jitter
               (latencyStdDev ?? 0) < 10 &&  // Consistent latency
               txRateStability != "Unstable" &&
               packetDeliveryPredictable
    }

    var stabilityQuality: String {
        if isDeliveryStable { return "Excellent - Stable delivery" }
        if jitter < 50 { return "Fair - Some instability" }
        return "Poor - Unstable delivery (buffering likely)"
    }
}

// MARK: - Congestion Analysis Result

struct CongestionAnalysisResult: Codable, Equatable {
    let type: CongestionType
    let confidence: Double  // 0.0 - 1.0
    let primaryIndicators: [String]
    let recommendation: String

    // Supporting evidence
    let rssiGood: Bool
    let noiseStable: Bool
    let txRateUnstable: Bool
    let mcsFluctuates: Bool
    let pingSpikesUnderLoad: Bool
    let channelClean: Bool

    var userFriendlyDiagnosis: String {
        switch type {
        case .channelCongestion:
            return """
            📡 Channel Congestion Detected

            Your WiFi channel is crowded with other networks fighting for airtime.

            Signal: ✅ Good
            Problem: 🔴 Too many APs on channel \(primaryIndicators.joined(separator: ", "))

            This causes:
            • Video buffering in bursts (play → stop → play)
            • TX rate jumping up and down
            • Good speed tests but stuttering video

            Why: Other networks are "talking over" your router on the same frequency.
            """

        case .routerCongestion:
            return """
            🖥️ Router Congestion Detected

            Your router hardware is overloaded (CPU/memory).

            Channel: ✅ Clean
            Problem: 🔴 Router struggling under load

            Evidence:
            \(primaryIndicators.joined(separator: "\n"))

            This happens when multiple devices are active or router is underpowered.
            """

        case .compoundCongestion:
            return """
            ⚠️ Compound Congestion (Channel + Router)

            Both your WiFi channel AND router are congested.

            Issues:
            \(primaryIndicators.joined(separator: "\n"))

            This is very common in Chinese households:
            • Many devices (phones, TVs, IoT)
            • ISP equipment often underpowered
            • Crowded 2.4/5 GHz spectrum
            """

        case .noCongestion:
            return "✅ No congestion detected - delivery is stable"
        }
    }
}

// MARK: - Congestion Analyzer

struct CongestionAnalyzer {

    static func analyze(
        rssi: Int?,
        noise: Int?,
        txRate: Int?,
        mcsIndex: Int?,
        pingAvg: Double,
        jitter: Double,
        packetLoss: Double,
        throughput: Double,
        // Context from multiple measurements
        txRateHistory: [Int]? = nil,
        mcsHistory: [Int]? = nil,
        pingUnderLoad: Double? = nil
    ) -> CongestionAnalysisResult {

        var indicators: [String] = []
        var confidence: Double = 0.5

        // Signal quality assessment
        let rssiGood = (rssi ?? -100) > -65  // Strong signal
        let noiseStable = (noise != nil)  // We have noise data

        // TX rate stability (if we have history)
        let txRateUnstable: Bool
        if let history = txRateHistory, history.count >= 3 {
            let stdDev = standardDeviation(history.map { Double($0) })
            let mean = Double(history.reduce(0, +)) / Double(history.count)
            let variation = stdDev / mean
            txRateUnstable = variation > 0.3  // >30% variation
        } else {
            txRateUnstable = false
        }

        // MCS fluctuation
        let mcsFluctuates: Bool
        if let history = mcsHistory, history.count >= 3 {
            let uniqueValues = Set(history).count
            mcsFluctuates = uniqueValues > 2  // MCS changing frequently
        } else {
            mcsFluctuates = false
        }

        // Router load detection
        let pingSpikesUnderLoad: Bool
        if let underLoad = pingUnderLoad {
            pingSpikesUnderLoad = underLoad > (pingAvg * 2)  // 2x spike under load
        } else {
            pingSpikesUnderLoad = false
        }

        // Channel assessment (simplified - would need WiFi scan for accuracy)
        let channelClean = !txRateUnstable && !mcsFluctuates

        // DECISION LOGIC

        // A. Channel Congestion
        if rssiGood && txRateUnstable && mcsFluctuates && !pingSpikesUnderLoad {
            indicators.append("• RSSI good but TX rate unstable")
            indicators.append("• MCS index fluctuating")
            indicators.append("• Multiple APs likely on same channel")
            confidence = 0.8

            return CongestionAnalysisResult(
                type: .channelCongestion,
                confidence: confidence,
                primaryIndicators: indicators,
                recommendation: "Change WiFi channel to less crowded frequency. Recommend passive WiFi scan to find optimal channel.",
                rssiGood: rssiGood,
                noiseStable: noiseStable,
                txRateUnstable: txRateUnstable,
                mcsFluctuates: mcsFluctuates,
                pingSpikesUnderLoad: pingSpikesUnderLoad,
                channelClean: channelClean
            )
        }

        // B. Router Congestion
        if rssiGood && channelClean && (pingSpikesUnderLoad || (pingAvg > 20 && jitter > 30)) {
            indicators.append("• Ping spikes when other devices active")
            indicators.append("• High jitter (\(Int(jitter))ms)")
            if throughput < 10 && rssiGood {
                indicators.append("• Low throughput despite good signal")
            }
            confidence = 0.75

            return CongestionAnalysisResult(
                type: .routerCongestion,
                confidence: confidence,
                primaryIndicators: indicators,
                recommendation: "Router hardware overloaded. Consider: reducing connected devices, upgrading router, or enabling QoS.",
                rssiGood: rssiGood,
                noiseStable: noiseStable,
                txRateUnstable: txRateUnstable,
                mcsFluctuates: mcsFluctuates,
                pingSpikesUnderLoad: pingSpikesUnderLoad,
                channelClean: channelClean
            )
        }

        // C. Compound Congestion (very common in China)
        if txRateUnstable && (pingSpikesUnderLoad || jitter > 40) {
            indicators.append("• TX rate unstable (channel issue)")
            indicators.append("• Ping spikes under load (router issue)")
            indicators.append("• Both RF layer and router hardware congested")
            confidence = 0.85

            return CongestionAnalysisResult(
                type: .compoundCongestion,
                confidence: confidence,
                primaryIndicators: indicators,
                recommendation: "Multiple issues: 1) Change WiFi channel, 2) Reduce device load or upgrade router. Very common in Chinese households with many devices.",
                rssiGood: rssiGood,
                noiseStable: noiseStable,
                txRateUnstable: txRateUnstable,
                mcsFluctuates: mcsFluctuates,
                pingSpikesUnderLoad: pingSpikesUnderLoad,
                channelClean: channelClean
            )
        }

        // D. No Congestion
        return CongestionAnalysisResult(
            type: .noCongestion,
            confidence: 0.9,
            primaryIndicators: ["✅ Channel clean", "✅ Router responsive", "✅ Delivery stable"],
            recommendation: "No congestion detected. Network is performing well.",
            rssiGood: rssiGood,
            noiseStable: noiseStable,
            txRateUnstable: txRateUnstable,
            mcsFluctuates: mcsFluctuates,
            pingSpikesUnderLoad: pingSpikesUnderLoad,
            channelClean: channelClean
        )
    }

    // Helper: Standard deviation calculation
    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }
}

// MARK: - Bufferbloat Test

struct BufferbloatTestResult: Codable, Equatable {
    let pingIdle: Double  // ms - ping when network is idle
    let pingUnderLoad: Double  // ms - ping while downloading
    let bloatScore: Double  // Ratio: pingUnderLoad / pingIdle
    let rating: String

    var userFriendlyDescription: String {
        """
        Bufferbloat Test:
        Idle: \(Int(pingIdle))ms
        Under load: \(Int(pingUnderLoad))ms
        Bloat: \(String(format: "%.1fx", bloatScore))

        Rating: \(rating)

        \(interpretation)
        """
    }

    var interpretation: String {
        if bloatScore < 2.0 {
            return "✅ Excellent - Router handles load well"
        } else if bloatScore < 5.0 {
            return "⚠️ Moderate - Some latency spike under load"
        } else {
            return "🔴 Severe - Router buffers are bloated. Enable QoS or reduce device count."
        }
    }
}
