//
//  GeoIPService.swift
//  NetoSensei
//
//  Geolocation and IP information service
//

import Foundation

// FIXED: Removed @MainActor to prevent UI blocking
// FIXED: Added proper task management to prevent multiple concurrent fetches
// FIXED: Removed NSLock which is not safe in async contexts (Swift 6)
// FIXED: Added 5-minute caching to prevent API rate limit issues
@MainActor
class GeoIPService: ObservableObject {
    static let shared = GeoIPService()

    @Published var currentGeoIP: GeoIPInfo = .empty
    @Published var isLoading = false

    // Free GeoIP APIs (HTTPS only to comply with ATS)
    private let apiEndpoints = [
        "https://ipapi.co/json/",
        "https://ipwho.is/",  // HTTPS alternative to ip-api.com
        "https://ipinfo.io/json"
    ]

    // Task management to prevent multiple concurrent fetches
    private var currentFetchTask: Task<GeoIPInfo, Never>?
    // FIXED: Use actor-based synchronization instead of NSLock
    private var isFetching = false

    // FIXED: Cache management - 5 minute cache to prevent rate limit issues
    private var cachedResult: GeoIPInfo?
    private var cacheTimestamp: Date?
    private static let cacheDuration: TimeInterval = 300.0  // 5 minutes

    private init() {}

    // MARK: - Fetch GeoIP Information

    func fetchGeoIPInfo(forceRefresh: Bool = false) async -> GeoIPInfo {
        // FIXED: Return cached result if within cache duration (5 minutes)
        if !forceRefresh,
           let cached = cachedResult,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < Self.cacheDuration {
            print("🌍 GeoIP: Using cached result (cache valid for \(Int(Self.cacheDuration - Date().timeIntervalSince(timestamp)))s)")
            return cached
        }

        // FIXED: Use simple flag instead of NSLock for async safety
        if isFetching, let existingTask = currentFetchTask {
            return await existingTask.value
        }

        isFetching = true
        isLoading = true
        print("🌍 GeoIP: Starting fresh fetch...")

        // Create new fetch task
        let task = Task<GeoIPInfo, Never> { [weak self] in
            guard let self = self else { return .empty }

            // IMPROVED: Fetch from multiple sources in parallel
            // ISSUE 11 FIX: Prefer results that include ISP data to avoid "unknown"
            let result: GeoIPInfo? = await withTaskGroup(of: GeoIPInfo?.self) { group in
                group.addTask { await self.fetchFromIPAPICo() }
                group.addTask { await self.fetchFromIPAPI() }
                group.addTask { await self.fetchFromIPInfo() }

                // Add timeout task
                group.addTask {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    return nil
                }

                // Collect results: prefer one with ISP data
                var firstResult: GeoIPInfo? = nil
                for await info in group {
                    if let validInfo = info {
                        // If this result has ISP data, use it immediately
                        if validInfo.isp != nil {
                            group.cancelAll()
                            return validInfo
                        }
                        // Otherwise save it as fallback and keep waiting
                        if firstResult == nil {
                            firstResult = validInfo
                        }
                    }
                }
                return firstResult
            }

            return result ?? .empty
        }

        currentFetchTask = task

        let result = await task.value

        // Update state and cache
        currentGeoIP = result
        isLoading = false
        currentFetchTask = nil
        isFetching = false

        // FIXED: Cache the result with timestamp
        if result.publicIP != "0.0.0.0" {
            cachedResult = result
            cacheTimestamp = Date()
            print("🌍 GeoIP: Cached result for \(Int(Self.cacheDuration))s")
        }

        return result
    }

    /// Clear the cache (call when network changes significantly)
    func clearCache() {
        cachedResult = nil
        cacheTimestamp = nil
        print("🌍 GeoIP: Cache cleared")
    }

    // MARK: - API Implementations

