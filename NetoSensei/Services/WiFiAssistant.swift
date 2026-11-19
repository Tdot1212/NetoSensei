import Foundation

/// A comparison of repeated application-throughput measurements, not proof of causation.
struct WiFiSpeedComparison {
    let beforeMbps: Double
    let afterMbps: Double
    let changePercent: Double
    let rangesOverlap: Bool
    let beforeLatencyMs: Double?
    let afterLatencyMs: Double?
    var response: ResponseComparison? = nil

    struct ResponseComparison {
        struct Phase {
            let before: Double
            let after: Double
            let rangesOverlap: Bool

            init?(before: [Double], after: [Double], beforeCount: Int, afterCount: Int) {
                guard before.count == beforeCount, after.count == afterCount,
                      let b = HTTPSResponsiveness.median(before), let a = HTTPSResponsiveness.median(after),
                      let bMin = before.min(), let bMax = before.max(), let aMin = after.min(), let aMax = after.max() else { return nil }
                self.before = b
                self.after = a
                rangesOverlap = max(bMin, aMin) <= min(bMax, aMax)
            }

            var assessment: String {
                if rangesOverlap { return "Samples overlap · improvement inconclusive" }
                return after < before ? "Faster in this comparison" : "Slower in this comparison"
            }
        }

        let idle: Phase?
        let download: Phase?
        let upload: Phase?

        init?(before: [SpeedTestResult], after: [SpeedTestResult]) {
            guard let endpoint = before.first?.responsiveness?.endpoint,
                  (before + after).allSatisfy({ $0.responsiveness?.endpoint == endpoint }) else { return nil }
            func phase(_ metric: KeyPath<HTTPSResponsiveness, Double?>) -> Phase? {
                Phase(before: before.compactMap { $0.responsiveness?[keyPath: metric] },
                      after: after.compactMap { $0.responsiveness?[keyPath: metric] },
                      beforeCount: before.count, afterCount: after.count)
            }
            idle = phase(\.idleMs)
            download = phase(\.downloadMs)
            upload = phase(\.uploadMs)
        }
    }

    static func evaluate(before: [SpeedTestResult], after: [SpeedTestResult],
                         compareVPNExits: Bool = false) -> WiFiSpeedComparison? {
        let all = before + after
        guard before.count >= 3, after.count >= 3, let reference = before.first, reference.connectionType == "WiFi",
              let ssid = reference.networkSSID, !ssid.isEmpty,
              let server = reference.serverUsed, !server.isEmpty,
              let subnet = reference.localSubnet, !subnet.isEmpty,
              all.allSatisfy({
                  $0.testUnavailableReason == nil && $0.downloadSpeed.isFinite && $0.downloadSpeed > 0 &&
                  $0.networkSSID == ssid && $0.localSubnet == subnet &&
                  $0.connectionType == reference.connectionType && $0.vpnActive == reference.vpnActive &&
                  $0.serverUsed == server
              }), let secondReference = after.first,
              before.allSatisfy({ $0.ipAddress == reference.ipAddress && $0.publicCountry == reference.publicCountry }),
              after.allSatisfy({ $0.ipAddress == secondReference.ipAddress && $0.publicCountry == secondReference.publicCountry })
        else { return nil }
        if compareVPNExits {
            guard reference.vpnActive, let oldExit = reference.ipAddress, !oldExit.isEmpty,
                  let newExit = secondReference.ipAddress, !newExit.isEmpty, oldExit != newExit else { return nil }
        } else if reference.ipAddress != secondReference.ipAddress || reference.publicCountry != secondReference.publicCountry {
            return nil
        }
        let b = before.map(\.downloadSpeed), a = after.map(\.downloadSpeed)
        guard let bm = MeasurementStatistics.median(b), let am = MeasurementStatistics.median(a),
              let bMin = b.min(), let bMax = b.max(), let aMin = a.min(), let aMax = a.max() else { return nil }
        let beforePings = before.compactMap(\.ping).filter { $0.isFinite && $0 > 0 }
        let afterPings = after.compactMap(\.ping).filter { $0.isFinite && $0 > 0 }
        let hasComparableLatency = beforePings.count == before.count && afterPings.count == after.count
        return WiFiSpeedComparison(beforeMbps: bm, afterMbps: am,
            changePercent: (am / bm - 1) * 100,
            rangesOverlap: max(bMin, aMin) <= min(bMax, aMax),
            beforeLatencyMs: hasComparableLatency ? MeasurementStatistics.median(beforePings) : nil,
            afterLatencyMs: hasComparableLatency ? MeasurementStatistics.median(afterPings) : nil,
            response: ResponseComparison(before: before, after: after))
    }
}

@MainActor
final class WiFiAssistant: ObservableObject {
    @Published var isRunning = false
    @Published var statusText = "Ready to check your Wi-Fi"
    @Published var errorMessage: String?
    @Published var before: [SpeedTestResult] = []
    @Published var after: [SpeedTestResult] = []
    @Published var checkedAt: Date?
    @Published var recognizedIPs = Set<String>()
    @Published var deviceLabels: [String: String] = [:]
    @Published private(set) var inventory: WiFiDeviceInventory?
    @Published private(set) var scanStatus: NetworkStatus?
    private(set) var scanPath: Date?
    @Published var compareVPNExits = false
    @Published private(set) var quickResult: SpeedTestResult?
    @Published var actionHistory: [String] = []
    private var operation: Task<Void, Never>?

