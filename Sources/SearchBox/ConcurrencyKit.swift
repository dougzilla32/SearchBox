//
//  ConcurrencyKit.swift
//  ConcurrencyKit
//
//  Created by Doug Stein on 4/13/18.
//

import Foundation.NSDate // for TimeInterval

public struct TaskTimeoutError: Error, Equatable {}

///
/// Derived from work by Ole Begemann
/// https://forums.swift.org/t/running-an-async-task-with-a-timeout/49733
///
/// Execute an operation in the current task subject to a timeout.
///
/// - Parameters:
///   - seconds: The duration in seconds `operation` is allowed to run before timing out.
///   - operation: The async operation to perform on a background thread.
/// - Returns: Returns the result of `operation` if it completed in time.
/// - Throws: Throws ``TimedOutError`` if the timeout expires before `operation` completes.
///   If `operation` throws an error before the timeout expires, that error is propagated to the caller.
public func withTimeout<R>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> R
) async throws -> R {
    return try await withThrowingTaskGroup(of: R.self) { group in
        let deadline = Date(timeIntervalSinceNow: seconds)

        // Start actual work.
        group.addTask {
            return try await operation()
        }
        // Start timeout child task.
        group.addTask {
            let interval = deadline.timeIntervalSinceNow
            if interval > 0 {
                try await Task.sleep(seconds: interval)
            }
            try Task.checkCancellation()
            // We’ve reached the timeout.
            throw TaskTimeoutError()
        }
        // First finished child task wins, cancel the other task.
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

///
/// Derived from work by Ole Begemann
/// https://forums.swift.org/t/running-an-async-task-with-a-timeout/49733
///
/// Execute an operation in the current task, on the main actor, subject to a timeout.
///
/// - Parameters:
///   - seconds: The duration in seconds `operation` is allowed to run before timing out.
///   - operation: The async operation to perform on the main thread.
/// - Returns: Returns the result of `operation` if it completed in time.
/// - Throws: Throws ``TimedOutError`` if the timeout expires before `operation` completes.
///   If `operation` throws an error before the timeout expires, that error is propagated to the caller.
public func withTimeoutOnMainActor<R>(
    seconds: TimeInterval,
    operation: @escaping @MainActor @Sendable () async throws -> R
) async throws -> R {
    return try await withThrowingTaskGroup(of: R.self) { group in
        let deadline = Date(timeIntervalSinceNow: seconds)

        // Start actual work.
        group.addTask {
            // Need to separately call 'onMainActor' to force onto the main thread, because
            // calling 'group.addTask' casts 'operation' to a non-MainActor closure (not sure
            // why the compiler allows this...)
            return try await onMainActor(operation: operation)
        }
        // Start timeout child task.
        group.addTask {
            let interval = deadline.timeIntervalSinceNow
            if interval > 0 {
                try await Task.sleep(seconds: interval)
            }
            try Task.checkCancellation()
            // We’ve reached the timeout.
            throw TaskTimeoutError()
        }
        // First finished child task wins, cancel the other task.
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

@MainActor private func onMainActor<R>(operation: @escaping @MainActor @Sendable () async throws -> R) async throws -> R {
    return try await operation()
}

extension Task where Success == Never, Failure == Never {
    /// Suspends the current task for at least the given duration
    /// in  seconds.
    ///
    /// If the task is canceled before the time ends,
    /// this function throws `CancellationError`.
    ///
    /// This function doesn't block the underlying thread.
    public static func sleep(seconds duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(duration * Double(1_000_000_000)))
    }
}

extension ThrowingTaskGroup {
    public mutating func addTaskMainActor(priority: TaskPriority? = nil, operation: @escaping @Sendable @MainActor () async throws -> ChildTaskResult) async {
        return addTask(priority: priority, operation: operation)
    }
}
