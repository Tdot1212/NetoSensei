//
//  LegacySpeedRecordMigration.swift
//  NetoSensei
//
//  Accuracy audit Phase 4 (Trends honesty) — one-time cleanup of speed-test
//  records written before Phase 3.
//
//  WHY A MIGRATION (rewrite on disk) RATHER THAN READ-TIME STRIPPING:
//  - The sentinel values are not a *format* problem, they are *wrong data*.
//    Fixing them inside Codable would leave the wrong bytes on disk forever
//    and make every future reader (exports, AI snapshots, new views) rely on
//    remembering to strip again. Phase 3 already had to add three separate
//    `< 999` guards downstream; that is the pattern this replaces.
//  - Rewriting once makes the persisted truth match the Phase 3 contract
//    (nil = unmeasurable), so the guards become redundant defence, not load-
//    bearing logic.
//
//  RULES (see the audit and the Phase 3 commit 5c65ac8):
//  - ping >= 999   → nil. 999.0 was an explicit "all probes timed out"
//    sentinel returned from two code paths; it was never a measurement.
//    jitter is nil'd with it (Phase 3 contract: jitter is nil when ping is).
//  - packetLoss >= 100 → nil. 100 was produced BOTH by a literal sentinel in
//    the timeout catch AND by the old methodology counting every 1-second
//    HTTP-HEAD timeout as a lost packet next to a working 20–45 s transfer.
//    The two cases cannot be told apart in the stored data, and the old
//    method could not distinguish "blocked" from "lost", so the methodology
//    itself was invalid: per accuracy-first, a value that might be a
//    sentinel is not a measurement. nil, not 100.
//  - quality is recomputed from the sanitized values, because the stored
//    rating was derived from the sentinel (999 ms → "Poor" on a run that
//    moved 70 Mbps).
//
//  PROPERTIES: pure, idempotent (a second pass changes nothing), and the
//  caller logs the count so the one-time rewrite is visible in the device log.
//

import Foundation

enum LegacySpeedRecordMigration {

    static let pingSentinel: Double = 999.0
    static let lossSentinel: Double = 100.0

    struct Outcome {
        let records: [SpeedTestResult]
        let changedCount: Int
    }

    /// Apply the sanitizing rules to every record. Untouched records are
    /// returned as-is (same id, same values); changed records keep their id
    /// and timestamp.
    static func apply(_ records: [SpeedTestResult]) -> Outcome {
        var changed = 0
        let out = records.map { record -> SpeedTestResult in
            guard let fixed = sanitize(record) else { return record }
            changed += 1
            return fixed
        }
        return Outcome(records: out, changedCount: changed)
    }

    /// Returns a corrected copy if the record carries legacy sentinels,
    /// nil if it is already clean.
    static func sanitize(_ record: SpeedTestResult) -> SpeedTestResult? {
        let pingIsSentinel = record.ping.map { $0 >= pingSentinel } ?? false
        let lossIsSentinel = record.packetLoss.map { $0 >= lossSentinel } ?? false
        guard pingIsSentinel || lossIsSentinel else { return nil }

        var fixed = record
        if pingIsSentinel {
            fixed.ping = nil
            fixed.jitter = nil
        }
        if lossIsSentinel {
            fixed.packetLoss = nil
        }
        fixed.quality = SpeedTestResult.QualityRating.from(
            downloadSpeed: fixed.downloadSpeed,
            ping: fixed.ping,
            packetLoss: fixed.packetLoss,
            vpnActive: fixed.vpnActive
        )
        return fixed
    }
}
