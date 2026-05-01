//
//  InterpretationEngine.swift
//  NetoSensei
//
//  Layer 3: Interpretation Engine
//  Takes raw NetworkStatus + VPN detection → produces ExplanationCards + NetworkDiagnosis
//
//  5-SCORE SYSTEM:
//    localNetwork (0-100), domesticInternet (0-100), internationalInternet (0-100),
//    privacy (0-100), stability (0-100)
//
//  CHINA-AWARE RULES:
//    Rule 1: International failure ≠ Network broken
//    Rule 2: IPv6 from ISP ≠ VPN
//    Rule 3: System DNS OK but direct fails ≠ Broken
//    Rule 4: Overseas HTTPS timeout ≠ Interception
//    Rule 5: 100% packet loss to ONE server ≠ Network dead
//

import Foundation

@MainActor
class InterpretationEngine: ObservableObject {
    static let shared = InterpretationEngine()

    @Published var currentDiagnosis: NetworkDiagnosis?
    @Published var lastDiagnosedAt: Date?

    private init() {}

    // MARK: - Main Entry Point

    func diagnose(
        status: NetworkStatus,
        vpnResult: SmartVPNDetector.VPNDetectionResult?,
        speedResult: SpeedTestResult? = nil
    ) -> NetworkDiagnosis {

        let vpnState = vpnResult?.vpnState ?? .unknown
        let isVPN = vpnState.isLikelyOn
        let isInChina = vpnResult?.isLikelyInChina ?? false
        let facts = NetworkFacts.from(status: status, vpnResult: vpnResult)

        // Run decision tree steps → ExplanationCards
        let wifiCard = stepWiFi(status: status)
        let routerCard = stepA_LocalNetwork(status: status, vpnActive: isVPN)
        let domesticCard = stepB_DomesticInternet(facts: facts, vpnActive: isVPN)
        let overseasCard = stepC_OverseasInternet(facts: facts, vpnActive: isVPN)
        let dnsCard = stepD_DNS(facts: facts)
        let vpnCard = stepE_VPN(vpnResult: vpnResult, vpnState: vpnState)
        let speedCard = stepF_Speed(speedResult: speedResult, vpnActive: isVPN, isInChina: isInChina)

        var cards: [ExplanationCard] = [wifiCard, routerCard, domesticCard, overseasCard, dnsCard, vpnCard]
        if let sc = speedCard { cards.append(sc) }
        // FIX (Sec Issue 3): emit a Privacy evidence card so the Privacy score
        // is no longer a number with no breakdown.
        cards.append(stepG_Privacy(facts: facts, vpnState: vpnState, vpnResult: vpnResult))

        // Build probe results
        let probes = buildProbeResults(facts: facts, vpnResult: vpnResult, speedResult: speedResult)

        // Compute 5 independent scores
        let scores = computeScores(facts: facts, vpnState: vpnState, vpnResult: vpnResult, speedResult: speedResult)

        // Determine primary issue (China-aware)
        let primaryIssue = determinePrimaryIssue(cards: cards, facts: facts)

        // Generate summary from scores
        let summary = generateSummary(scores: scores, primaryIssue: primaryIssue, vpnState: vpnState, isInChina: isInChina)

        // VPN evidence
        var vpnEvidence: [String] = []
        if let r = vpnResult {
            if r.isAuthoritative {
                vpnEvidence.append("NEVPNManager: \(r.detectionMethod)")
            }
            vpnEvidence.append(contentsOf: r.inferenceReasons)
            for m in r.methodResults where m.detected {
                vpnEvidence.append("\(m.method): \(m.detail)")
            }
        }

        let diagnosis = NetworkDiagnosis(
            timestamp: Date(),
            vpnState: vpnState,
            vpnEvidence: vpnEvidence,
            probeResults: probes,
            cards: cards,
            scores: scores,
            primaryIssue: primaryIssue,
            summary: summary,
            facts: facts
        )

        currentDiagnosis = diagnosis
        lastDiagnosedAt = Date()

        return diagnosis
    }

    /// Quick diagnosis from current shared state
    func diagnoseFromCurrentState() -> NetworkDiagnosis {
        let status = NetworkMonitorService.shared.currentStatus
        let vpnResult = SmartVPNDetector.shared.detectionResult
        return diagnose(status: status, vpnResult: vpnResult)
    }

    // MARK: - 5-Score Computation