    var comparison: WiFiSpeedComparison? {
        WiFiSpeedComparison.evaluate(before: before, after: after, compareVPNExits: compareVPNExits)
    }

    func scan() {
        guard !isRunning, !NetworkDeviceDiscovery.shared.isScanning else { return }
        isRunning = true
        errorMessage = nil
        clearScan()
        operation = Task {
            defer { finishOperation() }
            statusText = "Refreshing network measurements…"
            await NetworkMonitorService.shared.updateNetworkStatus(force: true)
            guard NetworkMonitorService.shared.currentStatus.wifi.isConnected else {
                errorMessage = "Connect to Wi-Fi to check your local network."
                statusText = "Wi-Fi required"
                return
            }
            statusText = "Looking for responding devices…"
            let path = ExitPath.lastPathChange
            let discovery = NetworkDeviceDiscovery.shared
            await discovery.scanNetwork()
            statusText = "Matching advertised names…"
            guard let observed = await WiFiDeviceInventory.currentDiscovery(),
                  !Task.isCancelled, path == ExitPath.lastPathChange else {
                statusText = "Connection changed · check again"
                return
            }
            scanPath = path
            scanStatus = NetworkMonitorService.shared.currentStatus
            inventory = observed
            checkedAt = Date()
            statusText = "Checks complete · discovery is partial"
            actionHistory.insert("Completed a local network check", at: 0)
        }
    }

    func checkResponsiveness() {
        guard !isRunning, !SpeedTestEngine.shared.isRunning else { return }
        guard NetworkMonitorService.shared.currentStatus.connectionType == .wifi else {
            errorMessage = "Use Wi-Fi as the active connection before measuring."
            return
        }
        isRunning = true
        errorMessage = nil
        quickResult = nil
        statusText = "Measuring responsiveness…"
        operation = Task {
            defer { finishOperation() }
            let result = await SpeedTestEngine.shared.runSpeedTest(measureResponsiveness: true)
            guard !Task.isCancelled else { return }
            if let error = result.testUnavailableReason {
                errorMessage = error
                statusText = "Measurement incomplete"
                return
            }
            quickResult = result
            statusText = "Responsiveness check complete"
        }
    }

    func measureBaseline() { measure(isBaseline: true) }
    func measureAfter() { measure(isBaseline: false) }

    private func measure(isBaseline: Bool) {
        guard !isRunning, !SpeedTestEngine.shared.isRunning else { return }
        guard NetworkMonitorService.shared.currentStatus.connectionType == .wifi else {
            errorMessage = "Use Wi-Fi as the active connection before measuring."
            return
        }
        guard isBaseline || before.count >= 3 else { return }
        isRunning = true
        errorMessage = nil
        // Invalidate the previous pair before starting, including on failure.
        if isBaseline { before = [] }
        after = []
        operation = Task {
            defer { finishOperation() }
            var samples: [SpeedTestResult] = []
            for index in 1...3 {
                statusText = "\(isBaseline ? "Before" : "After") measurement \(index) of 3…"
                let server = isBaseline ? samples.first?.serverUsed : before.first?.serverUsed
                let result = await SpeedTestEngine.shared.runSpeedTest(
                    measureResponsiveness: true, comparisonServer: server
                )
                guard !Task.isCancelled else { return }
                guard result.testUnavailableReason == nil, result.downloadSpeed.isFinite, result.downloadSpeed > 0 else {
                    errorMessage = result.testUnavailableReason ?? "Download measurement failed. No comparison was recorded."
                    statusText = "Measurement incomplete"
                    return
                }
                samples.append(result)
            }
            // Apply the same compatibility rules within a batch, too.
            guard WiFiSpeedComparison.evaluate(before: samples, after: samples) != nil else {
                errorMessage = "The network identity or test server changed, or the Wi-Fi name is unavailable. Enable Wi-Fi name access and repeat on one network."
                statusText = "Measurements cannot be compared"
                return
            }
            if isBaseline { before = samples } else { after = samples }
            actionHistory.insert("Completed three \(isBaseline ? "before" : "after") speed measurements", at: 0)
            if !isBaseline && comparison == nil {
                errorMessage = compareVPNExits
                    ? "The VPN exit change could not be verified on the same Wi-Fi and test server."
                    : "The before and after paths differ. Repeat the baseline on the current Wi-Fi, VPN path and test server."
            }
            statusText = "Measurements complete"
        }
    }

    private func finishOperation() {
        if Task.isCancelled { statusText = "Check cancelled" }
        isRunning = false
        operation = nil
    }

    private func clearScan() {
        inventory = nil
        scanStatus = nil
        scanPath = nil
        checkedAt = nil
        recognizedIPs.removeAll()
        deviceLabels.removeAll()
    }

    func cancel() {
        operation?.cancel()
        statusText = "Stopping the current check…"
    }

    func reset() {
        guard !isRunning else { return }
        quickResult = nil; before = []; after = []; compareVPNExits = false; clearScan(); actionHistory.removeAll()
        errorMessage = nil; statusText = "Ready to check your Wi-Fi"
    }
}
