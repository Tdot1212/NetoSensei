//
//  AppLoadTracker.swift
//  NetoSensei
//
//  Accuracy audit follow-up (Commit 7): "the app must not measure itself".
//
//  NetoSensei generates network load on purpose — a saturating speed test,
//  the Deep Scan's probe storm, the Combined check's certificate fetches to
//  hosts that may be blocked from this country. While that load runs, the
//  passive monitor's own probes contend with it: router latency spikes,
//  packet loss appears, `overallHealth` swings green→red→green. Those swings
//  describe the app's traffic, not the network, and the stability monitor
//  was recording them as "Quality Degraded / Improved" events — around a
//  speed test that measured 152 Mbps and 0 % loss.
//
//  Every self-generated load source marks itself here (begin/end, reference
//  counted). Consumers that judge stability ask `isActive` and skip samples
//  taken under load. This is a suppression of a KNOWN measurement artifact,
//  not a widened threshold: samples taken while the app is idle are judged
//  exactly as before.
//

import Foundation

@MainActor
final class AppLoadTracker: ObservableObject {
    static let shared = AppLoadTracker()

    /// Names of the load sources currently running (a source may run once).
    @Published private(set) var activeSources: Set<String> = []
    /// When the last source ended — lets a consumer skip the first sample
    /// after load stops (the "recovery" swing is the same artifact).
    private(set) var lastEndedAt: Date?

    private init() {}

    var isActive: Bool { !activeSources.isEmpty }

    /// True if load is active now or ended within `grace` seconds.
    func isActiveOrRecent(grace: TimeInterval) -> Bool {
        if isActive { return true }
        guard let ended = lastEndedAt else { return false }
        return Date().timeIntervalSince(ended) < grace
    }

    func begin(_ source: String) {
        activeSources.insert(source)
    }

    func end(_ source: String) {
        guard activeSources.remove(source) != nil else { return }
        lastEndedAt = Date()
    }

    /// Run `body` with `source` marked as active load for its duration.
    func track<T>(_ source: String, _ body: () async -> T) async -> T {
        begin(source)
        defer { end(source) }
        return await body()
    }
}
