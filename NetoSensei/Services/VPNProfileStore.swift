//
//  VPNProfileStore.swift
//  NetoSensei
//
//  VPN Profile Storage - Persist, compare, and rank VPN profiles
//

import Foundation

@MainActor
class VPNProfileStore: ObservableObject {
    static let shared = VPNProfileStore()

    @Published var profiles: [VPNProfile] = []
    @Published var wifiBaseline: WiFiBaselineProfile?

    private let profilesKey = "vpn_profiles"
    private let baselineKey = "wifi_baseline"

    private init() {
        loadProfiles()
        loadBaseline()
    }

    // MARK: - Save and Load

    func saveProfile(_ profile: VPNProfile) {
        profiles.append(profile)
        profiles.sort { $0.timestamp > $1.timestamp }  // Newest first
        persistProfiles()
    }

    func saveBaseline(_ baseline: WiFiBaselineProfile) {
        wifiBaseline = baseline
        persistBaseline()
    }

    func deleteProfile(_ profile: VPNProfile) {
        profiles.removeAll { $0.id == profile.id }
        persistProfiles()
    }

    func clearAllProfiles() {
        profiles.removeAll()
        persistProfiles()
    }

    private func persistProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }
    }

    private func persistBaseline() {
        if let baseline = wifiBaseline,
           let encoded = try? JSONEncoder().encode(baseline) {
            UserDefaults.standard.set(encoded, forKey: baselineKey)
        }
    }

    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([VPNProfile].self, from: data) {
            profiles = decoded
        }
    }

    private func loadBaseline() {
        if let data = UserDefaults.standard.data(forKey: baselineKey),
           let decoded = try? JSONDecoder().decode(WiFiBaselineProfile.self, from: data) {
            wifiBaseline = decoded
        }
    }

    // MARK: - Rankings and Comparisons

    var rankedProfiles: [VPNProfile] {
        profiles.sorted { $0.overallScore > $1.overallScore }
    }

    var topProfile: VPNProfile? {
        rankedProfiles.first
    }

    func profilesByRegion() -> [String: [VPNProfile]] {
        Dictionary(grouping: profiles, by: { $0.country })
    }

    func profilesByProtocol() -> [String: [VPNProfile]] {
        Dictionary(grouping: profiles, by: { $0.protocolMode })
    }

    func bestProfileForRegion(_ country: String) -> VPNProfile? {
        profiles
            .filter { $0.country == country }
            .max { $0.overallScore < $1.overallScore }
    }

    func compareWithBaseline(_ profile: VPNProfile) -> VPNComparison? {
        guard let baseline = wifiBaseline else { return nil }
        return VPNComparison(baseline: baseline, vpnProfile: profile)
    }

    // MARK: - Smart Recommendations

    func getSenseiRecommendations() -> [SenseiRecommendation] {
        var recommendations: [SenseiRecommendation] = []

        // 1. Best VPN recommendation
        if let best = topProfile {
            recommendations.append(SenseiRecommendation(
                priority: .critical,
                title: "Best VPN for You",
                message: "🇸🇬 \(best.displayName) - Score \(best.scoreText)",
                detail: best.performanceSummary,
                action: .switchVPN(best)
            ))
        }

        // 2. Slow VPN warning
        let slowProfiles = profiles.filter { $0.overallScore < 5.0 }
        if !slowProfiles.isEmpty {
            let slowNames = slowProfiles.map { $0.region }.joined(separator: ", ")
            recommendations.append(SenseiRecommendation(
                priority: .high,
                title: "Avoid These Regions",
                message: "These VPN servers are slow: \(slowNames)",
                detail: "Score < 5.0/10",
                action: .avoid
            ))
        }

        // 3. DNS leak warning
        let leakedProfiles = profiles.filter { $0.dnsLeakDetected }
        if !leakedProfiles.isEmpty {
            recommendations.append(SenseiRecommendation(
                priority: .critical,
                title: "DNS Leak Detected",
                message: "Your DNS is leaking in: \(leakedProfiles.map { $0.region }.joined(separator: ", "))",
                detail: "Switch to 1.1.1.1 or 8.8.8.8 in VPN settings",
                action: .fixDNS
            ))
        }

        // 4. WiFi baseline comparison
        if let baseline = wifiBaseline, let best = topProfile {
            let comparison = VPNComparison(baseline: baseline, vpnProfile: best)

            if comparison.speedDecreasePercentage > 70 {
                recommendations.append(SenseiRecommendation(
                    priority: .high,
                    title: "VPN Slowing You Down",
                    message: "VPN reduces speed by \(Int(comparison.speedDecreasePercentage))%",
                    detail: comparison.recommendation,
                    action: .optimize
                ))
            }
        }

        // 5. Region-specific advice
        let byRegion = profilesByRegion()
        if byRegion.count >= 3 {
            let regionScores = byRegion.mapValues { profiles in
                profiles.map { $0.overallScore }.reduce(0, +) / Double(profiles.count)
            }.sorted { $0.value > $1.value }

            if let best = regionScores.first {
                recommendations.append(SenseiRecommendation(
                    priority: .medium,
                    title: "Best Region Overall",
                    message: "\(best.key) performs best on average",
                    detail: "Average score: \(String(format: "%.1f", best.value))/10",
                    action: .switchRegion(best.key)
                ))
            }
        }

        return recommendations
    }

    // MARK: - Streaming Quality Assessment

    func getStreamingRecommendation() -> String {
        guard let best = topProfile else {
            return "No VPN profiles yet. Run a benchmark!"
        }

        switch best.streamingQuality {
        case .fourK:
            return "✅ Your best VPN (\(best.region)) supports 4K streaming smoothly"
        case .fullHD:
            return "✅ Your best VPN (\(best.region)) supports 1080p streaming"
        case .hd:
            return "🟡 Your best VPN (\(best.region)) supports 720p. Try Singapore for better quality."
        case .buffering:
            return "🔴 Your VPN is too slow for smooth streaming. Turn VPN OFF or switch to Singapore."
        }
    }
}

// MARK: - Sensei Recommendation

struct SenseiRecommendation: Identifiable {
    let id = UUID()
    let priority: RecommendationPriority
    let title: String
    let message: String
    let detail: String
    let action: RecommendationAction
}

enum RecommendationAction {
    case switchVPN(VPNProfile)
    case switchRegion(String)
    case avoid
    case fixDNS
    case optimize
}