    private func computeScores(
        facts: NetworkFacts,
        vpnState: VPNState,
        vpnResult: SmartVPNDetector.VPNDetectionResult?,
        speedResult: SpeedTestResult?
    ) -> NetworkScores {

        // 1. Local Network (gateway + WiFi)
        let localNetwork: Int = {
            guard facts.wifiConnected else { return 10 }
            guard facts.gatewayReachable else { return 20 }
            guard let lat = facts.gatewayLatencyMs else { return 50 }
            let loss = facts.gatewayPacketLoss ?? 0
            var score = 100
            if lat > 50 { score -= 40 }
            else if lat > 20 { score -= 20 }
            else if lat > 10 { score -= 10 }
            if loss > 5 { score -= 30 }
            else if loss > 1 { score -= 15 }
            return max(0, score)
        }()

        // 2. Domestic Internet
        // FIX (Sec Issue 1): When VPN is active, the latency we're measuring
        // is transpacific tunnel RTT (China → LA → back), NOT domestic
        // latency. Penalizing this as "high domestic latency" was wrong —
        // 171ms is normal for a healthy international tunnel. Under VPN,
        // grade only on reachability and let the user judge the tunnel via
        // the VPN evidence card. This stops the cascade where a working
        // VPN scored Domestic Internet 40 ("Fair / possible ISP issue").
        let domesticInternet: Int = {
            guard facts.domesticReachable else { return 0 }
            if vpnState.isLikelyOn {
                // Reachability-only: no latency penalty under VPN.
                return 90
            }
            guard let lat = facts.domesticLatencyMs else { return 60 }
            if lat < 30 { return 100 }
            if lat < 80 { return 85 }
            if lat < 150 { return 65 }
            if lat < 300 { return 40 }
            return 20
        }()

        // 3. International Internet
        // CHINA RULE 1: International failure ≠ Network broken
        let internationalInternet: Int = {
            if facts.isLikelyInChina && !vpnState.isLikelyOn {
                // China without VPN: overseas restricted is EXPECTED
                guard facts.overseasReachable else { return 15 }
                // If overseas reachable without VPN from China, that's unusual
                return 70
            }
            guard facts.overseasReachable else { return 0 }
            // Use speed test ping as overseas latency proxy if available
            if let speed = speedResult {
                if speed.ping < 50 { return 100 }
                if speed.ping < 100 { return 80 }
                if speed.ping < 200 { return 60 }
                return 40
            }
            return 75  // Reachable but no latency data
        }()

        // 4. Privacy
        // FIX (Sec Issue 3): Replaced the opaque single-input switch with a
        // transparent rubric. Components also feed an Evidence card (see
        // `stepG_Privacy`) so users can see what drove the score.
        let privacy = privacyComponents(facts: facts, vpnState: vpnState, vpnResult: vpnResult).total

        // 5. Stability
        let stability: Int = {
            var score = 100
            let loss = facts.gatewayPacketLoss ?? 0
            let jitter = facts.gatewayJitterMs ?? 0
            if loss > 10 { score -= 50 }
            else if loss > 5 { score -= 30 }
            else if loss > 1 { score -= 15 }
            if jitter > 50 { score -= 30 }
            else if jitter > 20 { score -= 15 }
            else if jitter > 10 { score -= 5 }
            if let speed = speedResult, speed.packetLoss > 3 {
                score -= 20
            }
            return max(0, score)
        }()

        return NetworkScores(
            localNetwork: localNetwork,
            domesticInternet: domesticInternet,
            internationalInternet: internationalInternet,
            privacy: privacy,
            stability: stability
        )
    }

    // MARK: - Privacy Components (Sec Issue 3)
    // Transparent rubric for the Privacy score. Each component contributes a
    // labeled delta so the Evidence card can show the user where the number
    // came from. Replaces the old single-input switch on vpnState.

    struct PrivacyComponent {
        let label: String      // "VPN active"
        let detail: String     // "Confirmed by NEVPNManager"
        let delta: Int         // +30, -10, etc.
        let positive: Bool     // for ✓ vs ⚠ glyph
    }

    private struct PrivacyComputation {
        let total: Int
        let components: [PrivacyComponent]
    }

