//
//  SmartVPNDetector.swift
//  NetoSensei
//
//  ARCHITECTURE (5-Layer Apple-Compliant Detection):
//
//  LAYER 1: NEVPNManager (AUTHORITATIVE)
//    - Checks iOS system VPN status via NEVPNManager + NETunnelProviderManager
//    - Detects VPN profiles AND app-based VPNs (Surge, Shadowrocket, Clash)
//    - 100% confidence when available
//
//  LAYER 2: VPN Inference (NOT AUTHORITATIVE)
//    - ISP/ASN classification (datacenter = VPN, residential = not VPN)
//    - Geolocation mismatch (IP country != device locale)
//    - China connectivity test (can reach Google = likely has VPN/proxy)
//    - Shown as "inferred" with confidence percentage
//
//  LAYER 3: Secondary signals (low weight)
//    - DNS configuration, VPN ports, network interfaces (ipsec/ppp only)
//
//  IMPORTANT: utun interfaces are NOT used as VPN evidence
//    - iOS creates utun for iCloud Private Relay, Mail Privacy Protection
//

import Foundation
import Network
import NetworkExtension

import SystemConfiguration.CaptiveNetwork

@MainActor
class SmartVPNDetector: ObservableObject {
    static let shared = SmartVPNDetector()

    @Published var detectionResult: VPNDetectionResult?
    @Published var isDetecting = false

    // Cache control
    // ISSUE 1 FIX: Increased from 5s → 30s to reduce redundant detection cycles
    private var lastDetectionTime: Date?
    private static let detectionCooldown: TimeInterval = 30.0

    // ISSUE 3 FIX: Cache NEVPNManager failure permanently — never retry if permission denied
    private var nevpnChecked = false
    private var nevpnResult: (authoritative: Bool, vpnActive: Bool, detail: String)?

    // Debug info for debug panel
    @Published var lastDebugInfo: DebugInfo?

    // MARK: - Detection Status

    enum VPNDetectionStatus: String {
        case active = "VPN Active"
        case possiblyActive = "Possibly VPN"
        case notActive = "No VPN"
    }

    // MARK: - Detection Result

    struct VPNDetectionResult {
        let isVPNActive: Bool
        let detectionStatus: VPNDetectionStatus
        let vpnState: VPNState  // 6-state machine output
        let detectionMethod: String
        let publicIP: String?
        let publicCountry: String?
        let publicCity: String?
        let publicASN: String?
        let publicISP: String?
        let expectedCountry: String?
        let confidence: Double  // 0.0 to 1.0
        let methodResults: [MethodResult]
        let vpnProtocol: String?
        let ipType: String?
        let displayLabel: String?
        let isLikelyInChina: Bool  // User's physical location, not IP location
        let ipVerified: Bool  // True if 2+ IP sources agreed
        let isAuthoritative: Bool  // true = NEVPNManager confirmed, false = ISP/inference
        let inferenceReasons: [String]  // Human-readable reasons for VPN inference
        let timestamp: Date

        struct MethodResult {
            let method: String
            let detected: Bool
            let detail: String
            /// FIX (Sec Issue 5): Some "checks" are not pass/fail — they're
            /// "not available on iOS" (e.g. system DNS enumeration requires
            /// an entitlement we don't have). When `isInformational == true`
            /// the row should render with an info ⓘ glyph, NOT the gray X
            /// that previously made platform limitations look like failures.
            /// Defaulted to false so existing call-sites keep compiling.
            var isInformational: Bool = false
        }
    }

    // MARK: - Debug Info

    struct DebugInfo {
        let interfaces: [(name: String, ip: String, family: String)]
        let dnsServers: [String]
        let methodResults: [VPNDetectionResult.MethodResult]
        let rawSSIDInfo: String
        let pathStatus: String
        let detectionReasoning: String
        let timestamp: Date
    }

    // MARK: - ISP Classification Lists

    private static let datacenterKeywords: [String] = [
        "zenlayer", "aws", "amazon", "google cloud", "gcp", "microsoft azure", "azure",
        "digitalocean", "vultr", "linode", "akamai", "ovh", "hetzner", "cloudflare",
        "fastly", "oracle cloud", "ibm cloud", "alibaba cloud", "aliyun",
        "tencent cloud", "hosting", "data center", "datacenter", "server", "vps",
        "cloud computing", "colocation", "colo", "rackspace", "leaseweb",
        "choopa", "m247", "psychz", "quadranet", "multacom", "colocrossing",
        "sharktech", "incero", "cogent", "he.net", "hurricane electric"
    ]

    private static let vpnProviderKeywords: [String] = [
        "vpn", "private internet", "express", "nord", "surfshark", "proton",
        "mullvad", "wireguard", "shadowsocks", "v2ray", "trojan", "clash", "surge",
        "cyberghost", "pia", "ipvanish", "strongvpn", "tunnelbear", "windscribe",
        "hide.me", "hotspot shield", "astrill", "purevpn"
    ]

