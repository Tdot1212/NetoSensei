//
//  HistoryManager.swift
//  NetoSensei
//
//  History logging and persistence manager
//

import Foundation

@MainActor
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published var speedTestHistory: [SpeedTestResult] = []
    @Published var diagnosticHistory: [DiagnosticHistoryEntry] = []

    private let userDefaults = UserDefaults.standard
    private let speedTestKey = "speedTestHistory"
    private let diagnosticKey = "diagnosticHistory"
    private let maxHistoryItems = 100

    private init() {
        loadHistory()
    }

    // MARK: - Speed Test History

    func addSpeedTest(_ result: SpeedTestResult) {
        speedTestHistory.insert(result, at: 0)

        // Keep only recent results
        if speedTestHistory.count > maxHistoryItems {
            speedTestHistory = Array(speedTestHistory.prefix(maxHistoryItems))
        }

        // FIXED: Use safe save to prevent UserDefaults crash from large data
        let historyToSave = speedTestHistory
        Task.detached {
            UserDefaults.standard.setSafe(historyToSave, forKey: "speedTestHistory", maxItems: 50)
        }
    }

    func getSpeedTestHistory() -> [SpeedTestResult] {
        return speedTestHistory
    }

    func clearSpeedTestHistory() {
        speedTestHistory = []
        UserDefaults.standard.removeObject(forKey: "speedTestHistory")
    }

    // MARK: - Diagnostic History

    func addDiagnostic(_ result: DiagnosticResult) {
        let entry = DiagnosticHistoryEntry(from: result)
        diagnosticHistory.insert(entry, at: 0)

        // Keep only recent results
        if diagnosticHistory.count > maxHistoryItems {
            diagnosticHistory = Array(diagnosticHistory.prefix(maxHistoryItems))
        }

        // FIXED: Use safe save to prevent UserDefaults crash from large data
        let historyToSave = diagnosticHistory
        Task.detached {
            UserDefaults.standard.setSafe(historyToSave, forKey: "diagnosticHistory", maxItems: 50)
        }
    }

    func getDiagnosticHistory() -> [DiagnosticHistoryEntry] {
        return diagnosticHistory
    }

    func clearDiagnosticHistory() {
        diagnosticHistory = []
        UserDefaults.standard.removeObject(forKey: "diagnosticHistory")
    }

    // MARK: - Clear All

    func clearAllHistory() {
        clearSpeedTestHistory()
        clearDiagnosticHistory()
    }

    // MARK: - Statistics

    func getAverageDownloadSpeed() -> Double? {
        guard !speedTestHistory.isEmpty else { return nil }
        let total = speedTestHistory.reduce(0.0) { $0 + $1.downloadSpeed }
        return total / Double(speedTestHistory.count)
    }

    func getAverageUploadSpeed() -> Double? {
        guard !speedTestHistory.isEmpty else { return nil }
        let total = speedTestHistory.reduce(0.0) { $0 + $1.uploadSpeed }
        return total / Double(speedTestHistory.count)
    }

    func getAveragePing() -> Double? {
        guard !speedTestHistory.isEmpty else { return nil }
        let total = speedTestHistory.reduce(0.0) { $0 + $1.ping }
        return total / Double(speedTestHistory.count)
    }

    func getRecentIssues(days: Int = 7) -> [DiagnosticHistoryEntry] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return diagnosticHistory.filter { $0.timestamp >= cutoffDate }
    }

    // MARK: - Persistence

    private func loadHistory() {
        // Load speed test history
        if let data = userDefaults.data(forKey: speedTestKey),
           let decoded = try? JSONDecoder().decode([SpeedTestResult].self, from: data) {
            speedTestHistory = decoded
        }

        // Load diagnostic history
        if let data = userDefaults.data(forKey: diagnosticKey),
           let decoded = try? JSONDecoder().decode([DiagnosticHistoryEntry].self, from: data) {
            diagnosticHistory = decoded
        }
    }

    // MARK: - Export

    func exportSpeedTestHistory() -> String {
        var csv = "Timestamp,Download (Mbps),Upload (Mbps),Ping (ms),Jitter (ms),Packet Loss (%),Connection Type,VPN Active\n"

        for test in speedTestHistory {
            let timestamp = ISO8601DateFormatter().string(from: test.timestamp)
            csv += "\(timestamp),\(test.downloadSpeed),\(test.uploadSpeed),\(test.ping),\(test.jitter),\(test.packetLoss),\(test.connectionType),\(test.vpnActive)\n"
        }

        return csv
    }

    func exportDiagnosticHistory() -> String {
        var csv = "Timestamp,Summary,Issue Count,Primary Issue,Status\n"

        for entry in diagnosticHistory {
            let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
            let escapedSummary = entry.summary.replacingOccurrences(of: ",", with: ";")
            csv += "\(timestamp),\(escapedSummary),\(entry.issueCount),\(entry.primaryIssueCategory),\(entry.overallStatus)\n"
        }

        return csv
    }
}