    /// Compute Privacy score and the components that fed it.
    /// Base 50 = neutral (no VPN, no leak). Components add or subtract.
    /// Capped at [0, 100].
    private func privacyComponents(
        facts: NetworkFacts,
        vpnState: VPNState,
        vpnResult: SmartVPNDetector.VPNDetectionResult?
    ) -> PrivacyComputation {
        var score = 50
        var parts: [PrivacyComponent] = []

        // Component 1: VPN status
        switch vpnState {
        case .on:
            score += 35
            parts.append(.init(label: "VPN active", detail: "Confirmed by NEVPNManager", delta: 35, positive: true))
        case .probablyOn:
            score += 25
            parts.append(.init(label: "VPN active", detail: "Inferred from IP/country mismatch", delta: 25, positive: true))
        case .connecting:
            score += 10
            parts.append(.init(label: "VPN connecting", detail: "Transitional state", delta: 10, positive: true))
        case .off:
            parts.append(.init(label: "No VPN", detail: "Confirmed by NEVPNManager — your real IP is visible", delta: 0, positive: false))
        case .probablyOff:
            parts.append(.init(label: "No VPN", detail: "Inferred from residential ISP — your real IP is likely visible", delta: 0, positive: false))
        case .unknown:
            parts.append(.init(label: "VPN status unknown", detail: "Could not determine VPN state", delta: 0, positive: false))
        }

        // Component 2: IP masking (country mismatch as proxy for "real IP hidden")
        let publicCountry = vpnResult?.publicCountry ?? facts.ipCountry ?? ""
        let deviceLocale = Locale.current.region?.identifier ?? ""
        let likelyOn = vpnState.isLikelyOn
        if likelyOn && !publicCountry.isEmpty && !deviceLocale.isEmpty && publicCountry != deviceLocale {
            score += 15
            parts.append(.init(
                label: "IP masked",
                detail: "Public IP geolocated to \(publicCountry), device locale \(deviceLocale)",
                delta: 15, positive: true
            ))
        } else if likelyOn {
            parts.append(.init(label: "IP not masked", detail: "VPN active but IP country matches device locale", delta: 0, positive: false))
        }

        // Component 3: IPv6 leak (from VPN detection method results)
        // The IPv6 Check method emits "Native ISP IPv6 present" when residential
        // IPv6 is leaking outside the tunnel.
        let ipv6Leak: Bool = {
            guard let methods = vpnResult?.methodResults else { return false }
            return methods.contains { $0.method == "IPv6 Check" && $0.detail.lowercased().contains("native isp ipv6") }
        }()
        if ipv6Leak && likelyOn {
            score -= 15
            parts.append(.init(
                label: "IPv6 leak",
                detail: "Native ISP IPv6 routes outside the VPN tunnel",
                delta: -15, positive: false
            ))
        } else if !ipv6Leak {
            // Only mention "no leak" when VPN is on (otherwise it's not a meaningful credit).
            if likelyOn {
                parts.append(.init(label: "No IPv6 leak", detail: "All traffic appears to route through VPN", delta: 0, positive: true))
            }
        }

        // Component 4: DNS encryption (we don't have a reliable DoH/DoT signal
        // here; mark as unknown so the Evidence row is honest).
        parts.append(.init(
            label: "DNS encryption",
            detail: "Status unknown — iOS doesn't expose system DNS encryption to third-party apps",
            delta: 0, positive: false
        ))

        return PrivacyComputation(total: max(0, min(100, score)), components: parts)
    }

    /// Build an Evidence card explaining the Privacy score.
    private func stepG_Privacy(
        facts: NetworkFacts,
        vpnState: VPNState,
        vpnResult: SmartVPNDetector.VPNDetectionResult?
    ) -> ExplanationCard {
        let computation = privacyComponents(facts: facts, vpnState: vpnState, vpnResult: vpnResult)
        let measured = "Privacy score: \(computation.total) / 100\n" +
            computation.components.map { c in
                let sign = c.delta > 0 ? "+\(c.delta)" : "\(c.delta)"
                return "• \(c.label) \(sign): \(c.detail)"
            }.joined(separator: "\n")

        let result: CardResult
        if computation.total >= 80 { result = .good }
        else if computation.total >= 50 { result = .warning }
        else { result = .problem }

        // Surface the most actionable next step
        let leakDetected = computation.components.contains { $0.delta < 0 }
        let nextSteps: String = {
            if leakDetected {
                return "An IPv6 leak was detected. To fix: disable IPv6 in your proxy app settings (Surge / Shadowrocket: Settings → IPv6 → Off), or use a VPN profile that tunnels IPv6."
            }
            if vpnState == .off || vpnState == .probablyOff {
                return "Connect to a VPN to encrypt traffic and hide your real IP."
            }
            return "No action needed — privacy posture looks good."
        }()

        return ExplanationCard(
            category: .privacy,
            measured: measured,
            result: result,
            confidence: vpnState.isAuthoritative ? .high("VPN state confirmed by system; other components inferred") : .medium("Multiple inputs combined; some inferred"),
            nextSteps: nextSteps,
            iOSLimitation: "DNS encryption status is not exposed to third-party iOS apps without entitlement.",
            displayLabel: "Privacy"
        )
    }