    private static let residentialISPKeywords: [String] = [
        // China
        "china mobile", "china telecom", "china unicom", "chinanet",
        "cmcc", "中国移动", "中国电信", "中国联通",
        // US
        "comcast", "at&t", "verizon", "spectrum", "cox", "charter",
        "t-mobile", "sprint", "xfinity", "centurylink", "frontier",
        // Europe
        "british telecom", "bt ", "vodafone", "orange", "deutsche telekom",
        "telefonica", "swisscom", "kpn", "telia", "telenor",
        // Asia
        "ntt", "softbank", "kddi", "sk telecom", "kt ", "lg u+",
        "singtel", "starhub", "true ", "ais ", "globe telecom", "pldt",
        // General
        "broadband", "cable", "fiber", "fibre", "dsl", "residential",
        "communications group", "communications corporation"
    ]

    private static let residentialIPv6Prefixes: [String] = [
        "2409:",   // China Mobile
        "240e:",   // China Telecom
        "2408:",   // China Unicom
        "2001:ee0",
        "2600:",   // Comcast, US ISPs
        "2601:",   // Comcast
        "2602:",
        "2603:",
        "2607:",
        "2a02:",   // European ISPs
        "2a01:",
        "2a00:",
    ]

    private init() {}

    // MARK: - NEVPNManager Check

    /// Check iOS system VPN status via NEVPNManager.
    /// IMPORTANT: NEVPNManager is only AUTHORITATIVE when it says VPN IS connected.
    /// When it says "disconnected", it only means no iOS VPN profile is active —
    /// it CANNOT detect router-level VPNs, corporate network VPNs, or proxy servers.
    /// So "disconnected" must NOT block ISP/geolocation detection.
    private func checkNEVPNManager() async -> (authoritative: Bool, vpnActive: Bool, detail: String) {
        // ISSUE 3 FIX: If we already know NEVPNManager is unavailable (permission denied),
        // return the cached result immediately — never call loadFromPreferences again.
        if nevpnChecked, let cached = nevpnResult {
            // Only re-check if previous result was "available" (entitlement present)
            // to detect VPN connect/disconnect. If permission denied, skip forever.
            if cached.detail.contains("unavailable") || cached.detail.contains("permission denied") {
                return cached
            }
        }

        let manager = NEVPNManager.shared()

        // loadFromPreferences requires the Personal VPN entitlement.
        // If entitlement is missing, this throws and we fall back to ISP detection.
        do {
            try await manager.loadFromPreferences()
        } catch {
            let result = (false, false, "NEVPNManager unavailable: \(error.localizedDescription)")
            // ISSUE 3 FIX: Cache permanently — only log once
            if !nevpnChecked {
                print("[VPN] NEVPNManager not available (no entitlement) — using heuristic detection only")
            }
            nevpnChecked = true
            nevpnResult = result
            return result
        }

        nevpnChecked = true

        // System VPN profile check
        if manager.connection.status == .connected {
            let result = (true, true, "System VPN connected")
            nevpnResult = result
            return result
        }

        // Check app-based VPN profiles (Surge, Shadowrocket, Clash, etc.)
        if let tunnelManagers = try? await NETunnelProviderManager.loadAllFromPreferences() {
            for tm in tunnelManagers {
                if tm.connection.status == .connected {
                    let name = tm.localizedDescription ?? "App VPN"
                    let result = (true, true, "\(name) connected")
                    nevpnResult = result
                    return result
                }
            }
        }

        // CRITICAL FIX: NEVPNManager says "no iOS VPN profile active" — but this does NOT
        // rule out router-level VPNs, corporate VPNs, or proxy servers.
        // Return authoritative=FALSE so ISP/geolocation detection can still detect these.
        let systemStatus = manager.connection.status
        let result: (Bool, Bool, String)
        if systemStatus == .disconnected || systemStatus == .invalid {
            result = (false, false, "No iOS VPN profile active (router/network VPN not checked)")
        } else {
            result = (false, false, "VPN transitional (status: \(systemStatus.rawValue))")
        }
        nevpnResult = result
        return result
    }

    // MARK: - Main Detection Entry Point

