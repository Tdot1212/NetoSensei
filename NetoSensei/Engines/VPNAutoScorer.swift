//
//  VPNAutoScorer.swift
//  NetoSensei
//
//  VPN Auto-Scoring System - 100% Real Scoring
//  Ranks: Speed (40%), Latency (30%), Stability (20%), Privacy (10%)
//  Outputs: "Your best VPN setup right now is: Singapore + WireGuard."
//

import Foundation

actor VPNAutoScorer {
    static let shared = VPNAutoScorer()

    private init() {}

    // Scoring weights
    private let speedWeight = 0.40
    private let latencyWeight = 0.30
    private let stabilityWeight = 0.20
    private let privacyWeight = 0.10

    // MARK: - Score VPN Setup

    func scoreVPNSetup(region: String, mode: VPNMode) async -> VPNSetupScore {
        // 1. Get reliability data for this region
        let reliability = await VPNReliabilityTracker.shared.getRegionReliability(region: region)

        // 2. Get benchmark data for this mode
        let modeBenchmark = await VPNModeBenchmark.shared.benchmarkMode(mode: mode, region: region)

        // 3. Get failure prediction for this setup
        let failurePrediction = await VPNFailurePredictor.shared.predictFailure(currentRegion: region)

        // 4. Calculate component scores
        let speedScore = calculateSpeedScore(
            downloadSpeed: modeBenchmark.downloadSpeed,
            uploadSpeed: modeBenchmark.uploadSpeed
        )

        let latencyScore = calculateLatencyScore(
            latency: modeBenchmark.averageLatency,
            jitter: modeBenchmark.jitter
        )

        let stabilityScore = calculateStabilityScore(
            reliability: reliability,
            modeBenchmark: modeBenchmark,
            failurePrediction: failurePrediction
        )

        let privacyScore = calculatePrivacyScore(
            mode: mode,
            dnsLeakDetected: failurePrediction.dnsLeakDetected
        )

        // 5. Calculate weighted overall score
        let overallScore = calculateWeightedScore(
            speed: speedScore,
            latency: latencyScore,
            stability: stabilityScore,
            privacy: privacyScore
        )

        return VPNSetupScore(
            region: region,
            mode: mode,
            overallScore: overallScore,
            speedScore: speedScore,
            latencyScore: latencyScore,
            stabilityScore: stabilityScore,
            privacyScore: privacyScore,
            downloadSpeed: modeBenchmark.downloadSpeed,
            uploadSpeed: modeBenchmark.uploadSpeed,
            averageLatency: modeBenchmark.averageLatency,
            jitter: modeBenchmark.jitter,
            packetLoss: modeBenchmark.packetLoss,
            tunnelDropRate: reliability?.dropRate ?? 0,
            dnsLeakDetected: failurePrediction.dnsLeakDetected
        )
    }

    func findBestVPNSetup(regions: [String]) async -> VPNSetupRecommendation {
        var allScores: [VPNSetupScore] = []

        // Score all region + mode combinations
        for region in regions {
            for mode in VPNMode.allCases {
                let score = await scoreVPNSetup(region: region, mode: mode)
                allScores.append(score)

                // Small delay to avoid overwhelming the system
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            }
        }

        // Sort by overall score
        let sortedScores = allScores.sorted { $0.overallScore > $1.overallScore }

        // Get best for each category
        let bestOverall = sortedScores.first
        let bestForSpeed = allScores.max(by: { $0.speedScore < $1.speedScore })
        let bestForLatency = allScores.max(by: { $0.latencyScore < $1.latencyScore })
        let bestForStability = allScores.max(by: { $0.stabilityScore < $1.stabilityScore })
        let bestForPrivacy = allScores.max(by: { $0.privacyScore < $1.privacyScore })

        // Get top 5 setups
        let topSetups = Array(sortedScores.prefix(5))

        // Get worst setups to avoid
        let worstSetups = sortedScores.filter { $0.overallScore < 50 }

        return VPNSetupRecommendation(
            bestOverall: bestOverall,
            bestForSpeed: bestForSpeed,
            bestForLatency: bestForLatency,
            bestForStability: bestForStability,
            bestForPrivacy: bestForPrivacy,
            topSetups: topSetups,
            worstSetups: worstSetups,
            allScores: sortedScores
        )
    }

    func compareCurrentSetup(currentRegion: String, currentMode: VPNMode, regions: [String]) async -> VPNSetupComparison {
        // Score current setup
        let currentScore = await scoreVPNSetup(region: currentRegion, mode: currentMode)

        // Find best alternative
        let recommendation = await findBestVPNSetup(regions: regions)

        guard let bestSetup = recommendation.bestOverall else {
            return VPNSetupComparison(
                currentSetup: currentScore,
                bestSetup: currentScore,
                scoreDifference: 0,
                shouldSwitch: false,
                improvements: []
            )
        }

        let scoreDifference = bestSetup.overallScore - currentScore.overallScore
        let shouldSwitch = scoreDifference > 10  // Switch if 10+ point improvement

        var improvements: [String] = []

        if shouldSwitch {
            if bestSetup.speedScore > currentScore.speedScore + 10 {
                let speedImprovement = bestSetup.downloadSpeed - currentScore.downloadSpeed
                improvements.append("Speed: +\(String(format: "%.1f", speedImprovement)) Mbps")
            }

            if bestSetup.latencyScore > currentScore.latencyScore + 10 {
                let latencyImprovement = currentScore.averageLatency - bestSetup.averageLatency
                improvements.append("Latency: -\(String(format: "%.0f", latencyImprovement)) ms")
            }

            if bestSetup.stabilityScore > currentScore.stabilityScore + 10 {
                improvements.append("Stability: +\(Int(bestSetup.stabilityScore - currentScore.stabilityScore)) points")
            }

            if bestSetup.privacyScore > currentScore.privacyScore {
                improvements.append("Privacy: Better protection")
            }
        }

        return VPNSetupComparison(
            currentSetup: currentScore,
            bestSetup: bestSetup,
            scoreDifference: scoreDifference,
            shouldSwitch: shouldSwitch,
            improvements: improvements
        )
    }

    // MARK: - Component Score Calculations

    private func calculateSpeedScore(downloadSpeed: Double, uploadSpeed: Double) -> Int {
        // Download is weighted more heavily (70/30 split)
        let downloadScore: Int
        if downloadSpeed > 100 {
            downloadScore = 100
        } else if downloadSpeed > 50 {
            downloadScore = 80 + Int((downloadSpeed - 50) / 50 * 20)
        } else if downloadSpeed > 25 {
            downloadScore = 60 + Int((downloadSpeed - 25) / 25 * 20)
        } else if downloadSpeed > 10 {
            downloadScore = 40 + Int((downloadSpeed - 10) / 15 * 20)
        } else if downloadSpeed > 5 {
            downloadScore = 20 + Int((downloadSpeed - 5) / 5 * 20)
        } else {
            downloadScore = Int(downloadSpeed / 5 * 20)
        }

        let uploadScore: Int
        if uploadSpeed > 50 {
            uploadScore = 100
        } else if uploadSpeed > 25 {
            uploadScore = 80 + Int((uploadSpeed - 25) / 25 * 20)
        } else if uploadSpeed > 10 {
            uploadScore = 60 + Int((uploadSpeed - 10) / 15 * 20)
        } else if uploadSpeed > 5 {
            uploadScore = 40 + Int((uploadSpeed - 5) / 5 * 20)
        } else {
            uploadScore = Int(uploadSpeed / 5 * 40)
        }

        return Int(Double(downloadScore) * 0.7 + Double(uploadScore) * 0.3)
    }

    private func calculateLatencyScore(latency: Double, jitter: Double) -> Int {
        var score = 100

        // Latency penalty (70% weight)
        if latency > 200 {
            score -= 50
        } else if latency > 150 {
            score -= 35
        } else if latency > 100 {
            score -= 20
        } else if latency > 50 {
            score -= 10
        }

        // Jitter penalty (30% weight)
        if jitter > 30 {
            score -= 20
        } else if jitter > 20 {
            score -= 15
        } else if jitter > 10 {
            score -= 10
        } else if jitter > 5 {
            score -= 5
        }

        return max(0, min(100, score))
    }

    private func calculateStabilityScore(
        reliability: RegionReliability?,
        modeBenchmark: VPNModeBenchmarkResult,
        failurePrediction: VPNFailurePrediction
    ) -> Int {
        var score = 100

        // Region reliability (40% weight)
        if let reliability = reliability {
            score -= Int(reliability.dropRate * 0.4)
        }

        // Mode stability (30% weight)
        let stabilityPenalty = (100 - modeBenchmark.stabilityScore) / 3
        score -= stabilityPenalty

        // Failure prediction (30% weight)
        let predictionPenalty = failurePrediction.failureProbability / 3
        score -= predictionPenalty

        return max(0, min(100, score))
    }

    private func calculatePrivacyScore(mode: VPNMode, dnsLeakDetected: Bool) -> Int {
        var score = 100

        // DNS leak = major privacy issue
        if dnsLeakDetected {
            score -= 50
        }

        // Mode privacy rating
        switch mode {
        case .stealthMode, .shadowsocks:
            // Best for privacy
            break
        case .wireGuard, .openVPN:
            // Good privacy
            score -= 5
        case .ikev2:
            // Decent privacy
            score -= 10
        case .gamingMode, .streamingMode:
            // Optimized for performance, not privacy
            score -= 15
        case .webProxyMode:
            // Lowest privacy
            score -= 20
        }

        return max(0, min(100, score))
    }

    private func calculateWeightedScore(
        speed: Int,
        latency: Int,
        stability: Int,
        privacy: Int
    ) -> Int {
        let weighted = Double(speed) * speedWeight +
                      Double(latency) * latencyWeight +
                      Double(stability) * stabilityWeight +
                      Double(privacy) * privacyWeight

        return Int(weighted)
    }
}