    // MARK: - Step WiFi

    private func stepWiFi(status: NetworkStatus) -> ExplanationCard {
        if status.wifi.isConnected {
            let ssidText = status.wifi.ssid.map { "Connected to \"\($0)\"" } ?? "Connected (SSID requires Location permission)"
            return ExplanationCard(
                category: .wifi,
                measured: ssidText,
                result: .good,
                confidence: status.wifi.ssid != nil ? .high("System reports WiFi connected") : .medium("Connected but SSID unavailable"),
                nextSteps: "No action needed",
                iOSLimitation: "iOS cannot measure WiFi signal strength (RSSI), channel, or link speed via public APIs"
            )
        } else {
            return ExplanationCard(
                category: .wifi,
                measured: "WiFi not connected",
                result: status.connectionType == .cellular ? .warning : .problem,
                confidence: .high("NWPathMonitor reports no WiFi"),
                nextSteps: status.connectionType == .cellular ? "Using cellular data" : "Connect to a WiFi network",
                iOSLimitation: nil
            )
        }
    }

    // MARK: - Step A: Local Network

    private func stepA_LocalNetwork(status: NetworkStatus, vpnActive: Bool) -> ExplanationCard {
        // CHINA RULE: "Router hidden by VPN tunnel" ONLY when VPN is actually confirmed
        if vpnActive && !status.router.isReachable {
            return ExplanationCard(
                category: .router,
                measured: "Gateway: \(status.router.gatewayIP ?? "unknown") — unreachable while VPN active",
                result: .hidden,
                confidence: .high("VPN tunnels typically prevent local gateway access"),
                nextSteps: "This is normal with VPN active — not a WiFi problem",
                iOSLimitation: nil
            )
        }

        guard status.router.isReachable, let latency = status.router.latency else {
            return ExplanationCard(
                category: .router,
                measured: "Gateway: \(status.router.gatewayIP ?? "unknown") — unreachable",
                result: .problem,
                confidence: .high("TCP connect to gateway failed"),
                nextSteps: "Check WiFi connection. Restart router if issue persists.",
                iOSLimitation: nil
            )
        }

        let loss = status.router.packetLoss ?? 0
        let jitter = status.router.jitter ?? 0

        let result: CardResult
        let nextSteps: String

        if latency < 10 && loss < 1 {
            result = .good
            nextSteps = "No action needed"
        } else if latency < 30 && loss < 3 {
            result = .warning
            nextSteps = "Move closer to router or reduce devices on network"
        } else {
            result = .problem
            nextSteps = "WiFi signal is weak. Move closer to router, or restart router."
        }

        var measured = "Gateway latency: \(String(format: "%.0f", latency))ms (median of 5 pings)"
        if loss > 0 { measured += ", packet loss: \(String(format: "%.0f", loss))%" }
        if jitter > 5 { measured += ", jitter: \(String(format: "%.0f", jitter))ms" }

        return ExplanationCard(
            category: .router,
            measured: measured,
            result: result,
            confidence: .high("Measured via TCP connect to \(status.router.gatewayIP ?? "gateway")"),
            nextSteps: nextSteps,
            iOSLimitation: "Gateway latency measured via TCP connect, not ICMP ping (iOS limitation)"
        )
    }

    // MARK: - Step B: Domestic Internet

