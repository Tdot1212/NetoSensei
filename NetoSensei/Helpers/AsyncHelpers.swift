//
//  AsyncHelpers.swift
//  NetoSensei
//
//  Async utilities for non-blocking operations
//

import Foundation

// MARK: - Timeout Helper

enum TimeoutError: Error {
    case timedOut
}

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timedOut
        }

        // Safe unwrap to prevent crash if task group is cancelled
        guard let result = try await group.next() else {
            group.cancelAll()
            throw TimeoutError.timedOut
        }
        group.cancelAll()
        return result
    }
}
