//
//  NetoSenseiApp.swift
//  NetoSensei
//
//  Main app entry point with singleton services
//  STEP 6 - App Architecture
//

import SwiftUI
import CoreLocation
import UIKit

// MARK: - Location Permission Manager
/// Manages location permission for WiFi SSID access on iOS 13+
class LocationPermissionManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionManager()

    private let locationManager = CLLocationManager()

    /// Cached authorization status — updated via delegate, safe to read from any thread
    private(set) var currentStatus: CLAuthorizationStatus = .notDetermined

    /// Cached location services enabled flag
    private(set) var isLocationEnabled: Bool = false

    private override init() {
        super.init()
        // ISSUE 5 FIX: Don't call locationServicesEnabled() or authorizationStatus on main thread
        // in init(). Setting the delegate triggers locationManagerDidChangeAuthorization immediately,
        // which populates currentStatus and isLocationEnabled off the synchronous init path.
        locationManager.delegate = self
    }

    /// Request location permission if not already granted
    func requestPermissionIfNeeded() {
        switch currentStatus {
        case .notDetermined:
            debugLog("📍 Requesting location permission for WiFi SSID access...")
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            debugLog("📍 Location permission already granted")
        case .restricted, .denied:
            debugLog("📍 Location permission denied - WiFi SSID will not be available")
        @unknown default:
            break
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if #available(iOS 14.0, *) {
            currentStatus = manager.authorizationStatus
        } else {
            currentStatus = CLLocationManager.authorizationStatus()
        }
        isLocationEnabled = CLLocationManager.locationServicesEnabled()

        switch currentStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            debugLog("📍 Location permission granted - WiFi SSID access enabled")
        case .denied:
            debugLog("📍 Location permission denied - WiFi SSID access disabled")
        default:
            break
        }
    }
}

// MARK: - Crash Logging Helper
class CrashLogger {
    static let shared = CrashLogger()

    // Track last activity to help diagnose crashes
    private var lastActivity: String = "App starting"
    private let activityKey = "CrashLogger_LastActivity"
    private let crashKey = "CrashLogger_DidCrash"

    private init() {
        checkForPreviousCrash()
        setupCrashHandling()
    }

    private func checkForPreviousCrash() {
        // Check if app crashed last time
        if UserDefaults.standard.bool(forKey: crashKey) {
            let lastActivity = UserDefaults.standard.string(forKey: activityKey) ?? "Unknown"
            debugLog("⚠️ APP CRASHED PREVIOUSLY!")
            debugLog("⚠️ Last activity before crash: \(lastActivity)")
            logToFile("Previous crash detected. Last activity: \(lastActivity)")
        }
        // Mark that app is running (will be cleared on normal exit)
        UserDefaults.standard.set(true, forKey: crashKey)
        UserDefaults.standard.synchronize()
    }

    func markNormalExit() {
        // Called when app exits normally
        UserDefaults.standard.set(false, forKey: crashKey)
        UserDefaults.standard.synchronize()
    }

    func setActivity(_ activity: String) {
        lastActivity = activity
        UserDefaults.standard.set(activity, forKey: activityKey)
        // Don't synchronize every time - too slow
    }

    private func setupCrashHandling() {
        // Set up exception handler
        NSSetUncaughtExceptionHandler { exception in
            let message = """
            🚨 UNCAUGHT EXCEPTION:
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "unknown")
            Last Activity: \(CrashLogger.shared.lastActivity)
            Call Stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """
            debugLog(message)
            CrashLogger.shared.logToFile(message)
        }

        // Set up signal handlers for common crash signals
        signal(SIGABRT) { signal in
            let message = "🚨 CRASH: SIGABRT (signal \(signal)) - Abort"
            debugLog(message)
            CrashLogger.shared.logToFile(message)
        }
        signal(SIGSEGV) { signal in
            let message = "🚨 CRASH: SIGSEGV (signal \(signal)) - Segmentation fault"
            debugLog(message)
            CrashLogger.shared.logToFile(message)
        }
        signal(SIGBUS) { signal in
            let message = "🚨 CRASH: SIGBUS (signal \(signal)) - Bus error"
            debugLog(message)
            CrashLogger.shared.logToFile(message)
        }
        signal(SIGILL) { signal in
            let message = "🚨 CRASH: SIGILL (signal \(signal)) - Illegal instruction"
            debugLog(message)
            CrashLogger.shared.logToFile(message)
        }
        signal(SIGFPE) { signal in
            let message = "🚨 CRASH: SIGFPE (signal \(signal)) - Floating point exception"
            debugLog(message)
            CrashLogger.shared.logToFile(message)
        }
        signal(SIGTRAP) { signal in
            let message = "🚨 CRASH: SIGTRAP (signal \(signal)) - Trace/breakpoint trap (Swift runtime error)"
            debugLog(message)
            CrashLogger.shared.logToFile(message)
        }
    }

