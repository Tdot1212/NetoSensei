//
//  MeasurementValidityTracker.swift
//  NetoSensei
//
//  Tracks consecutive successes/failures for DNS, gateway, and external probes,
//  so the UI can require multiple consecutive failures before showing alarming
//  messages like "DNS Resolution Failed" or "Router Unreachable".
//
//  Background: a single timed-out probe used to flip the dashboard into a
//  panic state (issues, recommendations, "Poor" score). That created false
//  alarms while the user was clearly browsing fine. This tracker is the
//  debounce layer between raw probe results and user-visible problem cards.
//

import Foundation

@MainActor
final class MeasurementValidityTracker: ObservableObject {
    static let shared = MeasurementValidityTracker()

    private struct ProbeState {
        var consecutiveFailures: Int = 0
        var lastSuccessAt: Date?
    }

    private var dns = ProbeState()
    private var gateway = ProbeState()
    private var external = ProbeState()

    /// Number of consecutive failures required before declaring a hard problem.
    /// 2 means: a single hiccup is forgiven, two in a row trips the alarm.
    private let failureThreshold = 2

    /// How recently (in seconds) a probe must have succeeded for us to consider
    /// the subsystem "currently working" — used to suppress alarms while the
    /// user is clearly online.
    private let recentSuccessWindow: TimeInterval = 60

    private init() {}

    // MARK: - Recording

    func recordDNS(success: Bool) {
        record(success: success, into: &dns)
    }

    func recordGateway(success: Bool) {
        record(success: success, into: &gateway)
    }

    func recordExternal(success: Bool) {
        record(success: success, into: &external)
    }

    /// Convenience: feed a NetworkStatus snapshot in one shot.
    func ingest(_ status: NetworkStatus) {
        // DNS: success means we have a real (non-sentinel) latency AND lookupSuccess.
        recordDNS(success: status.dns.lookupSuccess && status.dns.displayableLatency != nil)
        // Gateway: success means we measured a real latency to it.
        recordGateway(success: status.router.displayableLatency != nil)
        // External: success means reachable AND we either pinged or HTTP-tested OK.
        let externalOK = status.internet.isReachable &&
            (status.internet.externalPingSuccess || status.internet.httpTestSuccess)
        recordExternal(success: externalOK)
    }

    private func record(success: Bool, into state: inout ProbeState) {
        if success {
            state.consecutiveFailures = 0
            state.lastSuccessAt = Date()
        } else {
            state.consecutiveFailures += 1
        }
    }

    // MARK: - Queries (used by UI / recommendation engines)

    /// True iff DNS has failed enough times in a row AND nothing recently succeeded.
    /// Use this to gate "DNS Resolution Failed" alerts.
    var dnsHasHardFailure: Bool {
        hardFailure(dns)
    }

    /// True iff the gateway has failed enough times in a row AND nothing recently succeeded.
    /// Use this to gate "Router Unreachable" alerts.
    var gatewayHasHardFailure: Bool {
        hardFailure(gateway)
    }

    var externalHasHardFailure: Bool {
        hardFailure(external)
    }

    private func hardFailure(_ state: ProbeState) -> Bool {
        guard state.consecutiveFailures >= failureThreshold else { return false }
        // If we successfully measured within the window, don't alarm.
        if let last = state.lastSuccessAt,
           Date().timeIntervalSince(last) < recentSuccessWindow {
            return false
        }
        return true
    }
}