// MARK: - VPN Setup Score

struct VPNSetupScore: Codable, Sendable {
    let region: String
    let mode: VPNMode
    let overallScore: Int
    let speedScore: Int
    let latencyScore: Int
    let stabilityScore: Int
    let privacyScore: Int
    let downloadSpeed: Double
    let uploadSpeed: Double
    let averageLatency: Double
    let jitter: Double
    let packetLoss: Double
    let tunnelDropRate: Double
    let dnsLeakDetected: Bool

    var grade: String {
        if overallScore >= 90 {
            return "A+ Excellent"
        } else if overallScore >= 80 {
            return "A Good"
        } else if overallScore >= 70 {
            return "B Fair"
        } else if overallScore >= 60 {
            return "C Acceptable"
        } else if overallScore >= 50 {
            return "D Poor"
        } else {
            return "F Very Poor"
        }
    }

    var setupDescription: String {
        return "\(region) + \(mode.rawValue)"
    }

    var detailsSummary: String {
        return """
        Overall Score: \(overallScore)/100 (\(grade))
        Speed: \(String(format: "%.1f", downloadSpeed)) Mbps (\(speedScore)/100)
        Latency: \(String(format: "%.0f", averageLatency)) ms (\(latencyScore)/100)
        Stability: \(stabilityScore)/100
        Privacy: \(privacyScore)/100
        """
    }
}

