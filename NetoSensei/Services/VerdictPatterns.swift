//
//  VerdictPatterns.swift
//  NetoSensei
//
//  Diagnosis v2 — named diagnostic patterns (design §E).
//  Commit 2 ships the file with no matchers; commit 3 fills it in.
//

import Foundation

enum VerdictPatterns {
    /// Each matcher is a pure function of coverage + context → Finding?.
    /// Order = priority (most specific first). Commit 3 populates this list.
    static var matchers: [(Coverage, VerdictContext) -> Finding?] { [] }

    static func match(coverage: Coverage, context: VerdictContext) -> [Finding] {
        matchers.compactMap { $0(coverage, context) }
    }
}
