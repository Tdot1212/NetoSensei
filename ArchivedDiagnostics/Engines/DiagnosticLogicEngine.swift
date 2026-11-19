//
//  DiagnosticLogicEngine.swift
//  NetoSensei
//
//  Intelligent symptom-based network diagnosis
//  Like a doctor - diagnose from symptoms, not direct access
//

import Foundation

actor DiagnosticLogicEngine {
    static let shared = DiagnosticLogicEngine()

    private init() {}

    // MARK: - Main Diagnostic Function

    func diagnose(
        vpnActive: Bool,
        publicIP: String,
        localLatency: Double,
        foreignLatency: Double?,
        packetLoss: Double,
        jitter: Int,
        downloadSpeed: Double,
        uploadSpeed: Double? = nil,
        dnsHijackDetected: Bool = false,
        vpnLeakDetected: Bool = false
    ) -> NetworkDiagnosisResult {

        // Calculate symptom indicators
        let hasHighLocalLatency = localLatency > 100
        let hasHighPacketLoss = packetLoss > 3.0
        let hasHighJitter = jitter > 50
        let hasSlowSpeed = downloadSpeed < 10.0

        let hasLatencyJump: Bool
        if let foreign = foreignLatency {
            hasLatencyJump = (foreign - localLatency) > 100
        } else {
            hasLatencyJump = false
        }

        let technicalDetails = TechnicalDetails(
            vpnActive: vpnActive,
            publicIP: publicIP,
            localLatency: localLatency,
            foreignLatency: foreignLatency,
            packetLoss: packetLoss,
            jitter: jitter,
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            hasHighLocalLatency: hasHighLocalLatency,
            hasHighPacketLoss: hasHighPacketLoss,
            hasHighJitter: hasHighJitter,
            hasSlowSpeed: hasSlowSpeed,
            hasLatencyJump: hasLatencyJump
        )

        // Calculate Network Safety Score
        let (safetyScore, safetyReasons) = calculateSafetyScore(
            technicalDetails: technicalDetails,
            dnsHijackDetected: dnsHijackDetected,
            vpnLeakDetected: vpnLeakDetected
        )

        // Diagnostic Logic Tree
        if !vpnActive {
            // VPN OFF scenarios
            return diagnoseWithoutVPN(
                technicalDetails: technicalDetails,
                safetyScore: safetyScore,
                safetyReasons: safetyReasons
            )
        } else {
            // VPN ON scenarios
            return diagnoseWithVPN(
                technicalDetails: technicalDetails,
                safetyScore: safetyScore,
                safetyReasons: safetyReasons
            )
        }
    }

    // MARK: - Network Safety Score Calculation

    private func calculateSafetyScore(
        technicalDetails: TechnicalDetails,
        dnsHijackDetected: Bool,
        vpnLeakDetected: Bool
    ) -> (NetworkSafetyScore, [String]) {

        var riskScore = 0
        var reasons: [String] = []

        // Critical risks
        if dnsHijackDetected {
            riskScore += 30  // Reduced from 50 - ISP DNS manipulation is less severe than actual attack
            reasons.append("ISP DNS interception detected (common in your region) - may affect content access")
        }

        if vpnLeakDetected {
            riskScore += 30
            reasons.append("VPN leak detected - your real IP is exposed")
        }

        // High jitter can indicate MITM or network tampering
        if technicalDetails.jitter > 100 {
            riskScore += 20
            reasons.append("Extremely high jitter (\(technicalDetails.jitter)ms) - possible network tampering")
        } else if technicalDetails.jitter > 50 {
            riskScore += 10
            reasons.append("High jitter (\(technicalDetails.jitter)ms) - unstable connection")
        }

        // Very high packet loss is suspicious
        if technicalDetails.packetLoss > 10 {
            riskScore += 20
            reasons.append("Very high packet loss (\(String(format: "%.1f", technicalDetails.packetLoss))%) - possible network attack")
        } else if technicalDetails.packetLoss > 5 {
            riskScore += 10
            reasons.append("High packet loss (\(String(format: "%.1f", technicalDetails.packetLoss))%)")
        }

        // Unusual latency patterns
        if let foreign = technicalDetails.foreignLatency {
            if foreign > 500 && technicalDetails.localLatency < 50 {
                riskScore += 15
                reasons.append("Unusual routing pattern detected")
            }
        }

        // Determine safety score
        let safetyScore: NetworkSafetyScore
        if riskScore >= 50 {
            safetyScore = .suspicious
        } else if riskScore >= 30 {
            safetyScore = .risky
        } else if riskScore >= 15 {
            safetyScore = .caution
        } else {
            safetyScore = .safe
            if reasons.isEmpty {
                reasons.append("No suspicious network behavior detected")
                reasons.append("DNS resolving correctly")
                reasons.append("Connection is stable")
            }
        }

        return (safetyScore, reasons)
    }

    // MARK: - Scenario A & D: VPN OFF Diagnosis

    private func diagnoseWithoutVPN(
        technicalDetails: TechnicalDetails,
        safetyScore: NetworkSafetyScore,
        safetyReasons: [String]
    ) -> NetworkDiagnosisResult {

        // Scenario A: WiFi ON, VPN OFF → Slow
        // Symptoms: High local latency, high loss/jitter, low speed
        // IMPORTANT: Only blame router if BOTH latency high AND packet loss exists
        // Single latency spike != router issue
        let isRouterActuallyTheIssue = (technicalDetails.localLatency > 20 && technicalDetails.packetLoss > 0) ||
                                        (technicalDetails.localLatency > 50)

        if isRouterActuallyTheIssue ||
           technicalDetails.hasHighPacketLoss ||
           technicalDetails.hasSlowSpeed {

            let problemType: NetworkProblemType = isRouterActuallyTheIssue ? .wifiRouterIssue : .ispLocalCongestion

            // FIXED: Remove WiFi signal advice - iOS cannot measure WiFi signal
            let recommendations: [ActionableRecommendation] = [
                ActionableRecommendation(
                    priority: .critical,
                    action: "Restart your router",
                    reasoning: "Gateway latency is \(Int(technicalDetails.localLatency))ms (should be <30ms)",
                    expectedImprovement: "Should reduce latency to 10-20ms"
                ),
                ActionableRecommendation(
                    priority: .high,
                    action: "Disconnect unused devices from network",
                    reasoning: "Too many devices can cause router congestion",
                    expectedImprovement: "Less competition for bandwidth"
                ),
                ActionableRecommendation(
                    priority: .medium,
                    action: "Check for bandwidth-heavy applications",
                    reasoning: "Downloads/updates can saturate your connection",
                    expectedImprovement: "Free up bandwidth for better performance"
                ),
                ActionableRecommendation(
                    priority: .low,
                    action: "Try connecting to 5GHz band if available",
                    reasoning: "5GHz has less congestion than 2.4GHz",
                    expectedImprovement: "Potentially faster speeds"
                )
            ]

            // FIXED: Remove WiFi signal references from explanation
            let explanation: String
            if isRouterActuallyTheIssue {
                explanation = "Your router is the bottleneck. Gateway latency is \(Int(technicalDetails.localLatency))ms with \(String(format: "%.1f", technicalDetails.packetLoss))% packet loss. This indicates router congestion or too many connected devices."
            } else if technicalDetails.hasHighPacketLoss {
                explanation = "Your connection has \(String(format: "%.1f", technicalDetails.packetLoss))% packet loss. This could be network congestion or ISP instability."
            } else {
                explanation = "Your download speed is \(String(format: "%.1f", technicalDetails.downloadSpeed)) Mbps, which is below expected. This is likely ISP congestion or bandwidth throttling."
            }

            return NetworkDiagnosisResult(
                timestamp: Date(),
                primaryProblem: problemType,
                secondaryProblems: [],
                confidence: .high,
                explanation: explanation,
                recommendations: recommendations,
                technicalDetails: technicalDetails,
                safetyScore: safetyScore,
                safetyReasons: safetyReasons
            )
        }

        // Scenario D: VPN OFF, Netflix blurry (ISP international throttling)
        // Symptoms: Good local, but slow to foreign servers
        if let foreignLatency = technicalDetails.foreignLatency,
           foreignLatency > 200 && technicalDetails.localLatency < 50 {

            let recommendations: [ActionableRecommendation] = [
                ActionableRecommendation(
                    priority: .critical,
                    action: "Enable VPN to improve international routing",
                    reasoning: "Your ISP's route to international servers is slow (\(Int(foreignLatency))ms)",
                    expectedImprovement: "VPN can provide faster route to overseas servers"
                ),
                ActionableRecommendation(
                    priority: .high,
                    action: "Choose VPN server in Japan, Singapore, or Hong Kong",
                    reasoning: "These regions have good connectivity to global CDNs",
                    expectedImprovement: "Lower latency to international content"
                ),
                ActionableRecommendation(
                    priority: .low,
                    action: "Contact your ISP about international routing",
                    reasoning: "Your local connection is fine (\(Int(technicalDetails.localLatency))ms), but international is slow",
                    expectedImprovement: "ISP may fix routing issues"
                )
            ]

            return NetworkDiagnosisResult(
                timestamp: Date(),
                primaryProblem: .ispThrottling,
                secondaryProblems: [],
                confidence: .medium,
                explanation: "Your local WiFi is fine (\(Int(technicalDetails.localLatency))ms), but international routing is slow (\(Int(foreignLatency))ms). This suggests your ISP has poor international connectivity or is throttling overseas traffic. A VPN can bypass this.",
                recommendations: recommendations,
                technicalDetails: technicalDetails,
                safetyScore: safetyScore,
                safetyReasons: safetyReasons
            )
        }

        // No problems detected
        return createNormalDiagnosis(
            technicalDetails: technicalDetails,
            safetyScore: safetyScore,
            safetyReasons: safetyReasons
        )
    }

    // MARK: - Scenario B & C: VPN ON Diagnosis

    private func diagnoseWithVPN(
        technicalDetails: TechnicalDetails,
        safetyScore: NetworkSafetyScore,
        safetyReasons: [String]
    ) -> NetworkDiagnosisResult {

        // Scenario C: VPN keeps reconnecting / unstable
        // Symptoms: Very high jitter, packet loss, latency spikes
        if technicalDetails.hasHighJitter || technicalDetails.hasHighPacketLoss {

            let recommendations: [ActionableRecommendation] = [
                ActionableRecommendation(
                    priority: .critical,
                    action: "Switch to a different VPN server immediately",
                    reasoning: "Your current VPN server is unstable (Jitter: \(technicalDetails.jitter)ms, Loss: \(String(format: "%.1f", technicalDetails.packetLoss))%)",
                    expectedImprovement: "Stable connection with minimal packet loss"
                ),
                ActionableRecommendation(
                    priority: .high,
                    action: "Try a geographically closer VPN location",
                    reasoning: "Distance affects tunnel stability",
                    expectedImprovement: "Lower latency and better stability"
                ),
                ActionableRecommendation(
                    priority: .high,
                    action: "Switch VPN protocol to WireGuard if available",
                    reasoning: "WireGuard handles unstable connections better than OpenVPN",
                    expectedImprovement: "Faster reconnection and better stability"
                ),
                ActionableRecommendation(
                    priority: .medium,
                    action: "Check if your ISP is throttling this VPN provider",
                    reasoning: "High packet loss can indicate VPN blocking attempts",
                    expectedImprovement: "May need to switch VPN providers"
                )
            ]

            return NetworkDiagnosisResult(
                timestamp: Date(),
                primaryProblem: .vpnInstability,
                secondaryProblems: [],
                confidence: .high,
                explanation: "Your VPN tunnel is suffering from instability. Jitter is \(technicalDetails.jitter)ms (should be <30ms) and packet loss is \(String(format: "%.1f", technicalDetails.packetLoss))% (should be <1%). This causes reconnections, buffering, and poor quality.",
                recommendations: recommendations,
                technicalDetails: technicalDetails,
                safetyScore: safetyScore,
                safetyReasons: safetyReasons
            )
        }

        // Scenario B: WiFi ON, VPN ON → Slow
        // Symptoms: Normal WiFi latency, but big latency jump with VPN, slow throughput
        if technicalDetails.hasLatencyJump || (technicalDetails.hasSlowSpeed && !technicalDetails.hasHighLocalLatency) {

            let latencyIncrease = technicalDetails.foreignLatency.map { Int($0 - technicalDetails.localLatency) } ?? 0

            let recommendations: [ActionableRecommendation] = [
                ActionableRecommendation(
                    priority: .critical,
                    action: "Switch to a different VPN region",
                    reasoning: "Your WiFi is fine (\(Int(technicalDetails.localLatency))ms), but VPN adds \(latencyIncrease)ms of latency",
                    expectedImprovement: "Choose closer region: Japan > Singapore > Hong Kong"
                ),
                ActionableRecommendation(
                    priority: .high,
                    action: "Your VPN server is overloaded or too far away",
                    reasoning: "The VPN tunnel itself is the bottleneck, not your WiFi",
                    expectedImprovement: "Switching servers should improve speed significantly"
                ),
                ActionableRecommendation(
                    priority: .medium,
                    action: "Try WireGuard protocol instead of OpenVPN",
                    reasoning: "WireGuard has lower overhead and better performance",
                    expectedImprovement: "Can reduce latency by 10-30%"
                ),
                ActionableRecommendation(
                    priority: .low,
                    action: "Disconnect and reconnect VPN tunnel",
                    reasoning: "Sometimes VPN routing gets stuck on a bad path",
                    expectedImprovement: "May get a better route on reconnection"
                )
            ]

            return NetworkDiagnosisResult(
                timestamp: Date(),
                primaryProblem: .vpnServerSlow,
                secondaryProblems: [],
                confidence: .high,
                explanation: "Your WiFi is NOT the problem (\(Int(technicalDetails.localLatency))ms is good). The VPN server is the bottleneck - it's either overloaded, geographically far, or has poor routing. The VPN adds \(latencyIncrease)ms of extra latency.",
                recommendations: recommendations,
                technicalDetails: technicalDetails,
                safetyScore: safetyScore,
                safetyReasons: safetyReasons
            )
        }

        // VPN ON but no problems detected
        return createNormalDiagnosis(
            technicalDetails: technicalDetails,
            safetyScore: safetyScore,
            safetyReasons: safetyReasons
        )
    }

    // MARK: - Normal Diagnosis

    private func createNormalDiagnosis(
        technicalDetails: TechnicalDetails,
        safetyScore: NetworkSafetyScore,
        safetyReasons: [String]
    ) -> NetworkDiagnosisResult {
        let recommendations: [ActionableRecommendation] = [
            ActionableRecommendation(
                priority: .low,
                action: "Everything looks good!",
                reasoning: "Your network metrics are healthy",
                expectedImprovement: "Keep monitoring if issues arise"
            )
        ]

        let explanation: String
        if technicalDetails.vpnActive {
            explanation = "Your VPN connection is performing well. Latency is \(Int(technicalDetails.localLatency))ms, packet loss is \(String(format: "%.1f", technicalDetails.packetLoss))%, and download speed is \(String(format: "%.1f", technicalDetails.downloadSpeed)) Mbps. All metrics are within healthy ranges."
        } else {
            explanation = "Your internet connection is performing well. Latency is \(Int(technicalDetails.localLatency))ms, packet loss is \(String(format: "%.1f", technicalDetails.packetLoss))%, and download speed is \(String(format: "%.1f", technicalDetails.downloadSpeed)) Mbps. No issues detected."
        }

        return NetworkDiagnosisResult(
            timestamp: Date(),
            primaryProblem: .normalPerformance,
            secondaryProblems: [],
            confidence: .high,
            explanation: explanation,
            recommendations: recommendations,
            technicalDetails: technicalDetails,
                safetyScore: safetyScore,
                safetyReasons: safetyReasons
        )
    }
}