    func logToFile(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"

        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logFile = documentsPath.appendingPathComponent("crash_log.txt")
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                if let data = logMessage.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try? logMessage.write(to: logFile, atomically: true, encoding: .utf8)
            }
        }
    }

    func log(_ message: String) {
        debugLog("📱 [NetoSensei] \(message)")
        setActivity(message)
    }

    func getCrashLog() -> String? {
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logFile = documentsPath.appendingPathComponent("crash_log.txt")
            return try? String(contentsOf: logFile, encoding: .utf8)
        }
        return nil
    }
}

// MARK: - App Delegate (Background Task Registration)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // BackgroundTaskManager is initialized on first access
        _ = BackgroundTaskManager.shared
        return true
    }
}

@main
struct NetoSenseiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Global Service Singletons
    // These services are shared across the entire app to ensure consistency
    // and avoid duplicate network tests

    init() {
        // MINIMAL INIT - just print to console
        debugLog("🚀 App init() called")

        // IMPORTANT: Reset crash flag so app doesn't think it's perpetually crashing
        UserDefaults.standard.set(false, forKey: "CrashLogger_DidCrash")
        UserDefaults.standard.synchronize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Lightweight setup - don't block view loading
                    setupAppLightweight()
                }
                .task {
                    // Heavy initialization runs in background after view is visible
                    await initializeServicesInBackground()
                }
        }
    }

    // MARK: - Lightweight Setup (runs immediately, doesn't block UI)

    @MainActor
    private func setupAppLightweight() {
        debugLog("📱 setupAppLightweight starting...")

        // FIXED: Clean up potentially bloated UserDefaults data to prevent crashes
        cleanupBloatedUserDefaults()

        // Configure appearance (fast, doesn't involve network)
        configureAppearance()

        // Request location permission (async, doesn't block)
        LocationPermissionManager.shared.requestPermissionIfNeeded()

        debugLog("📱 setupAppLightweight complete")
    }

    /// FIXED: Clean up UserDefaults entries that may be too large and causing crashes
    /// This runs on app startup to prevent SIGTERM crashes from bloated data
    private func cleanupBloatedUserDefaults() {
        let maxSafeSize = 500_000  // 500KB - safe limit for UserDefaults
        let keysToCheck = [
            "stabilityEvents",
            "speedTestHistory",
            "diagnosticHistory",
            "vpn_snapshots",
            "vpn_mode_benchmark_history",
            "vpnConnectionHistory",
            "network_history_v2",
            "knownDevices",
            "deviceHistory_devices",
            "deviceHistory_events",
            "deviceHistory_alerts"
        ]

        for key in keysToCheck {
            if let data = UserDefaults.standard.data(forKey: key) {
                if data.count > maxSafeSize {
                    debugLog("⚠️ UserDefaults cleanup: '\(key)' is bloated (\(data.count) bytes) - removing")
                    UserDefaults.standard.removeObject(forKey: key)
                } else {
                    debugLog("✅ UserDefaults check: '\(key)' is OK (\(data.count) bytes)")
                }
            }
        }

        // Force synchronize to ensure cleanup is persisted
        UserDefaults.standard.synchronize()
        debugLog("🧹 UserDefaults cleanup complete")
    }

    // MARK: - Background Initialization (runs after UI is visible)

    @MainActor
    private func initializeServicesInBackground() async {
        debugLog("📱 initializeServicesInBackground starting...")

        // Wrap each service in its own error handling so one failure doesn't kill all

        // 1. Network Monitor
        debugLog("📱 Starting NetworkMonitorService...")
        NetworkMonitorService.shared.startMonitoring()
        debugLog("📱 NetworkMonitorService started")

        // 2. Diagnostic Engine
        debugLog("📱 Initializing DiagnosticEngine...")
        _ = DiagnosticEngine.shared
        debugLog("📱 DiagnosticEngine initialized")

        // 3. Streaming Diagnostic Service
        debugLog("📱 Initializing StreamingDiagnosticService...")
        _ = StreamingDiagnosticService.shared
        debugLog("📱 StreamingDiagnosticService initialized")

        // 4. VPN Engine
        debugLog("📱 Initializing VPNEngine...")
        _ = VPNEngine.shared
        debugLog("📱 VPNEngine initialized")

        // 5. Speed Test Engine
        debugLog("📱 Initializing SpeedTestEngine...")
        _ = SpeedTestEngine.shared
        debugLog("📱 SpeedTestEngine initialized")

        // 6. History Manager
        debugLog("📱 Initializing HistoryManager...")
        _ = HistoryManager.shared
        debugLog("📱 HistoryManager initialized")

        // 7. Connection Stability Monitor
        debugLog("📱 Starting ConnectionStabilityMonitor...")
        ConnectionStabilityMonitor.shared.startMonitoring()
        debugLog("📱 ConnectionStabilityMonitor started")

        debugLog("📱 All services initialization complete")

        // Fetch GeoIP data in background (don't await, let it complete whenever)
        Task.detached {
            _ = await GeoIPService.shared.fetchGeoIPInfo()
            debugLog("📱 GeoIP fetch complete")
        }
    }


    /// Configure global app appearance
    private func configureAppearance() {
        // Tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }
}