    private func stepB_DomesticInternet(facts: NetworkFacts, vpnActive: Bool) -> ExplanationCard {
        // FIX (Sec Issue 6): label cards distinctly so the Evidence list
        // doesn't show two consecutive bare "Internet" rows.
        let label = "Domestic Internet"
        guard facts.domesticReachable else {
            return ExplanationCard(
                category: .internet,
                measured: "Domestic internet: unreachable (tested \(facts.domesticTarget))",
                result: .problem,
                confidence: .high("HTTP test to \(facts.domesticTarget) failed"),
                nextSteps: facts.isLikelyInChina ? "Check ISP connection. Try restarting router." : "Check internet connection.",
                iOSLimitation: nil,
                displayLabel: label
            )
        }

        // FIX (Sec Issue 1): Under VPN, the measured latency is transpacific
        // tunnel transit, NOT domestic latency. Reframe the card honestly
        // instead of telling the user "high latency — possible ISP issue".
        if vpnActive, let latency = facts.domesticLatencyMs {
            return ExplanationCard(
                category: .internet,
                measured: "Latency through VPN tunnel: \(String(format: "%.0f", latency))ms (normal for transpacific routing)",
                result: .good,
                confidence: .medium("Measurement reflects tunnel RTT to the VPN exit, not local network"),
                nextSteps: "Tunnel transit is working. To compare bandwidth, use the Speed tab.",
                iOSLimitation: "Probe target is hardcoded; under VPN, all destinations route via the tunnel exit, so 'domestic' vs 'international' is not meaningful here.",
                displayLabel: label
            )
        }

        if let latency = facts.domesticLatencyMs {
            let result: CardResult
            let nextSteps: String

            if latency < 50 {
                result = .good
                nextSteps = "No action needed"
            } else if latency < 150 {
                result = .warning
                nextSteps = "Slightly elevated latency — may be ISP congestion"
            } else {
                result = .problem
                nextSteps = "High latency — possible ISP issue or network congestion"
            }

            return ExplanationCard(
                category: .internet,
                measured: "Domestic latency: \(String(format: "%.0f", latency))ms (via \(facts.domesticTarget))",
                result: result,
                confidence: .medium("Measured via HTTP to \(facts.domesticTarget)"),
                nextSteps: nextSteps,
                iOSLimitation: "iOS cannot send ICMP ping — latency measured via HTTP",
                displayLabel: label
            )
        }

        return ExplanationCard(
            category: .internet,
            measured: "Domestic internet reachable (latency unknown)",
            result: .unknown,
            confidence: .low("HTTP succeeded but timing unavailable"),
            nextSteps: "Run a diagnostic for more detail",
            iOSLimitation: nil,
            displayLabel: label
        )
    }

    // MARK: - Step C: Overseas Internet (China-aware)

    private func stepC_OverseasInternet(facts: NetworkFacts, vpnActive: Bool) -> ExplanationCard {
        // FIX (Sec Issue 6): label cards distinctly so the Evidence list
        // doesn't show two consecutive bare "Internet" rows.
        let label = "International Internet"
        // Outside China: domestic and overseas are effectively the same
        guard facts.isLikelyInChina else {
            let reachable = facts.overseasReachable
            return ExplanationCard(
                category: .internet,
                measured: "International connectivity: \(reachable ? "OK" : "unreachable")",
                result: reachable ? .good : .problem,
                confidence: reachable ? .high("HTTP test succeeded") : .high("HTTP test failed"),
                nextSteps: reachable ? "No action needed" : "Check internet connection",
                iOSLimitation: nil,
                displayLabel: label
            )
        }

        // CHINA RULE 1: International failure ≠ Network broken
        if !facts.overseasReachable && facts.domesticReachable {
            if vpnActive {
                return ExplanationCard(
                    category: .internet,
                    measured: "Overseas via VPN: unreachable",
                    result: .warning,
                    confidence: .medium("VPN may be slow or server unreachable"),
                    nextSteps: "Try a different VPN server — current server may be congested",
                    iOSLimitation: nil,
                    displayLabel: label
                )
            } else {
                // CHINA-AWARE: This is EXPECTED, not a network failure
                return ExplanationCard(
                    category: .internet,
                    measured: "International access restricted or degraded (domestic OK)",
                    result: .warning,
                    confidence: .high("Domestic internet works. Cross-border access is restricted without VPN."),
                    nextSteps: "Connect to a VPN for overseas access (Google, YouTube, etc.)",
                    iOSLimitation: nil,
                    displayLabel: label
                )
            }
        }

        if facts.overseasReachable {
            let detail = vpnActive ? "Overseas reachable via VPN" : "Overseas reachable"
            return ExplanationCard(
                category: .internet,
                measured: detail,
                result: .good,
                confidence: vpnActive
                    ? .medium("Tested via VPN tunnel — speed reflects international bandwidth")
                    : .high("HTTP test to overseas server succeeded"),
                nextSteps: "No action needed",
                iOSLimitation: nil,
                displayLabel: label
            )
        }

        // Both domestic and overseas unreachable
        return ExplanationCard(
            category: .internet,
            measured: "Internet unreachable (both domestic and overseas)",
            result: .problem,
            confidence: .high("All connectivity tests failed"),
            nextSteps: "Check WiFi connection and restart router",
            iOSLimitation: nil,
            displayLabel: label
        )
    }