// MARK: - VPN Setup Recommendation

struct VPNSetupRecommendation: Codable, Sendable {
    let bestOverall: VPNSetupScore?
    let bestForSpeed: VPNSetupScore?
    let bestForLatency: VPNSetupScore?
    let bestForStability: VPNSetupScore?
    let bestForPrivacy: VPNSetupScore?
    let topSetups: [VPNSetupScore]
    let worstSetups: [VPNSetupScore]
    let allScores: [VPNSetupScore]

    var recommendations: [String] {
        var recs: [String] = []

        if let best = bestOverall {
            recs.append("🏆 YOUR BEST VPN SETUP RIGHT NOW:")
            recs.append("\(best.setupDescription)")
            recs.append("")
            recs.append(best.detailsSummary)
        }

        if let best = bestForSpeed, best.setupDescription != bestOverall?.setupDescription {
            recs.append("")
            recs.append("🚀 Best for Speed: \(best.setupDescription)")
            recs.append("   Speed: \(String(format: "%.1f", best.downloadSpeed)) Mbps")
        }

        if let best = bestForLatency, best.setupDescription != bestOverall?.setupDescription {
            recs.append("")
            recs.append("⚡ Best for Latency: \(best.setupDescription)")
            recs.append("   Latency: \(String(format: "%.0f", best.averageLatency)) ms")
        }

        if let best = bestForStability, best.setupDescription != bestOverall?.setupDescription {
            recs.append("")
            recs.append("🔒 Best for Stability: \(best.setupDescription)")
            recs.append("   Stability: \(best.stabilityScore)/100")
        }

        if let best = bestForPrivacy, best.setupDescription != bestOverall?.setupDescription {
            recs.append("")
            recs.append("🔐 Best for Privacy: \(best.setupDescription)")
            recs.append("   Privacy: \(best.privacyScore)/100")
        }

        if !worstSetups.isEmpty {
            recs.append("")
            recs.append("⚠️ AVOID THESE SETUPS:")
            for setup in worstSetups.prefix(3) {
                recs.append("   • \(setup.setupDescription) (Score: \(setup.overallScore)/100)")
            }
        }

        return recs
    }
}

// MARK: - VPN Setup Comparison

struct VPNSetupComparison: Codable, Sendable {
    let currentSetup: VPNSetupScore
    let bestSetup: VPNSetupScore
    let scoreDifference: Int
    let shouldSwitch: Bool
    let improvements: [String]

    var recommendations: [String] {
        var recs: [String] = []

        recs.append("CURRENT SETUP: \(currentSetup.setupDescription)")
        recs.append("Score: \(currentSetup.overallScore)/100")

        if shouldSwitch {
            recs.append("")
            recs.append("⚠️ RECOMMENDED: Switch to \(bestSetup.setupDescription)")
            recs.append("Improvement: +\(scoreDifference) points")
            recs.append("")
            recs.append("You'll gain:")
            recs.append(contentsOf: improvements.map { "  • \($0)" })
        } else {
            recs.append("")
            recs.append("✅ Your current setup is optimal")
            if scoreDifference > 0 {
                recs.append("Best alternative: \(bestSetup.setupDescription) (+\(scoreDifference) points)")
                recs.append("Improvement is minor - stay with current setup")
            }
        }

        return recs
    }
}
