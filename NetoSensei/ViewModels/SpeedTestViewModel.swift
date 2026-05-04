//
//  SpeedTestViewModel.swift
//  NetoSensei
//
//  FIXED: Proper Task.detached pattern, guaranteed UI updates
//  Swift 6 concurrency compliant - Updated 2025-12-17
//

import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor
class SpeedTestViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var result: SpeedTestResult?
    @Published var history: [SpeedTestResult] = []
    @Published var isRunning = false
    @Published var progress: Double = 0.0
    @Published var errorMessage: String?
    @Published var currentPhase: SpeedTestEngine.TestPhase = .idle
    @Published var currentTest: String = ""

    // MARK: - Services
    // FIXED: Removed nonisolated - these are @MainActor services

    private let speedTestEngine: SpeedTestEngine
    private let historyManager: HistoryManager
    private let networkMonitor: NetworkMonitorService

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Task Management
    nonisolated(unsafe) private var currentSpeedTestTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        self.speedTestEngine = SpeedTestEngine.shared
        self.historyManager = HistoryManager.shared
        self.networkMonitor = NetworkMonitorService.shared
        loadHistory()

        // Observe speed test engine progress
        speedTestEngine.$progress
            .receive(on: DispatchQueue.main)
            .assign(to: &$progress)

        speedTestEngine.$currentPhase
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentPhase)

        speedTestEngine.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRunning)
    }

    init(speedTestEngine: SpeedTestEngine, historyManager: HistoryManager, networkMonitor: NetworkMonitorService) {
        self.speedTestEngine = speedTestEngine
        self.historyManager = historyManager
        self.networkMonitor = networkMonitor
        loadHistory()

        // Observe speed test engine progress
        speedTestEngine.$progress
            .receive(on: DispatchQueue.main)
            .assign(to: &$progress)

        speedTestEngine.$currentPhase
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentPhase)

        speedTestEngine.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRunning)
    }

    private func loadHistory() {
        history = historyManager.getSpeedTestHistory()
    }

    // MARK: - Run Speed Test (FIXED: Proper async pattern with cancellation support)

    func runSpeedTest() {
        debugLog("🚀 SpeedTestViewModel: Starting speed test")

        // Cancel any existing speed test
        currentSpeedTestTask?.cancel()

        // Disable idle timer to prevent screen from turning off during test
        UIApplication.shared.isIdleTimerDisabled = true

        // Update UI: Starting
        isRunning = true
        progress = 0.0
        errorMessage = nil
        result = nil

        // Use Task with weak self to prevent retain cycles and allow cancellation
        currentSpeedTestTask = Task { [weak self] in
            guard let self = self else {
                await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
                return
            }

            defer {
                // Re-enable idle timer when test completes
                Task { @MainActor in
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }

            // Check for cancellation before starting
            guard !Task.isCancelled else { return }

            // Run actual speed test in background (nonisolated)
            let final = await speedTestEngine.runSpeedTest()

            // Check for cancellation before updating UI
            guard !Task.isCancelled else { return }

            debugLog("✅ SpeedTestViewModel: Got result - Download: \(final.downloadSpeed) Mbps")

            // Update UI: Complete (already on MainActor)
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                debugLog("📱 Updating UI...")
                self.result = final
                self.history.insert(final, at: 0)
                self.isRunning = false

                // Haptic feedback on completion
                if final.downloadSpeed > 0 {
                    HapticFeedback.success()
                } else {
                    HapticFeedback.error()
                }

                // Save to history (non-blocking - runs in background)
                self.historyManager.addSpeedTest(final)

                // Save to network history timeline for charts
                let networkStatus = self.networkMonitor.currentStatus
                let healthScore: Int
                switch final.quality {
                case .excellent: healthScore = 95
                case .good: healthScore = 80
                case .fair: healthScore = 60
                case .poor: healthScore = 40
                }

                // Capture WiFi and VPN context for history
                let vpnResult = SmartVPNDetector.shared.detectionResult
                let vpnServerLocation = vpnResult?.publicCity ?? vpnResult?.publicCountry

                let historyEntry = NetworkHistoryEntry(
                    healthScore: healthScore,
                    downloadSpeed: final.downloadSpeed,
                    uploadSpeed: final.uploadSpeed,
                    latency: final.ping,
                    gatewayLatency: networkStatus.router.latency ?? 0,
                    dnsLatency: networkStatus.dns.latency ?? 0,
                    jitter: final.jitter,
                    packetLoss: final.packetLoss,
                    vpnActive: networkStatus.vpn.isActive,
                    vpnOverhead: networkStatus.vpn.tunnelLatency,
                    rootCause: "Speed Test",
                    connectionType: networkStatus.connectionType?.displayName ?? "Unknown",
                    wifiSSID: networkStatus.wifi.ssid,
                    wifiBSSID: networkStatus.wifi.bssid,
                    vpnServerLocation: vpnServerLocation,
                    entryType: .speedTest
                )
                NetworkHistoryManager.shared.addEntry(historyEntry)

                debugLog("✅ SpeedTestViewModel: UI updated with results")
            }
        }
    }

    func cancelSpeedTest() {
        currentSpeedTestTask?.cancel()
        currentSpeedTestTask = nil
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - History Management

    func clearHistory() {
        historyManager.clearSpeedTestHistory()
        loadHistory()
    }

    func exportHistory() -> String {
        return historyManager.exportSpeedTestHistory()
    }

    func reset() {
        cancelSpeedTest()
        result = nil
        errorMessage = nil
        progress = 0.0
        currentPhase = .idle
        currentTest = ""
    }

    deinit {
        currentSpeedTestTask?.cancel()
    }

    // MARK: - Computed Properties

    var hasResult: Bool {
        result != nil
    }

    var downloadSpeedFormatted: String {
        guard let result = result else { return "0.0 Mbps" }
        return String(format: "%.1f Mbps", result.downloadSpeed)
    }

    var uploadSpeedFormatted: String {
        guard let result = result else { return "0.0 Mbps" }
        return String(format: "%.1f Mbps", result.uploadSpeed)
    }

    var pingFormatted: String {
        guard let result = result else { return "0 ms" }
        return String(format: "%.0f ms", result.ping)
    }

    var jitterFormatted: String {
        guard let result = result else { return "0 ms" }
        return String(format: "%.0f ms", result.jitter)
    }

    var packetLossFormatted: String {
        guard let result = result else { return "0.0%" }
        return String(format: "%.1f%%", result.packetLoss)
    }

    var qualityRating: SpeedTestResult.QualityRating {
        result?.quality ?? .poor
    }

    var qualityDescription: String {
        qualityRating.rawValue
    }

    var isStreamingCapable: Bool {
        result?.isStreamingCapable ?? false
    }

    var recommendedVideoQuality: String {
        result?.recommendedVideoQuality ?? "Unknown"
    }

    var phaseDescription: String {
        switch currentPhase {
        case .idle: return "Ready"
        case .findingServer: return "Finding best server..."
        case .testingPing: return "Testing latency..."
        case .testingDownload: return "Testing download speed..."
        case .testingUpload: return "Testing upload speed..."
        case .complete: return "Complete!"
        }
    }

    var hasHistory: Bool {
        !history.isEmpty
    }

    var historyCount: Int {
        history.count
    }

    var averageDownloadSpeed: String {
        guard let avg = historyManager.getAverageDownloadSpeed() else { return "N/A" }
        return String(format: "%.1f Mbps", avg)
    }

    var averageUploadSpeed: String {
        guard let avg = historyManager.getAverageUploadSpeed() else { return "N/A" }
        return String(format: "%.1f Mbps", avg)
    }

    var averagePing: String {
        guard let avg = historyManager.getAveragePing() else { return "N/A" }
        return String(format: "%.0f ms", avg)
    }

    func handleError(_ error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.isRunning = false
            self.progress = 0.0
            self.currentPhase = .idle
        }
    }
}