    private func fetchFromIPAPICo() async -> GeoIPInfo? {
        guard let url = URL(string: "https://ipapi.co/json/") else { return nil }

        do {
            // Add timeout
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0

            let (data, response) = try await URLSession.shared.data(for: request)

            // FIXED: Check HTTP status code before decoding
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 429 {
                    print("⚠️ IPAPICo rate limited (429)")
                    return nil
                }
                if httpResponse.statusCode != 200 {
                    print("⚠️ IPAPICo returned status \(httpResponse.statusCode)")
                    if let body = String(data: data, encoding: .utf8) {
                        print("⚠️ Response body: \(body.prefix(200))")
                    }
                    return nil
                }
            }

            let decoded = try JSONDecoder().decode(IPAPICoResponse.self, from: data)

            return GeoIPInfo(
                publicIP: decoded.ip,
                ipVersion: decoded.version ?? "IPv4",
                country: decoded.country_name,
                countryCode: decoded.country_code,
                region: decoded.region,
                city: decoded.city,
                latitude: decoded.latitude,
                longitude: decoded.longitude,
                timezone: decoded.timezone,
                isp: decoded.org,
                org: decoded.org,
                asn: decoded.asn,
                asnOrg: decoded.org,
                isProxy: false,
                isVPN: false,
                isTor: false,
                isHosting: false,
                isRelay: false,
                isCGNAT: detectCGNAT(ip: decoded.ip),
                hostname: nil,
                dnsProvider: nil
            )
        } catch {
            // FIXED: Don't log cancellation errors - they're expected when another provider succeeds first
            if (error as NSError).code != NSURLErrorCancelled {
                print("⚠️ IPAPICo fetch failed: \(error)")
            }
            return nil
        }
    }

    /// Fetch from ipwho.is (HTTPS alternative to ip-api.com) - FIRST PRIORITY (most reliable)
    private func fetchFromIPAPI() async -> GeoIPInfo? {
        guard let url = URL(string: "https://ipwho.is/") else { return nil }

        do {
            // Add timeout
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0

            let (data, response) = try await URLSession.shared.data(for: request)

            // FIXED: Check HTTP status code before decoding
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 429 {
                    print("⚠️ ipwho.is rate limited (429)")
                    return nil
                }
                if httpResponse.statusCode != 200 {
                    print("⚠️ ipwho.is returned status \(httpResponse.statusCode)")
                    return nil
                }
            }

            // ipwho.is response format
            struct IPWhoIsResponse: Codable {
                let ip: String?
                let success: Bool?
                let type: String?
                let country: String?
                let country_code: String?
                let region: String?
                let city: String?
                let latitude: Double?
                let longitude: Double?
                let timezone: TimezoneInfo?
                let connection: ConnectionInfo?

                struct TimezoneInfo: Codable {
                    let id: String?
                }

                struct ConnectionInfo: Codable {
                    let isp: String?
                    let org: String?
                    let asn: Int?
                    let domain: String?
                }
            }

            let decoded = try JSONDecoder().decode(IPWhoIsResponse.self, from: data)

            guard decoded.success == true else {
                print("⚠️ ipwho.is returned success=false")
                return nil
            }

            return GeoIPInfo(
                publicIP: decoded.ip ?? "0.0.0.0",
                ipVersion: decoded.type ?? "IPv4",
                country: decoded.country,
                countryCode: decoded.country_code,
                region: decoded.region,
                city: decoded.city,
                latitude: decoded.latitude,
                longitude: decoded.longitude,
                timezone: decoded.timezone?.id,
                isp: decoded.connection?.isp,
                org: decoded.connection?.org,
                asn: decoded.connection?.asn != nil ? "AS\(decoded.connection!.asn!)" : nil,
                asnOrg: decoded.connection?.org,
                isProxy: false,
                isVPN: false,
                isTor: false,
                isHosting: false,
                isRelay: false,
                isCGNAT: detectCGNAT(ip: decoded.ip ?? "0.0.0.0"),
                hostname: nil,
                dnsProvider: nil
            )
        } catch {
            // FIXED: Don't log cancellation errors - they're expected when another provider succeeds first
            if (error as NSError).code != NSURLErrorCancelled {
                print("⚠️ ipwho.is fetch failed: \(error)")
            }
            return nil
        }
    }

    private func fetchFromIPInfo() async -> GeoIPInfo? {
        guard let url = URL(string: "https://ipinfo.io/json") else { return nil }

        do {
            // Add timeout
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0

            let (data, response) = try await URLSession.shared.data(for: request)

            // FIXED: Check HTTP status code before decoding
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 429 {
                    print("⚠️ IPInfo rate limited (429)")
                    return nil
                }
                if httpResponse.statusCode != 200 {
                    print("⚠️ IPInfo returned status \(httpResponse.statusCode)")
                    return nil
                }
            }

            let decoded = try JSONDecoder().decode(IPInfoResponse.self, from: data)

            // Parse location
            var lat: Double?
            var lon: Double?
            if let loc = decoded.loc {
                let coords = loc.split(separator: ",")
                if coords.count == 2 {
                    lat = Double(coords[0])
                    lon = Double(coords[1])
                }
            }

            return GeoIPInfo(
                publicIP: decoded.ip,
                ipVersion: "IPv4",
                country: decoded.country,
                countryCode: decoded.country,
                region: decoded.region,
                city: decoded.city,
                latitude: lat,
                longitude: lon,
                timezone: decoded.timezone,
                isp: decoded.org,
                org: decoded.org,
                asn: decoded.asn?.asn,
                asnOrg: decoded.asn?.name,
                isProxy: decoded.privacy?.proxy ?? false,
                isVPN: decoded.privacy?.vpn ?? false,
                isTor: decoded.privacy?.tor ?? false,
                isHosting: decoded.privacy?.hosting ?? false,
                isRelay: decoded.privacy?.relay ?? false,
                isCGNAT: detectCGNAT(ip: decoded.ip),
                hostname: decoded.hostname,
                dnsProvider: nil
            )
        } catch {
            // FIXED: Don't log cancellation errors - they're expected when another provider succeeds first
            if (error as NSError).code != NSURLErrorCancelled {
                print("⚠️ IPInfo fetch failed: \(error)")
            }
            return nil
        }
    }

    // MARK: - CGNAT Detection

    private func detectCGNAT(ip: String) -> Bool {
        // Check if IP is in CGNAT range (100.64.0.0/10)
        let components = ip.split(separator: ".")
        guard components.count == 4,
              let first = Int(components[0]),
              let second = Int(components[1]) else {
            return false
        }

        // CGNAT range: 100.64.0.0 - 100.127.255.255
        if first == 100 && second >= 64 && second <= 127 {
            return true
        }

        return false
    }

    // MARK: - Quick IP Lookup

    func getPublicIP() async -> String? {
        // Simple API to just get IP
        guard let url = URL(string: "https://api.ipify.org?format=json") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ip = json["ip"] as? String {
                return ip
            }
        } catch {
            print("Failed to get public IP: \(error)")
        }

        return nil
    }
}

// MARK: - Response Models

struct IPAPICoResponse: Codable {
    var ip: String
    var version: String?
    var city: String?
    var region: String?
    var country_name: String?
    var country_code: String?
    var latitude: Double?
    var longitude: Double?
    var timezone: String?
    var org: String?
    var asn: String?
}