    func detectVPN(expectedCountry: String? = nil, forceRefresh: Bool = false) async -> VPNDetectionResult {
        // Cache check
        if !forceRefresh,
           let lastTime = lastDetectionTime,
           Date().timeIntervalSince(lastTime) < Self.detectionCooldown,
           let cached = detectionResult {
            return cached
        }

        guard !isDetecting else {
            return detectionResult ?? makeEmptyResult(expectedCountry: expectedCountry)
        }

        isDetecting = true
        lastDetectionTime = Date()

        // ===== STEP 0: NEVPNManager (AUTHORITATIVE) =====
        let (neAuthoritative, neVPNActive, neDetail) = await checkNEVPNManager()

        // ===== STEP 1: Get verified public IP from 3 sources =====
        let (verifiedIP, allIPs, ipVerified) = await getVerifiedPublicIP()

        // ===== STEP 2: Get detailed IP info (ISP, country, city) =====
        let ipInfo = await getDetailedIPInfo(forIP: verifiedIP)

        // ===== STEP 3: Run detection methods =====
        // Method A: ISP/ASN classification (PRIMARY)
        let ispResult = classifyISP(ipInfo: ipInfo)

        // Method B: Geolocation mismatch
        let expected = expectedCountry ?? getExpectedCountry()
        let geoResult = checkGeolocationMismatch(ipInfo: ipInfo, expectedCountry: expected)

        // Method C: DNS configuration (private DNS = VPN evidence)
        let dnsResult = detectByDNS()

        // Method D: Network interfaces (ipsec/ppp/tap only, NOT utun)
        let ifaceResult = detectByInterface()

        // Method D2: IPv6 residential check (Rule 2: IPv6 from ISP ≠ VPN)
        let ipv6Result = checkIPv6Residential(ipInfo: ipInfo)

        // Method E: VPN port detection
        let portResult = detectByVPNPorts()

        // Method F: China connectivity test (can reach Google = VPN inference)
        let connectivityResult = await checkChinaConnectivity()

        // NEVPNManager result (for debug display)
        let neMethodResult = VPNDetectionResult.MethodResult(
            method: "NEVPNManager",
            detected: neVPNActive,
            detail: neDetail
        )

        let allResults = [neMethodResult, ispResult, geoResult, connectivityResult, dnsResult, ifaceResult, ipv6Result, portResult]

        // ===== STEP 4: Determine VPN status =====
        // NEVPNManager is AUTHORITATIVE only when it confirms VPN IS connected.
        // When it says "disconnected", ISP/geolocation detection still runs
        // to catch router-level VPNs, corporate VPNs, and proxy servers.
        let isResidential = isKnownResidentialISP(isp: ipInfo?.isp)
        let isDatacenter = isKnownVPNProvider(isp: ipInfo?.isp)

        let confidence: Double
        let detectionStatus: VPNDetectionStatus
        let isVPNActive: Bool
        let isAuthoritative: Bool
        var inferenceReasons: [String] = []

        if neAuthoritative && neVPNActive {
            // NEVPNManager confirmed VPN IS connected — authoritative YES
            confidence = 1.0
            detectionStatus = .active
            isVPNActive = true
            isAuthoritative = true
        } else if isDatacenter {
            // ISP is a datacenter/VPN provider (e.g. Zenlayer, AWS, NordVPN)
            // This catches router-level VPNs that NEVPNManager can't see
            confidence = 0.95
            detectionStatus = .active
            isVPNActive = true
            isAuthoritative = false
            inferenceReasons.append("IP belongs to datacenter/VPN provider: \(ipInfo?.isp ?? "unknown")")
        } else if isResidential {
            // Inference: Residential ISP = NOT VPN
            confidence = 0.0
            detectionStatus = .notActive
            isVPNActive = false
            isAuthoritative = false
            inferenceReasons.append("IP belongs to residential ISP: \(ipInfo?.isp ?? "unknown")")
        } else if geoResult.detected && connectivityResult.detected {
            // Inference: Country mismatch + can reach Google from China = strong evidence
            confidence = 0.90
            detectionStatus = .active
            isVPNActive = true
            isAuthoritative = false
            inferenceReasons.append("Country mismatch: IP=\(ipInfo?.countryCode ?? "?"), device=\(expected)")
            inferenceReasons.append("Can reach Google from China")
        } else if geoResult.detected {
            // Inference: Country mismatch + unknown ISP = likely VPN
            confidence = 0.85
            detectionStatus = .active
            isVPNActive = true
            isAuthoritative = false
            inferenceReasons.append("Country mismatch: IP=\(ipInfo?.countryCode ?? "?"), device=\(expected)")
        } else if connectivityResult.detected {
            // Inference: Can reach Google from China locale = likely VPN/proxy
            confidence = 0.70
            detectionStatus = .possiblyActive
            isVPNActive = false  // Conservative: don't declare active on connectivity alone
            isAuthoritative = false
            inferenceReasons.append("Can reach Google from China — likely VPN/proxy")
        } else {
            // Inference: Unknown ISP, same country - check secondary signals
            isAuthoritative = false
            let secondaryPositive = [dnsResult, ifaceResult, portResult].filter { $0.detected }.count
            if secondaryPositive >= 2 {
                confidence = 0.7
                detectionStatus = .possiblyActive
                isVPNActive = false
                for r in [dnsResult, ifaceResult, portResult] where r.detected {
                    inferenceReasons.append(r.detail)
                }
            } else if secondaryPositive == 1 {
                confidence = 0.3
                detectionStatus = .notActive
                isVPNActive = false
            } else {
                confidence = 0.0
                detectionStatus = .notActive
                isVPNActive = false
            }
        }

        // ===== STEP 4b: Compute VPN State Machine =====
        let vpnState: VPNState
        if neAuthoritative && neVPNActive {
            // NEVPNManager confirmed iOS VPN profile is connected
            vpnState = .on
        } else if neDetail.contains("transitional") {
            vpnState = .connecting
        } else if isDatacenter {
            // IP belongs to datacenter → router/network VPN detected
            vpnState = .probablyOn
        } else if geoResult.detected {
            vpnState = .probablyOn
        } else if connectivityResult.detected {
            vpnState = .probablyOn
        } else if isResidential {
            // Residential ISP + NEVPNManager says no iOS profile → likely no VPN
            vpnState = .probablyOff
        } else {
            vpnState = .unknown
        }

        // ===== STEP 5: Determine China mode =====
        let ipCountry = (ipInfo?.countryCode ?? "").uppercased()
        let deviceLocale = Locale.current.identifier
        let isLikelyInChina: Bool
        if !isVPNActive {
            // No VPN → IP country = physical location
            isLikelyInChina = ipCountry == "CN"
        } else {
            // VPN active → use device locale as physical location proxy
            isLikelyInChina = deviceLocale.hasPrefix("zh_CN") || deviceLocale.hasPrefix("zh-CN")
        }

        // Determine VPN protocol
        let vpnProtocol = isVPNActive ? detectVPNProtocol() : nil
        let ipType = classifyIPType(isp: ipInfo?.isp)
        let displayLabel = buildDisplayLabel(
            vpnProtocol: vpnProtocol, ipType: ipType, isp: ipInfo?.isp,
            isActive: isVPNActive, status: detectionStatus,
            authoritative: isAuthoritative
        )

        let primaryMethod: String
        if neAuthoritative { primaryMethod = "NEVPNManager" }
        else if isDatacenter { primaryMethod = "ISP Classification" }
        else if geoResult.detected { primaryMethod = "Geolocation" }
        else if let first = allResults.first(where: { $0.detected }) { primaryMethod = first.method }
        else { primaryMethod = "none" }

        // Build reasoning for debug
        var reasoning = "=== VPN Detection Reasoning ===\n"
        reasoning += "NEVPNManager: \(neDetail) (authoritative: \(neAuthoritative))\n"
        reasoning += "IP Sources: \(allIPs.joined(separator: ", "))\n"
        reasoning += "Verified IP: \(verifiedIP ?? "none") (agreed: \(ipVerified))\n"
        reasoning += "ISP: \(ipInfo?.isp ?? "unknown")\n"
        reasoning += "  → Residential: \(isResidential)\n"
        reasoning += "  → Datacenter: \(isDatacenter)\n"
        reasoning += "Country: IP=\(ipCountry), Expected=\(expected)\n"
        reasoning += "  → Mismatch: \(geoResult.detected)\n"
        for r in allResults {
            reasoning += "[\(r.detected ? "YES" : " NO")] \(r.method): \(r.detail)\n"
        }
        reasoning += "Confidence: \(String(format: "%.0f%%", confidence * 100))\n"
        reasoning += "Status: \(detectionStatus.rawValue)\n"
        reasoning += "Authoritative: \(isAuthoritative)\n"
        if !inferenceReasons.isEmpty {
            reasoning += "Inference: \(inferenceReasons.joined(separator: "; "))\n"
        }
        reasoning += "China Mode: \(isLikelyInChina)"

        let result = VPNDetectionResult(
            isVPNActive: isVPNActive,
            detectionStatus: detectionStatus,
            vpnState: vpnState,
            detectionMethod: primaryMethod,
            publicIP: verifiedIP ?? ipInfo?.ip,
            publicCountry: ipInfo?.country,
            publicCity: ipInfo?.city,
            publicASN: ipInfo?.asn,
            publicISP: ipInfo?.isp,
            expectedCountry: expected,
            confidence: confidence,
            methodResults: allResults,
            vpnProtocol: vpnProtocol,
            ipType: ipType,
            displayLabel: displayLabel,
            isLikelyInChina: isLikelyInChina,
            ipVerified: ipVerified,
            isAuthoritative: isAuthoritative,
            inferenceReasons: inferenceReasons,
            timestamp: Date()
        )

        // Build debug info
        lastDebugInfo = DebugInfo(
            interfaces: getAllInterfaces(),
            dnsServers: getSystemDNSServers(),
            methodResults: allResults,
            rawSSIDInfo: getRawSSIDInfo(),
            pathStatus: getNWPathDescription(),
            detectionReasoning: reasoning,
            timestamp: Date()
        )

        // ISSUE 1 FIX: Only log when result changes, not every cycle
        let previousStatus = detectionResult?.detectionStatus
        let previousIP = detectionResult?.publicIP
        if detectionStatus != previousStatus || verifiedIP != previousIP {
            print("[VPN Detection] \(reasoning)")
        } else {
            print("[VPN] No change (status=\(detectionStatus.rawValue), confidence=\(String(format: "%.0f%%", confidence * 100)))")
        }

        detectionResult = result
        isDetecting = false

        return result
    }

