//
//  Constants.swift
//  NetoSensei
//
//  Application-wide constants
//

import Foundation
import SwiftUI

// MARK: - App Constants

enum AppConstants {
    /// App name
    static let appName = "NetoSensei"

    /// App version (from bundle)
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    /// App build number (from bundle)
    static let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    /// Full version string
    static let fullVersion = "\(appVersion) (\(buildNumber))"

    /// Support email
    static let supportEmail = "support@netosensei.app"

    /// Privacy policy URL
    static let privacyPolicyURL = URL(string: "https://netosensei.app/privacy")

    /// Terms of service URL
    static let termsOfServiceURL = URL(string: "https://netosensei.app/terms")
}

// MARK: - Network Constants

enum NetworkConstants {
    // MARK: - Timeout Values

    /// Default network timeout in seconds
    static let defaultTimeout: TimeInterval = 10.0

    /// Ping timeout in seconds
    static let pingTimeout: TimeInterval = 3.0

    /// DNS lookup timeout in seconds
    static let dnsTimeout: TimeInterval = 5.0

    /// HTTP request timeout in seconds
    static let httpTimeout: TimeInterval = 15.0

    /// Speed test timeout in seconds
    static let speedTestTimeout: TimeInterval = 60.0

    // MARK: - Test Servers

    /// Primary DNS servers for testing
    static let primaryDNSServers = [
        "1.1.1.1",      // Cloudflare
        "8.8.8.8",      // Google
        "208.67.222.222" // OpenDNS
    ]

    /// Test domains for DNS lookup
    static let testDomains = [
        "google.com",
        "cloudflare.com",
        "apple.com"
    ]

    /// Speed test servers
    static let speedTestServers = [
        "https://speed.cloudflare.com",
        "https://fast.com"
    ]

    // MARK: - Thresholds

    /// Excellent ping threshold (ms)
    static let excellentPingThreshold: Double = 30.0

    /// Good ping threshold (ms)
    static let goodPingThreshold: Double = 50.0

    /// Excellent Wi-Fi RSSI threshold (dBm)
    static let excellentWiFiRSSI: Int = -50

    /// Good Wi-Fi RSSI threshold (dBm)
    static let goodWiFiRSSI: Int = -67

    /// Poor Wi-Fi RSSI threshold (dBm)
    static let poorWiFiRSSI: Int = -70

    /// High packet loss threshold (%)
    static let highPacketLossThreshold: Double = 5.0

    /// High jitter threshold (ms)
    static let highJitterThreshold: Double = 30.0

    /// Slow DNS threshold (ms)
    static let slowDNSThreshold: Double = 100.0

    /// Very slow DNS threshold (ms)
    static let verySlowDNSThreshold: Double = 200.0

    // MARK: - Streaming Thresholds

    /// Minimum speed for SD streaming (Mbps)
    static let sdStreamingSpeed: Double = 3.0

    /// Minimum speed for HD streaming (Mbps)
    static let hdStreamingSpeed: Double = 5.0

    /// Minimum speed for Full HD streaming (Mbps)
    static let fullHDStreamingSpeed: Double = 8.0

    /// Minimum speed for 4K streaming (Mbps)
    static let uhd4KStreamingSpeed: Double = 25.0

    // MARK: - Update Intervals

    /// Dashboard update interval (seconds)
    static let dashboardUpdateInterval: TimeInterval = 2.0

    /// VPN health check interval (seconds)
    static let vpnHealthCheckInterval: TimeInterval = 30.0

    /// Background refresh interval (seconds)
    static let backgroundRefreshInterval: TimeInterval = 900.0 // 15 minutes
}

// MARK: - UI Constants

enum UIConstants {
    // MARK: - Spacing

    /// Extra small spacing
    static let spacingXS: CGFloat = 4

    /// Small spacing
    static let spacingS: CGFloat = 8

    /// Medium spacing
    static let spacingM: CGFloat = 12

    /// Large spacing
    static let spacingL: CGFloat = 16

    /// Extra large spacing
    static let spacingXL: CGFloat = 24

    /// Extra extra large spacing
    static let spacingXXL: CGFloat = 32

    // MARK: - Corner Radius

    /// Small corner radius
    static let cornerRadiusS: CGFloat = 8

    /// Medium corner radius
    static let cornerRadiusM: CGFloat = 12

    /// Large corner radius
    static let cornerRadiusL: CGFloat = 16

    // MARK: - Shadow

    /// Default shadow radius
    static let shadowRadius: CGFloat = 2

    /// Card shadow radius
    static let cardShadowRadius: CGFloat = 4

    // MARK: - Icon Sizes

    /// Small icon size
    static let iconSizeS: CGFloat = 16

    /// Medium icon size
    static let iconSizeM: CGFloat = 24

    /// Large icon size
    static let iconSizeL: CGFloat = 32

    /// Extra large icon size
    static let iconSizeXL: CGFloat = 48

    // MARK: - Button Heights

    /// Standard button height
    static let buttonHeight: CGFloat = 50

    /// Small button height
    static let smallButtonHeight: CGFloat = 40

    // MARK: - Animation Durations

    /// Fast animation duration
    static let animationFast: Double = 0.2

    /// Standard animation duration
    static let animationStandard: Double = 0.3