    // MARK: - Step D: DNS (China-aware)

    private func stepD_DNS(facts: NetworkFacts) -> ExplanationCard {
        // CHINA RULE 3: System DNS OK but direct fails ≠ Broken
        guard facts.dnsLookupSuccess else {
            let detail = facts.isLikelyInChina
                ? "System resolver may work, but direct DNS could be filtered"
                : "Domain lookup failed"
            return ExplanationCard(
                category: .dns,
                measured: "DNS resolution: \(detail)",
                result: facts.isLikelyInChina ? .warning : .problem,
                confidence: facts.isLikelyInChina
                    ? .medium("System DNS may still work despite direct query failure")
                    : .high("Domain lookup failed"),
                nextSteps: facts.isLikelyInChina
                    ? "System resolver may still work. Try 114.114.114.114 or 223.5.5.5 for China."
                    : "Try changing DNS to 1.1.1.1 or 8.8.8.8 in WiFi settings",
                iOSLimitation: nil
            )
        }

        guard let latency = facts.dnsLatencyMs else {
            return ExplanationCard(
                category: .dns,
                measured: "DNS: working (latency unknown)",
                result: .unknown,
                confidence: .low("DNS succeeded but timing unavailable"),
                nextSteps: "Run DNS benchmark for detailed results",
                iOSLimitation: nil
            )
        }

        let resolver = facts.dnsResolverIP ?? "system default"
        let result: CardResult
        let nextSteps: String

        if latency < 30 {
            result = .good
            nextSteps = "No action needed"
        } else if latency < 100 {
            result = .warning
            nextSteps = facts.isLikelyInChina
                ? "Consider 114.114.114.114 or 223.5.5.5 for faster DNS in China"
                : "Consider switching to a faster DNS (1.1.1.1 or 8.8.8.8)"
        } else {
            result = .problem
            nextSteps = facts.isLikelyInChina
                ? "DNS is slow — try 114.114.114.114, 223.5.5.5, or 119.29.29.29"
                : "DNS is slow — switch to 1.1.1.1 or 8.8.8.8 in your WiFi settings"
        }

        return ExplanationCard(
            category: .dns,
            measured: "DNS latency: \(String(format: "%.0f", latency))ms (resolver: \(resolver))",
            result: result,
            confidence: .high("Measured via UDP port 53 query"),
            nextSteps: nextSteps,
            iOSLimitation: nil
        )
    }

    // MARK: - Step E: VPN

    private func stepE_VPN(
        vpnResult: SmartVPNDetector.VPNDetectionResult?,
        vpnState: VPNState
    ) -> ExplanationCard {
        let measured: String
        let result: CardResult
        let confidence: CardConfidence
        let nextSteps: String
        var limitation: String? = nil

        switch vpnState {
        case .on:
            let proto = vpnResult?.vpnProtocol ?? "VPN"
            let location = vpnResult?.publicCity ?? vpnResult?.publicCountry ?? "unknown location"
            measured = "\(proto) connected — exit IP in \(location)"
            result = .good
            confidence = .high("NEVPNManager confirmed VPN connected")
            nextSteps = "VPN is working as expected"

        case .off:
            measured = "No VPN active"
            result = .good
            confidence = .high("NEVPNManager confirmed no VPN")
            nextSteps = "No action needed"

        case .connecting:
            measured = "VPN connecting..."
            result = .warning
            confidence = .high("NEVPNManager reports transitional state")
            nextSteps = "Wait for VPN to finish connecting"

        case .probablyOn:
            let isp = vpnResult?.publicISP ?? "unknown"
            let reasons = vpnResult?.inferenceReasons.joined(separator: "; ") ?? "datacenter IP detected"
            measured = "VPN/Proxy detected (inferred) — ISP: \(isp)"
            result = .warning
            confidence = .medium("Inferred: \(reasons)")
            // FIX (Sec Issue 4): The previous copy ("If you're not using a
            // VPN, your ISP may use datacenter IPs") contradicted the verdict
            // three rows above on the same card. We're already in the
            // "VPN inferred" branch — say so honestly.
            nextSteps = "VPN detected via IP/country mismatch. ISP-level confirmation unavailable because iOS does not expose VPN profile metadata to third-party apps without entitlement."
            limitation = "iOS can only detect VPN profiles registered with the system. Third-party proxy apps may not be detected authoritatively."

        case .probablyOff:
            let isp = vpnResult?.publicISP ?? "residential ISP"
            measured = "No VPN detected — IP from \(isp)"
            result = .good
            confidence = .medium("Inferred from residential ISP classification")
            nextSteps = "No action needed"
            limitation = "NEVPNManager entitlement not available — VPN status inferred from IP"

        case .unknown:
            measured = "VPN status: could not determine"
            result = .unknown
            confidence = .low("Insufficient data to determine VPN status")
            nextSteps = "Run a full diagnostic for more detail"
            limitation = "VPN detection requires network access and IP lookup"
        }

        return ExplanationCard(
            category: .vpn,
            measured: measured,
            result: result,
            confidence: confidence,
            nextSteps: nextSteps,
            iOSLimitation: limitation
        )
    }

