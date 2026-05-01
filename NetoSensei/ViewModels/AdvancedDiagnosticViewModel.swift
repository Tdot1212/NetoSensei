//
//  AdvancedDiagnosticViewModel.swift
//  NetoSensei
//
//  ViewModel for Advanced Diagnostics - NEVER does async work directly
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class AdvancedDiagnosticViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var summary: AdvancedDiagnosticSummary?
    @Published var isRunning = false
    @Published var progress: Double = 0.0
    @Published var currentTask: String = ""
    @Published var error: String?

    // MARK: - Task Management
    // Using nonisolated(unsafe) to allow cleanup in deinit
    nonisolated(unsafe) private var currentDiagnosticTask: Task<Void, Never>?

    // MARK: - Run Full Diagnostics

    func runFullDiagnostics(targetHost: String = "www.google.com") {
        print("🔧 [AdvancedDiagnostics] Starting full diagnostics for \(targetHost)...")

        // Cancel any existing diagnostic task
        currentDiagnosticTask?.cancel()

        isRunning = true
        progress = 0.0
        error = nil
        summary = nil

        // Disable idle timer to prevent screen from turning off
        UIApplication.shared.isIdleTimerDisabled = true

        currentDiagnosticTask = Task { [weak self] in
            guard let self = self else {
                await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
                return
            }
            defer {
                // Re-enable idle timer when diagnostics complete
                UIApplication.shared.isIdleTimerDisabled = false
            }

            print("🔧 [AdvancedDiagnostics] Calling DiagnosticsEngine.runAdvancedDiagnostics()...")
            let result = await DiagnosticsEngine.shared.runAdvancedDiagnostics(
                targetHost: targetHost,
                onProgress: { [weak self] progress, task in
                    print("🔧 [AdvancedDiagnostics] Progress: \(progress) - \(task)")
                    // Use MainActor.run instead of nested Task to avoid race conditions
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.progress = progress
                        self.currentTask = task
                    }
                }
            )

            // MUST update UI on main actor
            await MainActor.run {
                print("🔧 [AdvancedDiagnostics] Diagnostics complete! Threat level: \(result.overallThreatLevel)")
                self.summary = result
                self.isRunning = false
                self.progress = 1.0
                self.currentTask = "Complete"
            }
        }
    }

    // MARK: - Run Security-Only Scan

    func runSecurityScan() {
        // Cancel any existing diagnostic task
        currentDiagnosticTask?.cancel()

        isRunning = true
        progress = 0.0
        error = nil
        summary = nil

        // Disable idle timer to prevent screen from turning off
        UIApplication.shared.isIdleTimerDisabled = true

        currentDiagnosticTask = Task { [weak self] in
            guard let self = self else {
                await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
                return
            }
            defer {
                // Re-enable idle timer when scan completes
                UIApplication.shared.isIdleTimerDisabled = false
            }

            let result = await DiagnosticsEngine.shared.runSecurityScan(
                onProgress: { [weak self] progress, task in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.progress = progress
                        self.currentTask = task
                    }
                }
            )

            await MainActor.run {
                self.summary = result
                self.isRunning = false
                self.progress = 1.0
                self.currentTask = "Complete"
            }
        }
    }

    // MARK: - Run Performance Test

    func runPerformanceTest(targetHost: String = "www.google.com") {
        // Cancel any existing diagnostic task
        currentDiagnosticTask?.cancel()

        isRunning = true
        progress = 0.0
        error = nil
        summary = nil

        // Disable idle timer to prevent screen from turning off
        UIApplication.shared.isIdleTimerDisabled = true

        currentDiagnosticTask = Task { [weak self] in
            guard let self = self else {
                await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
                return
            }
            defer {
                // Re-enable idle timer when test completes
                UIApplication.shared.isIdleTimerDisabled = false
            }

            let result = await DiagnosticsEngine.shared.runPerformanceTest(
                targetHost: targetHost,
                onProgress: { [weak self] progress, task in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.progress = progress
                        self.currentTask = task
                    }
                }
            )

            await MainActor.run {
                self.summary = result
                self.isRunning = false
                self.progress = 1.0
                self.currentTask = "Complete"
            }
        }
    }

    // MARK: - Helper Methods

    func reset() {
        cancel()
        summary = nil
        progress = 0.0
        currentTask = ""
        error = nil
        isRunning = false
    }

    func cancel() {
        currentDiagnosticTask?.cancel()
        currentDiagnosticTask = nil
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    deinit {
        currentDiagnosticTask?.cancel()
    }
}