    // MARK: - Step 1: Cross-Verified Public IP

    /// Get public IP from 3 independent sources, return consensus IP
    private func getVerifiedPublicIP() async -> (ip: String?, allIPs: [String], verified: Bool) {
        async let ip1 = fetchPlainIP(from: "https://api.ipify.org")
        async let ip2 = fetchPlainIP(from: "https://ipinfo.io/ip")
        async let ip3 = fetchIPFromJSON(from: "https://ip-api.com/json/?fields=query", key: "query")

        let results = await [ip1, ip2, ip3]
        let validIPs = results.compactMap { $0 }

        guard !validIPs.isEmpty else {
            return (nil, [], false)
        }

        // Find consensus: IP that appears 2+ times
        var counts: [String: Int] = [:]
        for ip in validIPs {
            counts[ip, default: 0] += 1
        }

        if let (consensusIP, count) = counts.max(by: { $0.value < $1.value }), count >= 2 {
            return (consensusIP, validIPs, true)
        }

        // No consensus — return first available but mark as unverified
        return (validIPs.first, validIPs, false)
    }

    /// Fetch IP as plain text from a service
    private func fetchPlainIP(from urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            // Validate it looks like an IP
            guard let ip = ip, ip.contains(".") || ip.contains(":"), ip.count <= 45 else { return nil }
            return ip
        } catch {
            return nil
        }
    }

    /// Fetch IP from a JSON endpoint
    private func fetchIPFromJSON(from urlString: String, key: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return json[key] as? String
        } catch {
            return nil
        }
    }

    // MARK: - Step 2: Detailed IP Info

    private struct PublicIPInfo {
        let ip: String
        let country: String?
        let countryCode: String?
        let city: String?
        let isp: String?
        let asn: String?
    }

    /// Get detailed IP info (ISP, country, city) from enrichment services
    private func getDetailedIPInfo(forIP verifiedIP: String?) async -> PublicIPInfo? {
        // Try ip-api.com first (best ISP data, free, no key needed)
        let services = [
            "https://ip-api.com/json/?fields=status,country,countryCode,city,isp,org,as,query",
            "https://ipwho.is/",
            "https://ipinfo.io/json"
        ]

        for serviceURL in services {
            if let info = await tryGetIPInfo(from: serviceURL) {
                // If we have a verified IP, make sure this service's IP matches
                if let verified = verifiedIP, info.ip != verified {
                    print("[VPN] IP mismatch: service=\(info.ip) vs verified=\(verified), using verified IP")
                    return PublicIPInfo(ip: verified, country: info.country, countryCode: info.countryCode,
                                       city: info.city, isp: info.isp, asn: info.asn)
                }
                return info
            }
        }
        return nil
    }

    private func tryGetIPInfo(from urlString: String) async -> PublicIPInfo? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let ip = json["ip"] as? String ?? json["query"] as? String
            guard let ipAddress = ip else { return nil }

            return PublicIPInfo(
                ip: ipAddress,
                country: json["country"] as? String ?? json["country_name"] as? String,
                countryCode: json["country_code"] as? String ?? json["countryCode"] as? String,
                city: json["city"] as? String,
                isp: json["isp"] as? String ?? json["org"] as? String,
                asn: json["asn"] as? String ?? json["as"] as? String
            )
        } catch {
            return nil
        }
    }

    // MARK: - Method A: ISP/ASN Classification (PRIMARY)

    private func classifyISP(ipInfo: PublicIPInfo?) -> VPNDetectionResult.MethodResult {
        guard let info = ipInfo, let isp = info.isp else {
            return VPNDetectionResult.MethodResult(
                method: "ISP Classification",
                detected: false,
                detail: "Could not determine ISP"
            )
        }

        let isResidential = isKnownResidentialISP(isp: isp)
        let isDatacenter = isKnownVPNProvider(isp: isp)

        if isResidential {
            return VPNDetectionResult.MethodResult(
                method: "ISP Classification",
                detected: false,
                detail: "Residential ISP: \(isp) — NOT VPN"
            )
        } else if isDatacenter {
            return VPNDetectionResult.MethodResult(
                method: "ISP Classification",
                detected: true,
                detail: "Datacenter/VPN ISP: \(isp)"
            )
        } else {
            return VPNDetectionResult.MethodResult(
                method: "ISP Classification",
                detected: false,
                detail: "Unknown ISP type: \(isp)"
            )
        }
    }

    // MARK: - Method B: Geolocation Mismatch

    private func checkGeolocationMismatch(ipInfo: PublicIPInfo?, expectedCountry: String) -> VPNDetectionResult.MethodResult {
        guard let info = ipInfo else {
            return VPNDetectionResult.MethodResult(
                method: "Geolocation", detected: false,
                detail: "Could not fetch IP info"
            )
        }

        let countryCode = (info.countryCode ?? "").uppercased()
        let expected = expectedCountry.uppercased()
        let isResidential = isKnownResidentialISP(isp: info.isp)

        // Same country or same region group = NOT VPN
        if countryCode.isEmpty || expected.isEmpty || countryCode == expected || countriesInSameGroup(countryCode, expected) {
            return VPNDetectionResult.MethodResult(
                method: "Geolocation", detected: false,
                detail: "IP country \(countryCode) matches expected \(expected) (or same region)"
            )
        }

        // Country mismatch but residential ISP = probably traveling, not VPN
        if isResidential {
            return VPNDetectionResult.MethodResult(
                method: "Geolocation", detected: false,
                detail: "Country mismatch (\(countryCode) vs \(expected)) but residential ISP — likely traveling"
            )
        }

        // Country mismatch + non-residential = VPN evidence
        return VPNDetectionResult.MethodResult(
            method: "Geolocation", detected: true,
            detail: "Country mismatch: IP=\(countryCode), device=\(expected), ISP=\(info.isp ?? "unknown")"
        )
    }

    // MARK: - Method C: DNS Configuration

    private func detectByDNS() -> VPNDetectionResult.MethodResult {
        let dnsServers = getSystemDNSServers()

        let privateDNS = dnsServers.filter { server in
            server.hasPrefix("10.") ||
            server.hasPrefix("172.16.") || server.hasPrefix("172.17.") ||
            server.hasPrefix("172.18.") || server.hasPrefix("172.19.") ||
            server.hasPrefix("172.2") || server.hasPrefix("172.3") ||
            server.hasPrefix("100.64.") ||
            server.hasPrefix("fd") || server.hasPrefix("fc")
        }

        if !privateDNS.isEmpty {
            // Genuine positive — VPN DNS detected.
            return VPNDetectionResult.MethodResult(
                method: "DNS",
                detected: true,
                detail: "VPN DNS detected: \(privateDNS.joined(separator: ", "))"
            )
        }

        // FIX (Sec Issue 5): When dnsServers is empty, that's iOS not exposing
        // the system resolver list to third-party apps — a platform limitation,
        // NOT a failed VPN check. Mark informational so the UI renders ⓘ
        // instead of the gray X that read as failure.
        if dnsServers.isEmpty {
            return VPNDetectionResult.MethodResult(
                method: "DNS",
                detected: false,
                detail: "DNS server enumeration not available on iOS (platform limitation). DNS resolution working — see WiFi Details for latency.",
                isInformational: true
            )
        }

        // DNS servers visible but none look private — report them honestly.
        return VPNDetectionResult.MethodResult(
            method: "DNS",
            detected: false,
            detail: "DNS servers: \(dnsServers.joined(separator: ", "))"
        )
    }

    // MARK: - Method D: Network Interface Detection
    // utun interfaces are COMPLETELY IGNORED — iOS uses them for system services
    // Only ipsec, ppp, tap, tun (non-utun) count

    private func detectByInterface() -> VPNDetectionResult.MethodResult {
        let vpnInterfaces = getVPNInterfaces()
        let detected = !vpnInterfaces.isEmpty

        let allUtun = getAllUtunInterfaces()
        var detail: String
        if detected {
            detail = "VPN interfaces: \(vpnInterfaces.joined(separator: ", "))"
        } else if !allUtun.isEmpty {
            detail = "utun found (system use, IGNORED): \(allUtun.joined(separator: ", "))"
        } else {
            detail = "No VPN interfaces"
        }

        return VPNDetectionResult.MethodResult(method: "Interface", detected: detected, detail: detail)
    }

    /// Only non-utun VPN interfaces count: ipsec, ppp, tap, tun (not utun)
    private func getVPNInterfaces() -> [String] {
        var vpnNames: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee,
                  let addr = interface.ifa_addr else { continue }

            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            let name = String(cString: interface.ifa_name)

            // SKIP utun entirely — iOS uses these for system services
            if name.hasPrefix("utun") { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            guard !ip.isEmpty && ip != "0.0.0.0" && ip != "::" else { continue }

            // Only definitive VPN interfaces
            let vpnPrefixes = ["ipsec", "ppp", "tap"]
            if vpnPrefixes.contains(where: { name.hasPrefix($0) }) {
                if !vpnNames.contains(where: { $0.hasPrefix(name) }) {
                    vpnNames.append("\(name) (\(ip))")
                }
            }
            // tun (NOT utun) — OpenVPN
            if name.hasPrefix("tun") && !name.hasPrefix("utun") {
                if !vpnNames.contains(where: { $0.hasPrefix(name) }) {
                    vpnNames.append("\(name) (\(ip))")
                }
            }
        }
        return vpnNames
    }

    /// Get all utun interfaces for debug display
    private func getAllUtunInterfaces() -> [String] {
        var utunNames: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee,
                  let addr = interface.ifa_addr else { continue }

            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("utun") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: hostname)
                if !ip.isEmpty && ip != "::" {
                    let familyStr = family == UInt8(AF_INET) ? "IPv4" : "IPv6"
                    let entry = "\(name)=\(ip) (\(familyStr))"
                    if !utunNames.contains(entry) { utunNames.append(entry) }
                }
            }
        }
        return utunNames
    }

    // MARK: - Method D2: IPv6 Residential Check (Rule 2)
    // If local IPv6 address matches a known residential ISP prefix,
    // this is "Native ISP IPv6" — NOT evidence of VPN.

    private func checkIPv6Residential(ipInfo: PublicIPInfo?) -> VPNDetectionResult.MethodResult {
        // Get local IPv6 addresses from network interfaces
        let localIPv6Addresses = getLocalIPv6Addresses()

        guard !localIPv6Addresses.isEmpty else {
            return VPNDetectionResult.MethodResult(
                method: "IPv6 Check",
                detected: false,
                detail: "No IPv6 addresses found"
            )
        }

        // Check if any local IPv6 matches a known residential ISP prefix
        for ipv6 in localIPv6Addresses {
            let lower = ipv6.lowercased()
            for prefix in Self.residentialIPv6Prefixes {
                if lower.hasPrefix(prefix.lowercased()) {
                    // IPv6 from residential ISP — this is NOT VPN evidence
                    return VPNDetectionResult.MethodResult(
                        method: "IPv6 Check",
                        detected: false,
                        detail: "Native ISP IPv6 present (\(ipv6.prefix(12))...) — not VPN"
                    )
                }
            }
        }

        // IPv6 present but not matching known residential prefixes
        return VPNDetectionResult.MethodResult(
            method: "IPv6 Check",
            detected: false,
            detail: "IPv6 present (\(localIPv6Addresses.count) addr) — prefix not matched to residential ISP"
        )
    }

    /// Get all global-scope IPv6 addresses from local interfaces (skip link-local fe80:)
    nonisolated private func getLocalIPv6Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee,
                  let addr = interface.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET6) else { continue }

            let name = String(cString: interface.ifa_name)
            // Only check non-VPN interfaces (en0, en1, pdp_ip, etc.)
            guard !name.hasPrefix("utun") && !name.hasPrefix("ipsec") &&
                  !name.hasPrefix("ppp") && !name.hasPrefix("tap") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: hostname)
                // Skip link-local (fe80:) and loopback (::1)
                if !ip.hasPrefix("fe80:") && ip != "::1" && !ip.isEmpty {
                    addresses.append(ip)
                }
            }
        }
        return addresses
    }

    // MARK: - Method F: China Connectivity Test (VPN Inference)
    // If device locale is Chinese and Google is reachable, likely has VPN/proxy

    private func checkChinaConnectivity() async -> VPNDetectionResult.MethodResult {
        let deviceLocale = Locale.current.identifier
        let isChineseLocale = deviceLocale.hasPrefix("zh_CN") || deviceLocale.hasPrefix("zh-CN")
            || deviceLocale.contains("_CN")

        guard isChineseLocale else {
            // FIX (Sec Issue 5): Mark as informational so the UI uses ⓘ, not
            // the gray X that read as failure for a not-applicable check.
            return VPNDetectionResult.MethodResult(
                method: "Connectivity",
                detected: false,
                detail: "Not in China locale — skipped",
                isInformational: true
            )
        }

        // Can we reach Google? (blocked in China without VPN/proxy)
        let canReachGoogle = await checkURLReachable("https://www.google.com/generate_204", timeout: 3.0)

        if canReachGoogle {
            return VPNDetectionResult.MethodResult(
                method: "Connectivity",
                detected: true,
                detail: "Can reach Google from China — likely VPN/proxy active"
            )
        }

        return VPNDetectionResult.MethodResult(
            method: "Connectivity",
            detected: false,
            detail: "Cannot reach Google from China locale (normal without VPN)"
        )
    }

    private func checkURLReachable(_ urlString: String, timeout: TimeInterval) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode != nil
        } catch {
            return false
        }
    }

    // MARK: - Method E: VPN Port Detection

    private func detectByVPNPorts() -> VPNDetectionResult.MethodResult {
        let vpnPorts: [(port: UInt16, proto: String)] = [
            (1194, "OpenVPN"), (51820, "WireGuard"),
            (500, "IKEv2/IPSec"), (4500, "IKEv2 NAT-T"),
            (1701, "L2TP"), (1723, "PPTP"), (8388, "Shadowsocks"),
        ]

        var detectedPorts: [String] = []
        for (port, proto) in vpnPorts {
            if isPortInUse(port: port) {
                detectedPorts.append("\(proto) (:\(port))")
            }
        }

        let detected = !detectedPorts.isEmpty
        let detail = detected
            ? "Active VPN ports: \(detectedPorts.joined(separator: ", "))"
            : "No VPN ports active"

        return VPNDetectionResult.MethodResult(method: "VPN Ports", detected: detected, detail: detail)
    }

    nonisolated private func isPortInUse(port: UInt16) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bindResult != 0 && errno == EADDRINUSE
    }

    // MARK: - VPN Protocol Detection

    private func detectVPNProtocol() -> String? {
        if isPortInUse(port: 51820) { return "WireGuard" }
        if isPortInUse(port: 500) || isPortInUse(port: 4500) { return "IKEv2" }
        if isPortInUse(port: 1194) { return "OpenVPN" }
        if isPortInUse(port: 1701) { return "L2TP" }
        if isPortInUse(port: 8388) { return "Shadowsocks" }

        let vpnInterfaces = getVPNInterfaces()
        for iface in vpnInterfaces {
            if iface.hasPrefix("ipsec") { return "IPSec" }
            if iface.hasPrefix("ppp") { return "L2TP/PPTP" }
            if iface.hasPrefix("tap") { return "OpenVPN (TAP)" }
            if iface.hasPrefix("tun") && !iface.hasPrefix("utun") { return "OpenVPN (TUN)" }
        }
        return "VPN"
    }

    // MARK: - IP Type Classification

    private func classifyIPType(isp: String?) -> String? {
        guard let isp = isp else { return nil }
        let ispLower = isp.lowercased()

        for keyword in Self.datacenterKeywords + Self.vpnProviderKeywords {
            if ispLower.contains(keyword) { return "Datacenter" }
        }
        return "Residential"
    }

    // MARK: - Display Label

    private func buildDisplayLabel(vpnProtocol: String?, ipType: String?, isp: String?, isActive: Bool, status: VPNDetectionStatus, authoritative: Bool) -> String? {
        switch status {
        case .notActive: return nil
        case .possiblyActive: return "VPN/Proxy Detected (inferred)"
        case .active:
            if authoritative {
                // NEVPNManager confirmed — no need for ISP details
                if let proto = vpnProtocol { return "\(proto) VPN Active" }
                return "VPN Active"
            }
            // Inferred from ISP/geo — show reasoning
            var parts: [String] = []
            if let proto = vpnProtocol { parts.append("\(proto) VPN") }
            else { parts.append("VPN/Proxy") }
            parts.append("(inferred)")
            if let ispName = isp {
                let shortISP = ispName.count > 30 ? String(ispName.prefix(27)) + "..." : ispName
                parts.append("via \(shortISP)")
            }
            return parts.joined(separator: " ")
        }
    }

    // MARK: - ISP Classification Helpers

    private func isKnownVPNProvider(isp: String?) -> Bool {
        guard let isp = isp else { return false }
        let ispLower = isp.lowercased()
        return (Self.datacenterKeywords + Self.vpnProviderKeywords).contains { ispLower.contains($0) }
    }

    private func isKnownResidentialISP(isp: String?) -> Bool {
        guard let isp = isp else { return false }
        let ispLower = isp.lowercased()
        return Self.residentialISPKeywords.contains { ispLower.contains($0) }
    }

    // MARK: - Expected Country (Timezone + Locale)

    /// Timezone → country mapping for more reliable geolocation than locale alone
    private static let timezoneCountryMap: [String: String] = [
        "Asia/Shanghai": "CN", "Asia/Chongqing": "CN", "Asia/Urumqi": "CN",
        "Asia/Hong_Kong": "HK", "Asia/Taipei": "TW", "Asia/Macau": "MO",
        "Asia/Tokyo": "JP", "Asia/Seoul": "KR",
        "Asia/Singapore": "SG", "Asia/Bangkok": "TH",
        "Asia/Kolkata": "IN", "Asia/Dubai": "AE",
        "America/New_York": "US", "America/Chicago": "US",
        "America/Denver": "US", "America/Los_Angeles": "US",
        "America/Anchorage": "US", "Pacific/Honolulu": "US",
        "America/Toronto": "CA", "America/Vancouver": "CA",
        "Europe/London": "GB", "Europe/Paris": "FR",
        "Europe/Berlin": "DE", "Europe/Madrid": "ES",
        "Europe/Rome": "IT", "Europe/Amsterdam": "NL",
        "Europe/Zurich": "CH", "Europe/Moscow": "RU",
        "Australia/Sydney": "AU", "Australia/Melbourne": "AU",
        "Pacific/Auckland": "NZ",
    ]

    /// Get the user's expected country from timezone (primary) + locale (fallback)
    private func getExpectedCountry() -> String {
        // Timezone is more reliable than locale — locale can be changed in Settings,
        // but timezone is usually set automatically from device location
        let tz = TimeZone.current.identifier
        if let country = Self.timezoneCountryMap[tz] {
            return country
        }

        // Fallback to locale region
        if let regionCode = Locale.current.region?.identifier {
            return regionCode
        }
        return "US"
    }

    /// Check if IP country and expected country are in the same "region group"
    /// (e.g., CN/HK/MO/TW are all Greater China — not a VPN mismatch)
    private static let regionGroups: [[String]] = [
        ["CN", "HK", "MO", "TW"],  // Greater China
        ["US", "PR", "VI", "GU"],   // US territories
    ]

    private func countriesInSameGroup(_ a: String, _ b: String) -> Bool {
        let upperA = a.uppercased()
        let upperB = b.uppercased()
        for group in Self.regionGroups {
            if group.contains(upperA) && group.contains(upperB) { return true }
        }
        return false
    }

    // MARK: - System DNS Servers

    nonisolated private func getSystemDNSServers() -> [String] {
        var servers: [String] = []
        if let contents = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) {
            for line in contents.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("nameserver ") {
                    let server = String(trimmed.dropFirst("nameserver ".count))
                        .trimmingCharacters(in: .whitespaces)
                    if !server.isEmpty { servers.append(server) }
                }
            }
        }
        return servers
    }

    // MARK: - Debug Helpers

    nonisolated func getAllInterfaces() -> [(name: String, ip: String, family: String)] {
        var result: [(String, String, String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee,
                  let addr = interface.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            let name = String(cString: interface.ifa_name)
            let familyStr = family == UInt8(AF_INET) ? "IPv4" : "IPv6"
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                result.append((name, String(cString: hostname), familyStr))
            }
        }
        return result
    }

    nonisolated func getRawSSIDInfo() -> String {
        #if targetEnvironment(simulator)
        return "Simulator - CNCopyCurrentNetworkInfo unavailable"
        #else
        var output = ""
        let status = LocationPermissionManager.shared.currentStatus
        output += "Location auth: \(status.rawValue)\n"
        output += "Location enabled: \(LocationPermissionManager.shared.isLocationEnabled)\n"
        if let interfaces = CNCopySupportedInterfaces() as? [String] {
            output += "Interfaces: \(interfaces)\n"
            for iface in interfaces {
                if let info = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: Any] {
                    output += "\(iface): \(info)\n"
                } else {
                    output += "\(iface): nil\n"
                }
            }
        } else {
            output += "CNCopySupportedInterfaces: nil\n"
        }
        return output
        #endif
    }

    nonisolated private func getNWPathDescription() -> String {
        let monitor = NWPathMonitor()
        let path = monitor.currentPath
        var desc = "Status: \(path.status)\n"
        desc += "WiFi: \(path.usesInterfaceType(.wifi)), Cell: \(path.usesInterfaceType(.cellular))\n"
        desc += "Other: \(path.usesInterfaceType(.other))\n"
        desc += "IPv4: \(path.supportsIPv4), IPv6: \(path.supportsIPv6)\n"
        desc += "Interfaces: \(path.availableInterfaces.map { $0.name }.joined(separator: ", "))"
        return desc
    }

    // MARK: - Empty Result

    private func makeEmptyResult(expectedCountry: String?) -> VPNDetectionResult {
        VPNDetectionResult(
            isVPNActive: false,
            detectionStatus: .notActive,
            vpnState: .unknown,
            detectionMethod: "none",
            publicIP: nil, publicCountry: nil, publicCity: nil,
            publicASN: nil, publicISP: nil,
            expectedCountry: expectedCountry ?? getExpectedCountry(),
            confidence: 0.0, methodResults: [],
            vpnProtocol: nil, ipType: nil, displayLabel: nil,
            isLikelyInChina: false, ipVerified: false,
            isAuthoritative: false, inferenceReasons: [],
            timestamp: Date()
        )
    }
}