    // MARK: - Step F: Speed

    private func stepF_Speed(
        speedResult: SpeedTestResult?,
        vpnActive: Bool,
        isInChina: Bool
    ) -> ExplanationCard? {
        guard let speed = speedResult else { return nil }

        let dl = speed.downloadSpeed
        let ul = speed.uploadSpeed
        let ping = speed.ping

        let result: CardResult
        let nextSteps: String

        if dl >= 25 && ul >= 5 && ping < 50 {
            result = .good
            nextSteps = "No action needed — speeds are good for streaming and video calls"
        } else if dl >= 5 && ul >= 1 {
            result = .warning
            nextSteps = vpnActive
                ? "Speeds reduced by VPN — try a closer VPN server for better throughput"
                : "Speeds are moderate — adequate for browsing but may struggle with HD video"
        } else if dl > 0 {
            result = .problem
            nextSteps = vpnActive
                ? "Very slow — VPN server may be congested. Try a different server."
                : "Very slow connection — check with your ISP or try restarting router"
        } else {
            // CHINA RULE 5: Speed test failure to ONE server ≠ network dead
            result = .problem
            nextSteps = isInChina && !vpnActive
                ? "Test endpoint unreachable — Cloudflare may be throttled from China without VPN"
                : "Speed test failed — check internet connection"
        }

        var measured = "Download: \(String(format: "%.1f", dl)) Mbps, Upload: \(String(format: "%.1f", ul)) Mbps"
        measured += ", Ping: \(String(format: "%.0f", ping))ms"
        if speed.packetLoss > 0 {
            measured += ", Loss: \(String(format: "%.0f", speed.packetLoss))%"
        }

        var limitation: String? = nil
        if isInChina && !vpnActive {
            limitation = "Speed test uses Cloudflare (overseas). Results reflect international bandwidth, not domestic speed."
        }

        return ExplanationCard(
            category: .speed,
            measured: measured,
            result: result,
            confidence: vpnActive
                ? .medium("Speed measured through VPN tunnel — reflects VPN + ISP combined")
                : .high("Measured via Cloudflare speed test"),
            nextSteps: nextSteps,
            iOSLimitation: limitation
        )
    }

    // MARK: - Build Probe Results

