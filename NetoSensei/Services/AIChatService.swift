//
//  AIChatService.swift
//  NetoSensei
//
//  Multi-provider AI chat service for network diagnostic assistance.
//  VPN-aware system prompt prevents false alarms for China proxy users.
//

import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: String  // "user", "assistant", "system"
    let content: String
    let timestamp: Date
    var isLoading: Bool

    init(role: String, content: String, isLoading: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isLoading = isLoading
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - AI Network Data Models

struct DiagnosticTestSummary: Codable {
    var name: String
    var result: String      // "pass", "warning", "fail", "skipped"
    var latencyMs: Double?
    var details: String
}

struct DNSHijackSummary: Codable {
    var status: String      // "clean", "detected", "not_tested"
    var hijacked: Bool
    var note: String?
}

struct SpeedHistorySummary: Codable {
    var timestamp: String
    var downloadMbps: Double
    var uploadMbps: Double
    var pingMs: Double
    var vpnActive: Bool
}

struct AINetworkData: Codable {
    // Which features have been tested
    var featuresTested: [String: Bool]

    // Dashboard
    var connectionType: String?
    var ssid: String?
    var signalQuality: String?
    var healthScore: String?

    // Diagnostic results (if run)
    var diagnosticSummary: String?
    var diagnosticIssueCount: Int?
    var diagnosticPrimaryIssue: String?
    var diagnosticOverallStatus: String?

    // Speed test (if run)
    var downloadMbps: Double?
    var uploadMbps: Double?
    var pingMs: Double?
    var jitterMs: Double?
    var packetLossPercent: Double?
    var speedTestServer: String?
    var speedTestQuality: String?

    // VPN detection
    var vpnActive: Bool?
    var vpnConfidence: Double?
    var vpnInference: String?
    var vpnState: String?
    var vpnDetectionMethod: String?
    var publicIP: String?
    var ipCountry: String?
    var ipCity: String?
    var deviceCountry: String?
    var vpnTunnelType: String?
    var vpnDnsLeakDetected: Bool?

    // Security scan (if run)
    var dnsHijackResult: DNSHijackSummary?
    var vpnLeakDetected: Bool?
    var tlsIssues: [String]?
    var threatLevel: String?
    var securityRating: Int?

    // Connection stability
    var recentStabilityEvents: [String]?
    var latencySpikeCount: Int?
    var uptimePercentage: Double?
    var disconnectCount: Int?

    // Network details
    var gatewayIP: String?
    var gatewayReachable: Bool?
    var gatewayLatencyMs: Double?
    var internetReachable: Bool?
    var externalLatencyMs: Double?
    var dnsResolverIP: String?
    var dnsLatencyMs: Double?
    var isCGNAT: Bool?
    var isProxyDetected: Bool?

    // GeoIP
    var geoIPCountry: String?
    var geoIPCity: String?
    var geoIPISP: String?
    var geoIPASN: String?

    // Device discovery (if run)
    var devicesFound: Int?
    var devicesConnectedNow: Int?
    var newDevices: Int?
    var untrustedDevices: Int?

    // Port scan (if run)
    var openPorts: [String]?
    var portScanRiskLevel: String?

    // TLS analysis (if run)
    var tlsAnalysisSites: [String]?

    // Speed test history (last 5 for trends)
    var speedHistory: [SpeedHistorySummary]?
}

// MARK: - AI Data Collector

/// Aggregates ALL available diagnostic data into a Codable struct for AI context.
@MainActor
struct AIDataCollector {

    static func collect() -> AINetworkData {
        let status = NetworkMonitorService.shared.currentStatus
        let vpnResult = SmartVPNDetector.shared.detectionResult
        let geoIP = GeoIPService.shared.currentGeoIP
        let speedResult = HistoryManager.shared.speedTestHistory.last
        let securityResult = SecurityScanService.shared.currentScan
        let stability = ConnectionStabilityMonitor.shared
        let portResults = PortScanner.shared.results
        let devices = DeviceHistoryManager.shared.devices
        let diagnosticHistory = HistoryManager.shared.diagnosticHistory
        let speedHistory = HistoryManager.shared.speedTestHistory
        let tlsResults = TLSAnalyzer.shared.recentResults

        // -- Features tested --
        let featuresTested: [String: Bool] = [
            "dashboard": true,
            "speed_test": speedResult != nil,
            "diagnostic": !diagnosticHistory.isEmpty,
            "vpn_detection": vpnResult != nil,
            "security_scan": securityResult != nil,
            "stability_monitor": stability.isMonitoring,
            "device_discovery": !devices.isEmpty,
            "port_scanner": !portResults.isEmpty,
            "tls_analysis": !tlsResults.isEmpty
        ]

        var data = AINetworkData(featuresTested: featuresTested)

        // -- Dashboard / Network Status --
        data.connectionType = status.connectionType?.displayName ?? "Unknown"
        data.ssid = status.wifi.ssid
        data.signalQuality = healthString(status.overallHealth)
        data.healthScore = healthString(status.overallHealth)
        data.gatewayIP = status.router.gatewayIP
        data.gatewayReachable = status.router.isReachable
        data.gatewayLatencyMs = status.router.latency
        data.internetReachable = status.internet.isReachable
        data.externalLatencyMs = status.internet.latencyToExternal
        data.dnsResolverIP = status.dns.resolverIP
        data.dnsLatencyMs = status.dns.latency
        data.isCGNAT = status.isCGNAT
        data.isProxyDetected = status.isProxyDetected

        // -- VPN Detection --
        let liveVPN = status.vpn
        data.vpnActive = liveVPN.isActive
        data.vpnConfidence = liveVPN.detectionConfidence
        data.vpnTunnelType = liveVPN.tunnelType
        data.vpnDnsLeakDetected = liveVPN.dnsLeakDetected
        data.vpnState = liveVPN.vpnState.rawValue

        if let vpn = vpnResult {
            data.vpnDetectionMethod = vpn.detectionMethod
            data.vpnInference = vpn.inferenceReasons.joined(separator: "; ")
            data.publicIP = vpn.publicIP
            data.ipCountry = vpn.publicCountry
            data.ipCity = vpn.publicCity
            data.deviceCountry = vpn.expectedCountry
        } else {
            data.publicIP = status.publicIP
        }

        // -- GeoIP --
        data.geoIPCountry = geoIP.country
        data.geoIPCity = geoIP.city
        data.geoIPISP = geoIP.isp
        data.geoIPASN = geoIP.asn

        // -- Speed Test --
        if let speed = speedResult {
            data.downloadMbps = speed.downloadSpeed
            data.uploadMbps = speed.uploadSpeed
            data.pingMs = speed.ping
            data.jitterMs = speed.jitter
            data.packetLossPercent = speed.packetLoss
            data.speedTestServer = speed.serverUsed
            data.speedTestQuality = speed.quality.rawValue
        }

        // -- Diagnostic History --
        if let lastDiag = diagnosticHistory.first {
            data.diagnosticSummary = lastDiag.summary
            data.diagnosticIssueCount = lastDiag.issueCount
            data.diagnosticPrimaryIssue = lastDiag.primaryIssueCategory
            data.diagnosticOverallStatus = lastDiag.overallStatus
        }

        // -- Security Scan --
        if let sec = securityResult {
            data.threatLevel = sec.overallThreatLevel.rawValue
            data.securityRating = sec.networkSafetyRating

            // DNS hijack/leak result
            switch sec.dnsLeakResult {
            case .notTested:
                data.dnsHijackResult = DNSHijackSummary(status: "not_tested", hijacked: false)
            case .clean:
                data.dnsHijackResult = DNSHijackSummary(status: "clean", hijacked: false, note: "No DNS leak detected")
            case .detected(let threat):
                data.dnsHijackResult = DNSHijackSummary(status: "detected", hijacked: true, note: threat.description)
            }

            // VPN leak from live status
            data.vpnLeakDetected = liveVPN.isActive && liveVPN.dnsLeakDetected

            // TLS issues from security scan
            switch sec.tlsFingerprintResult {
            case .notTested:
                break
            case .clean:
                break
            case .detected(let threat):
                data.tlsIssues = [threat.title + ": " + threat.description]
            }
        }

        // Merge TLS analysis results
        if !tlsResults.isEmpty {
            var sites: [String] = []
            var issues: [String] = data.tlsIssues ?? []
            for r in tlsResults {
                let rating = r.securityRating.rawValue
                sites.append("\(r.host) (\(r.tlsVersion.version), \(rating))")
                for issue in r.issues {
                    issues.append("\(r.host): \(issue.title) [\(issue.severity.rawValue)]")
                }
            }
            data.tlsAnalysisSites = sites
            if !issues.isEmpty { data.tlsIssues = issues }
        }

        // -- Connection Stability --
        if let metrics = stability.currentMetrics {
            data.uptimePercentage = metrics.uptimePercentage
            data.disconnectCount = metrics.disconnectCount
            data.latencySpikeCount = metrics.latencySpikeCount
        }
        let recentEvents = stability.events.suffix(15)
        if !recentEvents.isEmpty {
            data.recentStabilityEvents = recentEvents.map { event in
                "\(event.type): \(event.details)" + (event.latency.map { " (\(Int($0))ms)" } ?? "")
            }
        }

        // -- Device Discovery --
        if !devices.isEmpty {
            data.devicesFound = devices.count
            data.devicesConnectedNow = devices.filter { $0.isCurrentlyConnected }.count
            data.newDevices = devices.filter { $0.isNew }.count
            data.untrustedDevices = devices.filter { !$0.isTrusted }.count
        }

        // -- Port Scan --
        if !portResults.isEmpty {
            var ports: [String] = []
            for scan in portResults {
                for p in scan.openPorts {
                    ports.append("\(p.port) (\(p.service)) [\(p.risk.rawValue)]")
                }
            }
            data.openPorts = ports.isEmpty ? nil : ports
            data.portScanRiskLevel = portResults.first?.riskLevel.rawValue
        }

        // -- Speed History (last 5) --
        let lastFive = speedHistory.prefix(5)
        if !lastFive.isEmpty {
            let formatter = ISO8601DateFormatter()
            data.speedHistory = lastFive.map { entry in
                SpeedHistorySummary(
                    timestamp: formatter.string(from: entry.timestamp),
                    downloadMbps: entry.downloadSpeed,
                    uploadMbps: entry.uploadSpeed,
                    pingMs: entry.ping,
                    vpnActive: entry.vpnActive
                )
            }
        }

        return data
    }

    static func collectJSON() -> String {
        let data = collect()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let jsonData = try? encoder.encode(data),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{\"error\": \"Failed to serialize diagnostic data\"}"
    }

    private static func healthString(_ health: NetworkHealth) -> String {
        switch health {
        case .excellent: return "Excellent"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Chat Service

@MainActor
class AIChatService: ObservableObject {
    static let shared = AIChatService()

    @Published var isResponding = false
    @Published var lastError: String?
    @Published var currentSession: ChatSession?
    @Published var sessions: [ChatSession] = []

    private let sessionsKey = "ai_chat_sessions"

    private init() {
        loadSessions()
    }

    // MARK: - VPN-Aware System Prompt

    private let systemPrompt = """
    You are NetoSensei AI, an expert network diagnostics assistant embedded in an iOS app. You analyze real network diagnostic data collected from the user's device.

    Core Rules

    VPN-Aware Analysis (CRITICAL)
    Many users of this app are in China using proxy/VPN tools (Surge, Shadowrocket, Quantumult X, Clash, VLESS+Reality, V2Ray, Trojan, etc.) to access the global internet. You MUST interpret all findings through this lens when VPN is detected active:

    - DNS results showing 198.18.x.x, 198.19.x.x, or 100.100.x.x IPs are NOT hijacking. These are fake/synthetic IPs generated by local proxy apps to intercept and route DNS through the tunnel. This is NORMAL and EXPECTED. Never flag this as a security threat.
    - DNS "leak" results showing 198.18.x.x resolver IPs when proxy/VPN is active = NOT a real DNS leak. Proxy apps (Surge, Shadowrocket, Clash) handle DNS locally through synthetic IPs. This is MORE private than tunnel DNS because queries never leave the device unencrypted. Report this as "DNS handled locally by proxy (good)" not "DNS leak detected."
    - TLS certificate differences through a VPN/proxy are NOT "TLS tampering" or "MITM attacks" unless there is specific evidence of a malicious certificate from a completely unknown CA. Proxy apps use their own certificates for MITM debugging when the user enables it. Flag as info, not critical.
    - Country mismatch (device location=CN, IP location=US/JP/HK/SG/etc.) when VPN is active means THE VPN IS WORKING CORRECTLY. Present this as confirmation, not as "location exposure."
    - Latency context for VPN connections:
      - China → US/EU: 150-200ms is physically normal (speed of light in fiber across the Pacific). Do not call this "extremely slow" or "crippling."
      - China → HK/JP/SG/TW: 30-80ms is normal.
      - <150ms transpacific = good. 150-250ms = normal. >300ms = congestion or poor routing.
    - Jitter context: 20-50ms is moderate for international VPN, not "very high." Only flag >100ms sustained as concerning.
    - Netflix/streaming service timeouts through a VPN are geo-restriction blocks (the streaming service blocking the VPN IP), NOT connectivity failures. Label them as such.
    - If VPN is detected active, reframe ALL findings through that context. DNS tests, TLS tests, traceroute anomalies — interpret as "through VPN tunnel" first, "security threat" only if evidence specifically points to compromise beyond normal VPN behavior.

    What Qualifies as Actually Critical (use 🔴)

    - VPN leak detected (real IP exposed while VPN active)
    - Gateway unreachable (cannot reach router at all)
    - Complete DNS failure (cannot resolve any domain)
    - Packet loss >5% sustained
    - Open dangerous ports on gateway exposed to internet (telnet/23, SMB/445)
    - Genuine malicious certificate from unknown CA when VPN is NOT active

    What is Normal/Expected (do NOT flag as threats)

    - 198.18.x.x / 198.19.x.x DNS responses when proxy/VPN active (fake IPs for routing)
    - Country mismatch with VPN active (VPN working as intended)
    - TLS certificate differences through VPN tunnel
    - NEVPNManager "permission denied" (app doesn't have VPN entitlement — normal for diagnostic apps)
    - Netflix/streaming timeouts through VPN (geo-restriction, not connectivity)
    - 150-200ms latency on transpacific VPN routes

    Accuracy Rules

    - Only report findings present in the data. Do not speculate about threats not evidenced.
    - If a feature was not tested (marked "not_tested" or false in featuresTested), say you don't have that data. Do not guess.
    - If downloadMbps is 0 or null, the speed test failed or was skipped — say "speed test data unavailable" not "your download speed is 0 Mbps." Same for any field that is 0/null/empty — treat as missing data, not as a measurement of zero.
    - Distinguish: FACTS (from data) vs LIKELY EXPLANATIONS (with reasoning) vs RECOMMENDATIONS.
    - Never say "your connection is being intercepted" unless you have evidence beyond normal VPN/proxy behavior.

    Tone and Format

    - Direct, technically accurate. No unnecessary alarm.
    - Severity levels: ✅ Normal | ℹ️ Info | ⚠️ Moderate | 🔴 Critical
    - Only use 🔴 for genuine, evidence-backed security threats.
    - Structure: Security → Performance → Recommendations

    RESPONSE LENGTH: Keep your ENTIRE response under 400 words. Lead with a ONE SENTENCE verdict. Then 2-3 key findings (1-2 sentences each). Then 1-2 actionable recommendations with specific steps. Do NOT repeat data the user can see in the app — interpret and advise. If everything is fine, say so in 3-4 sentences total.
    """

    // MARK: - Send Message

    func sendMessage(
        _ message: String,
        conversationHistory: [ChatMessage],
        provider: AIProvider,
        preflightJSON: String? = nil
    ) async throws -> String {
        let taskID = BackgroundTaskManager.shared.beginTask(id: "aiChat", name: "AI Response")
        do {
            let response = try await performSendMessage(
                message,
                conversationHistory: conversationHistory,
                provider: provider,
                preflightJSON: preflightJSON
            )
            BackgroundTaskManager.shared.completeTask(taskID, result: "Response ready")
            return response
        } catch {
            BackgroundTaskManager.shared.completeTask(taskID, result: "Error: \(error.localizedDescription)")
            throw error
        }
    }

    private func performSendMessage(
        _ message: String,
        conversationHistory: [ChatMessage],
        provider: AIProvider,
        preflightJSON: String? = nil
    ) async throws -> String {
        guard let key = AIKeyManager.shared.getKey(for: provider) else {
            throw AIError.noAPIKey
        }

        isResponding = true
        lastError = nil
        defer { isResponding = false }

        // Prefer the preflight snapshot (fresh data, guaranteed complete) over
        // the legacy cached collector. Fallback keeps older callers working.
        let diagnosticJSON = preflightJSON ?? AIDataCollector.collectJSON()

        do {
            let response: String
            switch provider {
            case .openai, .deepseek, .groq:
                response = try await callOpenAICompatible(
                    url: provider.baseURL,
                    key: key,
                    model: AIKeyManager.shared.selectedModel,
                    message: message,
                    diagnosticJSON: diagnosticJSON,
                    history: conversationHistory
                )
            case .claude:
                response = try await callClaude(
                    key: key,
                    model: AIKeyManager.shared.selectedModel,
                    message: message,
                    diagnosticJSON: diagnosticJSON,
                    history: conversationHistory
                )
            case .gemini:
                response = try await callGemini(
                    key: key,
                    model: AIKeyManager.shared.selectedModel,
                    message: message,
                    diagnosticJSON: diagnosticJSON,
                    history: conversationHistory
                )
            }
            return response
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Build Diagnostic Context

    private func buildDiagnosticContext(_ diagnosticJSON: String) -> String {
        """
        Here is the current network diagnostic data from this device:

        <diagnostic_data>
        \(diagnosticJSON)
        </diagnostic_data>

        The "featuresTested" field shows which features have data. Only analyze features that have been tested.
        If VPN is detected active (vpnActive=true), interpret ALL other findings through that context first.
        Analyze this data and provide your assessment.
        """
    }

    // MARK: - OpenAI-Compatible (OpenAI, DeepSeek, Groq)

    private func callOpenAICompatible(
        url: String,
        key: String,
        model: String,
        message: String,
        diagnosticJSON: String,
        history: [ChatMessage]
    ) async throws -> String {
        guard let requestURL = URL(string: url) else { throw AIError.invalidURL }

        var messages: [[String: String]] = []

        // Single consolidated system message. Some OpenAI-compatible endpoints
        // (older DeepSeek, Groq) drop additional system messages — concatenating
        // matches what we already do for Claude.
        let systemContent = systemPrompt + "\n\n" + buildDiagnosticContext(diagnosticJSON)
        messages.append(["role": "system", "content": systemContent])

        // Conversation history
        for msg in history {
            if msg.role == "user" || msg.role == "assistant" {
                messages.append(["role": msg.role, "content": msg.content])
            }
        }

        // New user message
        messages.append(["role": "user", "content": message])

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": 800,
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkError("No HTTP response")
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(httpResponse.statusCode, errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let messageObj = firstChoice["message"] as? [String: Any],
              let content = messageObj["content"] as? String else {
            throw AIError.parseError("Could not parse response")
        }

        return content
    }

    // MARK: - Claude (Anthropic)

    private func callClaude(
        key: String,
        model: String,
        message: String,
        diagnosticJSON: String,
        history: [ChatMessage]
    ) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIError.invalidURL
        }

        // Build system content: prompt + diagnostic data
        let systemContent = systemPrompt + "\n\n" + buildDiagnosticContext(diagnosticJSON)

        // Build messages (Claude uses separate system field)
        var messages: [[String: String]] = []
        for msg in history {
            if msg.role == "user" || msg.role == "assistant" {
                messages.append(["role": msg.role, "content": msg.content])
            }
        }
        messages.append(["role": "user", "content": message])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 800,
            "temperature": 0.3,
            "system": systemContent,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkError("No HTTP response")
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(httpResponse.statusCode, errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIError.parseError("Could not parse Claude response")
        }

        return text
    }

    // MARK: - Gemini (Google)

    private func callGemini(
        key: String,
        model: String,
        message: String,
        diagnosticJSON: String,
        history: [ChatMessage]
    ) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)") else {
            throw AIError.invalidURL
        }

        // Build conversation parts
        var contents: [[String: Any]] = []

        // System context as first user/model exchange
        let systemText = systemPrompt + "\n\n" + buildDiagnosticContext(diagnosticJSON)
        contents.append([
            "role": "user",
            "parts": [["text": "System instructions: \(systemText)"]]
        ])
        contents.append([
            "role": "model",
            "parts": [["text": "Understood. I'm NetoSensei AI with VPN-aware analysis. I'll interpret all findings with proper context for proxy/VPN users, especially in China. Ready to analyze."]]
        ])

        // History
        for msg in history {
            let role = msg.role == "assistant" ? "model" : "user"
            contents.append(["role": role, "parts": [["text": msg.content]]])
        }

        // New message
        contents.append(["role": "user", "parts": [["text": message]]])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 800,
                "temperature": 0.3
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkError("No HTTP response")
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(httpResponse.statusCode, errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let contentObj = firstCandidate["content"] as? [String: Any],
              let parts = contentObj["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIError.parseError("Could not parse Gemini response")
        }

        return text
    }

    // MARK: - Session Management

    @discardableResult
    func createNewSession() -> ChatSession {
        let session = ChatSession()
        sessions.insert(session, at: 0)
        currentSession = session
        saveSessions()
        return session
    }

    func selectSession(_ session: ChatSession) {
        currentSession = session
    }

    func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        if currentSession?.id == session.id {
            currentSession = sessions.first
        }
        saveSessions()
    }

    func clearAllSessions() {
        sessions.removeAll()
        currentSession = nil
        saveSessions()
    }

    /// Mark the current session as having diagnostic context attached and persist.
    /// Used by the chat view after a successful preflight so the "diagnostics attached"
    /// banner renders correctly — including for restored sessions.
    func markDiagnosticContextAttached() {
        guard var session = currentSession else { return }
        guard session.hasDiagnosticContext == false else { return }
        session.hasDiagnosticContext = true
        updateSession(session)
    }

    /// Add a message to the current session and persist
    func addMessageToCurrentSession(_ message: ChatMessage) {
        guard var session = currentSession else { return }
        session.addMessage(message)
        updateSession(session)
    }

    /// Remove loading messages from current session
    func removeLoadingMessages() {
        guard var session = currentSession else { return }
        session.messages.removeAll { $0.isLoading }
        updateSession(session)
    }

    private func updateSession(_ session: ChatSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
        currentSession = session
        saveSessions()
    }

    // MARK: - Persistence

    private func saveSessions() {
        // Keep only last 50 sessions to avoid excessive storage
        let toSave = Array(sessions.prefix(50))
        if let encoded = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(encoded, forKey: sessionsKey)
        }
    }

    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
            sessions = decoded
            currentSession = sessions.first
        }
    }
}

// MARK: - Error Types

enum AIError: LocalizedError {
    case noAPIKey
    case invalidURL
    case networkError(String)
    case apiError(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured. Go to AI Settings to add one."
        case .invalidURL: return "Invalid API endpoint URL."
        case .networkError(let msg): return "Network error: \(msg)"
        case .apiError(let code, let body):
            if code == 401 { return "Invalid API key. Check your key in AI Settings." }
            if code == 429 { return "Rate limited. Wait a moment and try again." }
            if code == 402 || body.contains("insufficient") { return "Insufficient API credits. Check your billing." }
            return "API error (HTTP \(code)): \(String(body.prefix(150)))"
        case .parseError(let msg): return "Failed to parse AI response: \(msg)"
        }
    }
}
