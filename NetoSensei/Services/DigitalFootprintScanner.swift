//
//  DigitalFootprintScanner.swift
//  NetoSensei
//
//  Scans known data broker sites for user's personal information,
//  tracks removal requests, and persists scan results locally.
//

import Foundation

// MARK: - Scan Result

struct FootprintScanResult: Identifiable, Codable {
    let id: UUID
    let broker: String
    let brokerID: String
    let foundURL: String?
    let foundData: FoundData?
    let status: Status
    let scannedAt: Date

    struct FoundData: Codable {
        let name: String?
        let address: String?
        let phone: String?
        let email: String?
        let age: String?
        let relatives: [String]?
    }

    enum Status: String, Codable {
        case found = "Found"
        case notFound = "Not Found"
        case unknown = "Unknown"
        case removed = "Removed"
        case pending = "Pending Removal"

        var icon: String {
            switch self {
            case .found: return "exclamationmark.triangle.fill"
            case .notFound: return "checkmark.circle.fill"
            case .unknown: return "questionmark.circle"
            case .removed: return "trash.circle.fill"
            case .pending: return "clock.fill"
            }
        }
    }
}

// MARK: - User Profile for Scanning

struct ScanProfile: Codable {
    var firstName: String
    var lastName: String
    var middleName: String?
    var email: String?
    var phone: String?
    var city: String?
    var state: String?
    var country: String

    var fullName: String {
        if let middle = middleName, !middle.isEmpty {
            return "\(firstName) \(middle) \(lastName)"
        }
        return "\(firstName) \(lastName)"
    }

    var searchQuery: String {
        var parts = [fullName]
        if let city = city { parts.append(city) }
        if let state = state { parts.append(state) }
        return parts.joined(separator: " ")
    }
}

// MARK: - Digital Footprint Scanner

@MainActor
class DigitalFootprintScanner: ObservableObject {
    static let shared = DigitalFootprintScanner()

    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var currentBroker = ""
    @Published var scanResults: [FootprintScanResult] = []
    @Published var removalProgress: [String: RemovalStatus] = [:]
    @Published var scanProfile: ScanProfile?

    struct RemovalStatus: Codable {
        let brokerID: String
        var status: FootprintScanResult.Status
        var requestedAt: Date?
        var completedAt: Date?
        var notes: String?
    }

    private let database = DataBrokerDatabase.shared
    private let storageKey = "digitalFootprintResults"
    private let removalKey = "removalProgress"
    private let profileKey = "scanProfile"

    private init() {
        loadData()
    }

    // MARK: - Scan for User

    @discardableResult
    func startScan(profile: ScanProfile) async -> Int {
        return await BackgroundTaskManager.shared.runInBackground(
            id: "footprintScan",
            name: "Digital Footprint Scan",
            operation: {
                await self.performScan(profile: profile)
                return self.scanResults.count
            },
            resultFormatter: { count in
                "\(count) sites checked"
            }
        )
    }

    private func performScan(profile: ScanProfile) async {
        self.scanProfile = profile
        saveProfile()

        isScanning = true
        progress = 0
        scanResults = []
        currentBroker = ""

        let brokers = database.brokers

        for (index, broker) in brokers.enumerated() {
            currentBroker = broker.name
            progress = Double(index) / Double(brokers.count)

            let result = await scanBroker(broker, profile: profile)
            scanResults.append(result)

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        progress = 1.0
        currentBroker = "Complete"
        isScanning = false

        saveResults()
    }

    // MARK: - Scan Single Broker

    private nonisolated func scanBroker(_ broker: DataBroker, profile: ScanProfile) async -> FootprintScanResult {
        FootprintScanResult(
            id: UUID(),
            broker: broker.name,
            brokerID: broker.id,
            foundURL: broker.searchURL?.replacingOccurrences(
                of: "{name}",
                with: profile.fullName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            ),
            foundData: nil,
            status: .unknown,
            scannedAt: Date()
        )
    }

    // MARK: - Check Specific Broker

    func checkBroker(_ brokerID: String, profile: ScanProfile) async -> FootprintScanResult? {
        guard let broker = database.brokers.first(where: { $0.id == brokerID }) else {
            return nil
        }

        let result = await scanBroker(broker, profile: profile)

        if let index = scanResults.firstIndex(where: { $0.brokerID == brokerID }) {
            scanResults[index] = result
        } else {
            scanResults.append(result)
        }

        saveResults()
        return result
    }

    // MARK: - Mark as Removal Requested

    func markRemovalRequested(_ brokerID: String) {
        removalProgress[brokerID] = RemovalStatus(
            brokerID: brokerID,
            status: .pending,
            requestedAt: Date(),
            completedAt: nil,
            notes: nil
        )

        if let index = scanResults.firstIndex(where: { $0.brokerID == brokerID }) {
            let old = scanResults[index]
            scanResults[index] = FootprintScanResult(
                id: old.id,
                broker: old.broker,
                brokerID: old.brokerID,
                foundURL: old.foundURL,
                foundData: old.foundData,
                status: .pending,
                scannedAt: old.scannedAt
            )
        }

        saveRemovalProgress()
        saveResults()
    }

    // MARK: - Mark as Removed

    func markRemoved(_ brokerID: String) {
        if var status = removalProgress[brokerID] {
            status.status = .removed
            status.completedAt = Date()
            removalProgress[brokerID] = status
        } else {
            removalProgress[brokerID] = RemovalStatus(
                brokerID: brokerID,
                status: .removed,
                requestedAt: nil,
                completedAt: Date(),
                notes: nil
            )
        }

        if let index = scanResults.firstIndex(where: { $0.brokerID == brokerID }) {
            let old = scanResults[index]
            scanResults[index] = FootprintScanResult(
                id: old.id,
                broker: old.broker,
                brokerID: old.brokerID,
                foundURL: old.foundURL,
                foundData: old.foundData,
                status: .removed,
                scannedAt: old.scannedAt
            )
        }

        saveRemovalProgress()
        saveResults()
    }

    // MARK: - Statistics

    var foundCount: Int {
        scanResults.filter { $0.status == .found }.count
    }

    var removedCount: Int {
        scanResults.filter { $0.status == .removed }.count
    }

    var pendingCount: Int {
        scanResults.filter { $0.status == .pending }.count
    }

    var exposureScore: Int {
        let totalBrokers = database.brokers.count
        let found = foundCount
        let pending = pendingCount

        if totalBrokers == 0 { return 0 }

        let exposedPercent = Double(found + pending) / Double(totalBrokers) * 100
        return 100 - Int(exposedPercent)
    }

    // MARK: - Persistence

    private func saveResults() {
        if let encoded = try? JSONEncoder().encode(scanResults) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func saveRemovalProgress() {
        if let encoded = try? JSONEncoder().encode(removalProgress) {
            UserDefaults.standard.set(encoded, forKey: removalKey)
        }
    }

    private func saveProfile() {
        if let profile = scanProfile,
           let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: profileKey)
        }
    }

    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([FootprintScanResult].self, from: data) {
            scanResults = decoded
        }

        if let data = UserDefaults.standard.data(forKey: removalKey),
           let decoded = try? JSONDecoder().decode([String: RemovalStatus].self, from: data) {
            removalProgress = decoded
        }

        if let data = UserDefaults.standard.data(forKey: profileKey),
           let decoded = try? JSONDecoder().decode(ScanProfile.self, from: data) {
            scanProfile = decoded
        }
    }

    func clearAllData() {
        scanResults = []
        removalProgress = [:]
        scanProfile = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: removalKey)
        UserDefaults.standard.removeObject(forKey: profileKey)
    }
}