// MARK: - Service Access Documentation

/*
 ARCHITECTURE NOTES:

 1. SINGLETON PATTERN
    - All services use .shared for app-wide consistency
    - Initialized once in app init()
    - Accessed via .shared throughout the app

 2. DEPENDENCY INJECTION
    - ViewModels accept services via initializer
    - Default to .shared for convenience
    - Allows testing with mock services

    Example:
    class DashboardViewModel: ObservableObject {
        init(networkMonitor: NetworkMonitorService = .shared,
             geoIPService: GeoIPService = .shared) {
            self.networkMonitor = networkMonitor
            self.geoIPService = geoIPService
        }
    }

 3. STATE FLOW
    App → Services (init) → ViewModels (create) → Views (bind)

    Views observe ViewModels via @StateObject
    ViewModels observe Services via Combine or @Published
    Services interact with system APIs

 4. ASYNC ORCHESTRATION
    - All network operations use async/await
    - ViewModels orchestrate multi-step operations
    - Services perform individual tasks
    - UI updates happen on @MainActor

 5. ERROR HANDLING
    - Services throw or return Result types
    - ViewModels catch and set errorMessage
    - Views display errors via UI

 6. SERVICE RESPONSIBILITIES
    - NetworkMonitorService: Real-time network status
    - DiagnosticEngine: Full network diagnostics
    - StreamingDiagnosticService: Platform-specific tests
    - SpeedTestEngine: Download/upload speed tests
    - VPNEngine: VPN control and monitoring
    - GeoIPService: Public IP and geolocation
    - HistoryManager: Persistent storage

 7. VIEWMODEL RESPONSIBILITIES
    - Orchestrate step-by-step operations
    - Maintain UI state (@Published properties)
    - Provide computed properties for display
    - Handle errors gracefully
    - Update progress indicators

 8. VIEW RESPONSIBILITIES
    - Display data from ViewModel
    - Trigger actions (button taps)
    - Show loading states
    - Present errors to user
    - NO business logic

 9. NAVIGATION
    - TabView at root level
    - Each tab has independent navigation stack
    - Sheets used for modal presentations
    - Deep linking supported via environment

 10. PERFORMANCE
     - Heavy operations off main thread
     - Debounced network monitoring
     - Lazy loading where appropriate
     - Efficient state updates
 */
