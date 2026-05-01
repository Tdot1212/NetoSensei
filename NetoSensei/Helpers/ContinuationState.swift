//
//  ContinuationState.swift
//  NetoSensei
//
//  Swift 6-safe continuation state management
//  Prevents data races when resuming continuations from multiple callbacks
//

import Foundation

/// Thread-safe state for managing continuation resume
/// Swift 6 requires proper isolation for mutable state in concurrent contexts
final class ContinuationState<T>: @unchecked Sendable {
    private var resumed = false
    private let lock = NSLock()

    /// Thread-safe check and set for resumed state
    /// Returns true if this is the first call (should resume), false otherwise
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if resumed {
            return false
        }
        resumed = true
        return true
    }

    /// Check if already resumed (thread-safe)
    var isResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resumed
    }
}

/// Helper for timeout-based continuation patterns (non-throwing)
/// Safely handles race between completion and timeout
final class TimeoutContinuation<T: Sendable>: @unchecked Sendable {
    private let continuation: CheckedContinuation<T, Never>
    private let state = ContinuationState<T>()

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    /// Resume with value if not already resumed
    func resume(returning value: T) {
        if state.tryResume() {
            continuation.resume(returning: value)
        }
    }

    /// Check if already resumed
    var isResumed: Bool {
        state.isResumed
    }
}

/// Helper for timeout-based throwing continuation patterns
/// Safely handles race between completion and timeout
final class ThrowingTimeoutContinuation<T: Sendable>: @unchecked Sendable {
    private let continuation: CheckedContinuation<T, Error>
    private let state = ContinuationState<T>()

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    /// Resume with value if not already resumed
    func resume(returning value: T) {
        if state.tryResume() {
            continuation.resume(returning: value)
        }
    }

    /// Resume with error if not already resumed
    func resume(throwing error: Error) {
        if state.tryResume() {
            continuation.resume(throwing: error)
        }
    }

    /// Check if already resumed
    var isResumed: Bool {
        state.isResumed
    }
}

/// Helper for Bool continuation patterns (most common)
typealias BoolContinuationState = TimeoutContinuation<Bool>

/// Thread-safe result holder for synchronous patterns
/// Used when semaphore-based synchronization is needed
final class SyncResultHolder<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(defaultValue: T) {
        self.value = defaultValue
    }

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
