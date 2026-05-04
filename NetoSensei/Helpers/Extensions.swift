//
//  Extensions.swift
//  NetoSensei
//
//  Utility extensions for common types
//

import Foundation
import SwiftUI
import Network

// MARK: - Date Extensions

extension Date {
    /// Format date as relative time (e.g., "2 minutes ago")
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Format date as short time string (e.g., "2:30 PM")
    var shortTimeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Format date as medium date string (e.g., "Dec 15, 2025")
    var mediumDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: self)
    }

    /// Format date and time (e.g., "Dec 15, 2025 at 2:30 PM")
    var fullDateTimeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - Double Extensions

extension Double {
    /// Format as Mbps with 1 decimal place
    var asMbps: String {
        String(format: "%.1f Mbps", self)
    }

    /// Format as milliseconds with 0 decimal places
    var asMilliseconds: String {
        String(format: "%.0f ms", self)
    }

    /// Format as percentage with 1 decimal place
    var asPercentage: String {
        String(format: "%.1f%%", self)
    }

    /// Format as bytes (KB, MB, GB)
    var asBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(self))
    }
}

// MARK: - String Extensions

extension String {
    /// Validate if string is a valid IP address (IPv4 or IPv6)
    var isValidIPAddress: Bool {
        var sin = sockaddr_in()
        var sin6 = sockaddr_in6()

        if self.withCString({ cstring in inet_pton(AF_INET, cstring, &sin.sin_addr) }) == 1 {
            return true
        }

        if self.withCString({ cstring in inet_pton(AF_INET6, cstring, &sin6.sin6_addr) }) == 1 {
            return true
        }

        return false
    }

    /// Validate if string is a valid domain name
    var isValidDomain: Bool {
        let domainRegex = "^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)
        return predicate.evaluate(with: self)
    }

    /// Truncate string to specified length with ellipsis
    func truncated(to length: Int, trailing: String = "...") -> String {
        if self.count <= length {
            return self
        } else {
            return String(self.prefix(length)) + trailing
        }
    }
}

// MARK: - Color Extensions

extension Color {
    /// Color from network health status
    static func fromHealth(_ health: NetworkHealth) -> Color {
        switch health {
        case .excellent: return .green
        case .fair: return .yellow
        case .poor: return .red
        case .unknown: return .gray
        }
    }

    /// Color from severity level
    static func fromSeverity(_ severity: IssueSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .moderate: return .orange
        case .minor: return .blue
        case .none: return .green
        }
    }

    /// Initialize from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Extensions

extension View {
    /// Apply conditional modifier
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Add loading overlay
    func loading(_ isLoading: Bool) -> some View {
        overlay(
            Group {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.3)
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                }
            }
        )
    }

    /// Add corner radius to specific corners
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// MARK: - Custom Shapes

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - NWInterface.InterfaceType Extension

extension NWInterface.InterfaceType {
    /// Icon name for interface type
    var iconName: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .wiredEthernet: return "cable.connector"
        case .loopback: return "arrow.triangle.2.circlepath"
        case .other: return "network"
        @unknown default: return "questionmark.circle"
        }
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .wifi: return "WiFi"
        case .cellular: return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .loopback: return "Loopback"
        case .other: return "Other"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - Array Extensions

extension Array where Element == DiagnosticTest {
    /// Filter tests by result
    func filter(byResult result: DiagnosticTest.TestResult) -> [DiagnosticTest] {
        self.filter { $0.result == result }
    }

    /// Count tests by result
    func count(byResult result: DiagnosticTest.TestResult) -> Int {
        self.filter { $0.result == result }.count
    }

    /// Get passed tests
    var passedTests: [DiagnosticTest] {
        filter(byResult: .pass)
    }

    /// Get failed tests
    var failedTests: [DiagnosticTest] {
        filter(byResult: .fail)
    }
}

// MARK: - UserDefaults Extensions

extension UserDefaults {
    /// Maximum size for UserDefaults storage (400KB to stay safe under ~1MB limit)
    static let maxEncodedSize = 400_000  // 400KB

    /// Save Codable object to UserDefaults with size guard
    /// FIXED: NO loops, NO recursion. Encode once, check once, save once.
    func setCodable<T: Codable>(_ object: T, forKey key: String) {
        guard let encoded = try? JSONEncoder().encode(object) else {
            debugLog("❌ UserDefaults: Failed to encode \(key)")
            return
        }

        if encoded.count > UserDefaults.maxEncodedSize {
            debugLog("⚠️ UserDefaults: \(key) too large (\(encoded.count) bytes), NOT saving")
            return
        }

        // Call the raw Data setter directly (not recursing through Codable)
        setValue(encoded, forKey: key)
    }

    /// Retrieve Codable object from UserDefaults
    func getCodable<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Safe save for arrays - trim to maxItems, encode once, save once. NO loops.
    func setSafe<T: Codable>(_ array: [T], forKey key: String, maxItems: Int = 50) {
        // Step 1: Trim to max count FIRST
        let trimmed = Array(array.prefix(maxItems))

        // Step 2: Encode ONCE
        guard let data = try? JSONEncoder().encode(trimmed) else {
            debugLog("❌ UserDefaults: Failed to encode \(key)")
            return
        }

        // Step 3: Check size ONCE - if still too big, trim harder (no loop)
        if data.count > UserDefaults.maxEncodedSize {
            let smallerItems = Array(array.prefix(max(1, maxItems / 5)))
            guard let smallerData = try? JSONEncoder().encode(smallerItems) else { return }
            if smallerData.count > UserDefaults.maxEncodedSize {
                debugLog("⚠️ UserDefaults: \(key) still too large after hard trim, NOT saving")
                return
            }
            setValue(smallerData, forKey: key)
        } else {
            setValue(data, forKey: key)
        }
    }
}

// MARK: - Result Extensions

extension Result where Success == Void {
    /// Success result with no value
    static var success: Result {
        .success(())
    }
}

// MARK: - Task Extensions

extension Task where Success == Never, Failure == Never {
    /// Sleep for seconds (convenience wrapper)
    static func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Haptic Feedback Helper

/// Centralized haptic feedback manager following Apple Human Interface Guidelines
enum HapticFeedback {
    /// Light impact - for subtle UI feedback
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Medium impact - for standard button presses
    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Heavy impact - for significant actions
    static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Success notification - for successful completion
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// Warning notification - for warnings
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    /// Error notification - for errors
    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }

    /// Selection changed - for picker/selection changes
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

// MARK: - Accessibility Extensions

extension View {
    /// Add accessibility label and hint for better VoiceOver support
    func accessibleAction(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }

    /// Mark view as an accessibility header
    func accessibilityHeader(_ text: String) -> some View {
        self
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }

    /// Add accessibility value for status indicators
    func accessibilityStatus(_ status: String, label: String) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityValue(status)
    }
}

// MARK: - NetworkHealth Accessibility Extension

extension NetworkHealth {
    /// Accessibility description for VoiceOver
    var accessibilityDescription: String {
        switch self {
        case .excellent: return "Network health is excellent. All systems working normally."
        case .fair: return "Network health is fair. Some minor issues detected."
        case .poor: return "Network health is poor. Significant issues detected."
        case .unknown: return "Network health status is unknown."
        }
    }
}