    private func buildProbeResults(
        facts: NetworkFacts,
        vpnResult: SmartVPNDetector.VPNDetectionResult?,
        speedResult: SpeedTestResult?
    ) -> [ProbeResult] {
        let now = Date()
        var probes: [ProbeResult] = []

        // LOCAL_NETWORK
        probes.append(ProbeResult(
            name: "LOCAL_NETWORK",
            target: facts.gatewayIP ?? "gateway",
            status: facts.gatewayReachable ? .success : .failed,
            latencyMs: facts.gatewayLatencyMs,
            detail: facts.gatewayReachable
                ? "Gateway responds in \(facts.gatewayLatencyMs.map { String(format: "%.0fms", $0) } ?? "?ms")"
                : "Gateway unreachable",
            confidence: 0.95,
            timestamp: now
        ))

        // DOMESTIC_INTERNET
        probes.append(ProbeResult(
            name: "DOMESTIC_INTERNET",
            target: facts.domesticTarget,
            status: facts.domesticReachable ? .success : .failed,
            latencyMs: facts.domesticLatencyMs,
            detail: facts.domesticReachable
                ? "Domestic internet reachable (\(facts.domesticLatencyMs.map { String(format: "%.0fms", $0) } ?? "?ms"))"
                : "Domestic internet unreachable",
            confidence: 0.9,
            timestamp: now
        ))

        // OVERSEAS_INTERNET
        probes.append(ProbeResult(
            name: "OVERSEAS_INTERNET",
            target: facts.overseasTarget,
            status: facts.overseasReachable ? .success : (facts.isLikelyInChina ? .blocked : .failed),
            latencyMs: facts.overseasLatencyMs,
            detail: facts.overseasReachable
                ? "Overseas internet reachable"
                : (facts.isLikelyInChina ? "Cross-border access restricted" : "Overseas internet unreachable"),
            confidence: 0.85,
            timestamp: now
        ))

        // SYSTEM_DNS
        probes.append(ProbeResult(
            name: "SYSTEM_DNS",
            target: facts.dnsResolverIP ?? "system DNS",
            status: facts.dnsLookupSuccess ? .success : .failed,
            latencyMs: facts.dnsLatencyMs,
            detail: facts.dnsLookupSuccess
                ? "DNS resolving (\(facts.dnsLatencyMs.map { String(format: "%.0fms", $0) } ?? "?ms"))"
                : "DNS resolution failed",
            confidence: 0.95,
            timestamp: now
        ))

        // VPN_STATE
        let vpnState = vpnResult?.vpnState ?? .unknown
        probes.append(ProbeResult(
            name: "VPN_STATE",
            target: "NEVPNManager + ISP inference",
            status: vpnState == .unknown ? .unavailable : .success,
            latencyMs: nil,
            detail: vpnState.displayText,
            confidence: vpnState.isAuthoritative ? 1.0 : 0.7,
            timestamp: now
        ))

        // IP_IDENTITY
        if let vr = vpnResult {
            probes.append(ProbeResult(
                name: "IP_IDENTITY",
                target: vr.publicIP ?? "unknown",
                status: vr.publicIP != nil ? .success : .failed,
                latencyMs: nil,
                detail: "IP: \(vr.publicIP ?? "?"), ISP: \(vr.publicISP ?? "?"), Country: \(vr.publicCountry ?? "?")",
                confidence: vr.ipVerified ? 0.95 : 0.6,
                timestamp: now
            ))
        }

        // SPEED (if available)
        if let speed = speedResult {
            probes.append(ProbeResult(
                name: "SPEED_TEST",
                target: speed.serverUsed ?? "speed test server",
                status: speed.downloadSpeed > 0 ? .success : .failed,
                latencyMs: speed.ping,
                detail: "DL: \(String(format: "%.1f", speed.downloadSpeed)) Mbps, UL: \(String(format: "%.1f", speed.uploadSpeed)) Mbps",
                confidence: 0.85,
                timestamp: now
            ))
        }

        return probes
    }

    // MARK: - Primary Issue (China-aware)

    private func determinePrimaryIssue(cards: [ExplanationCard], facts: NetworkFacts) -> String? {
        // CHINA RULE 1: If domestic works but overseas fails, that's NOT the primary issue
        let problemCards = cards.filter { $0.result == .problem }
        let warningCards = cards.filter { $0.result == .warning }

        // Check for real problems first (not overseas-blocked)
        let priorityOrder: [CardCategory] = [.router, .internet, .dns, .wifi, .vpn, .speed, .tls]

        for category in priorityOrder {
            if let card = problemCards.first(where: { $0.category == category }) {
                return card.nextSteps
            }
        }

        for category in priorityOrder {
            if let card = warningCards.first(where: { $0.category == category }) {
                return card.nextSteps
            }
        }

        return nil
    }

    // MARK: - Summary (5-score based)

    private func generateSummary(scores: NetworkScores, primaryIssue: String?, vpnState: VPNState, isInChina: Bool) -> String {
        let vpnPrefix: String
        switch vpnState {
        case .on: vpnPrefix = "VPN active. "
        case .probablyOn: vpnPrefix = "VPN/proxy likely active. "
        case .connecting: vpnPrefix = "VPN connecting. "
        default: vpnPrefix = ""
        }

        // Use the 5-score summary
        var text = "\(vpnPrefix)\(scores.summary)"

        // Add China-specific context
        if isInChina && scores.internationalInternet < 30 && scores.domesticInternet >= 60 {
            text += ". International access restricted — domestic network is fine."
        }

        return text
    }
}