    /// Slow animation duration
    static let animationSlow: Double = 0.5
}

// MARK: - App Colors (STEP 5)

struct AppColors {
    /// Success/Excellent status color - Optimized for light and dark mode
    static let green = Color(
        light: Color(red: 0.2, green: 0.78, blue: 0.35),
        dark: Color(red: 0.19, green: 0.82, blue: 0.35)
    )

    /// Warning/Fair status color - Optimized for light and dark mode
    static let yellow = Color(
        light: Color(red: 1.0, green: 0.8, blue: 0.0),
        dark: Color(red: 1.0, green: 0.84, blue: 0.0)
    )

    /// Critical/Poor status color - Optimized for light and dark mode
    static let red = Color(
        light: Color(red: 1.0, green: 0.23, blue: 0.19),
        dark: Color(red: 1.0, green: 0.27, blue: 0.23)
    )

    /// Card background color
    static let card = Color(uiColor: .secondarySystemBackground)

    /// Primary text color
    static let textPrimary = Color.primary

    /// Secondary text color
    static let textSecondary = Color.secondary

    /// Accent color for highlights
    static let accent = Color.accentColor

    /// Background color
    static let background = Color(uiColor: .systemBackground)
}

// MARK: - Color Extensions for Dark Mode

extension Color {
    /// Creates a color that adapts to light/dark mode
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor(light: UIColor(light), dark: UIColor(dark)))
    }
}

extension UIColor {
    /// Creates a UIColor that adapts to light/dark mode
    convenience init(light: UIColor, dark: UIColor) {
        self.init { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return dark
            default:
                return light
            }
        }
    }
}

// MARK: - API Constants

enum APIConstants {
    // MARK: - GeoIP APIs

    /// Primary GeoIP API
    static let primaryGeoIPAPI = "https://ipapi.co/json/"

    /// Fallback GeoIP API 1 (HTTPS for ATS compliance)
    static let fallbackGeoIPAPI1 = "https://ipwho.is/"

    /// Fallback GeoIP API 2
    static let fallbackGeoIPAPI2 = "https://ipinfo.io/json"

    /// IP-only API
    static let ipOnlyAPI = "https://api.ipify.org?format=json"

    // MARK: - Rate Limits

    /// IP-API rate limit (requests per minute)
    static let ipAPIRateLimit = 45

    /// IPInfo rate limit (requests per month, free tier)
    static let ipInfoRateLimit = 50_000

    /// IPAPI.co rate limit (requests per day, free tier)
    static let ipapiCoRateLimit = 1_000

    // MARK: - Cache Duration

    /// GeoIP cache duration (seconds)
    static let geoIPCacheDuration: TimeInterval = 3600 // 1 hour

    /// Speed test result cache duration (seconds)
    static let speedTestCacheDuration: TimeInterval = 300 // 5 minutes
}

// MARK: - Storage Constants

enum StorageConstants {
    // MARK: - UserDefaults Keys

    /// Speed test history key
    static let speedTestHistoryKey = "speedTestHistory"

    /// Diagnostic history key
    static let diagnosticHistoryKey = "diagnosticHistory"

    /// Last GeoIP lookup key
    static let lastGeoIPKey = "lastGeoIPLookup"

    /// Last GeoIP timestamp key
    static let lastGeoIPTimestampKey = "lastGeoIPTimestamp"

    /// User preferences key
    static let userPreferencesKey = "userPreferences"

    /// Onboarding completed key
    static let onboardingCompletedKey = "onboardingCompleted"

    // MARK: - Limits

    /// Maximum history entries
    static let maxHistoryEntries = 100

    /// Maximum diagnostic entries
    static let maxDiagnosticEntries = 50
}

// MARK: - Error Messages

enum ErrorMessages {
    // MARK: - Network Errors

    static let networkUnavailable = "Network is unavailable. Please check your connection."
    static let requestTimeout = "Request timed out. Please try again."
    static let serverUnreachable = "Server is unreachable. Please try again later."

    // MARK: - Permission Errors

    static let locationPermissionDenied = "Location permission is required to access Wi-Fi information."
    static let networkPermissionDenied = "Local network permission is required for diagnostics."
    static let vpnPermissionDenied = "VPN access permission is required for VPN diagnostics."

    // MARK: - General Errors

    static let unknownError = "An unknown error occurred. Please try again."
    static let dataParsingError = "Failed to parse response data."
    static let invalidResponse = "Received invalid response from server."
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when network status changes significantly
    static let networkStatusChanged = Notification.Name("networkStatusChanged")

    /// Posted when diagnostic completes
    static let diagnosticCompleted = Notification.Name("diagnosticCompleted")

    /// Posted when speed test completes
    static let speedTestCompleted = Notification.Name("speedTestCompleted")

    /// Posted when VPN status changes
    static let vpnStatusChanged = Notification.Name("vpnStatusChanged")
}

// MARK: - Feature Flags

enum FeatureFlags {
    /// Enable VPN auto-recovery
    static let enableVPNAutoRecovery = true

    /// Enable background monitoring
    static let enableBackgroundMonitoring = false

    /// Enable advanced analytics
    static let enableAdvancedAnalytics = false

    /// Enable debug logging
    static let enableDebugLogging = false

    /// Enable experimental features
    static let enableExperimentalFeatures = false
}
