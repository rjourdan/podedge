import Foundation

/// Abstracts scheduled background task registration and submission.
///
/// `BGTaskScheduler` is unavailable on macOS (`API_UNAVAILABLE(macos)`).
/// This protocol enables a Timer-based implementation for macOS while
/// keeping the coordinator testable via mock injection.
protocol ScheduledTaskScheduling: Sendable {
    /// Registers a handler for the given task identifier.
    ///
    /// - Parameters:
    ///   - identifier: A unique string identifying the task.
    ///   - handler: The closure invoked when the task fires.
    func register(forTaskWithIdentifier identifier: String, handler: @escaping @Sendable () async -> Void)

    /// Schedules a task to fire at or after the given date.
    ///
    /// - Parameters:
    ///   - identifier: The registered task identifier.
    ///   - date: The earliest date the task should fire.
    func schedule(identifier: String, earliestBeginDate date: Date)

    /// Cancels any pending task with the given identifier.
    func cancel(identifier: String)
}

/// Timer-based implementation of ``ScheduledTaskScheduling`` for macOS.
///
/// Uses `DispatchSourceTimer` to fire handlers at the scheduled time.
/// Each identifier maps to at most one pending timer; re-scheduling
/// replaces the previous timer.
@MainActor
final class TimerTaskScheduler: ScheduledTaskScheduling {
    nonisolated static let shared = TimerTaskScheduler()

    private var handlers: [String: @Sendable () async -> Void] = [:]
    private var timers: [String: DispatchSourceTimer] = [:]

    nonisolated init() {}

    nonisolated func register(forTaskWithIdentifier identifier: String, handler: @escaping @Sendable () async -> Void) {
        Task { @MainActor in
            self.handlers[identifier] = handler
        }
    }

    nonisolated func schedule(identifier: String, earliestBeginDate date: Date) {
        Task { @MainActor in
            self.scheduleOnMain(identifier: identifier, date: date)
        }
    }

    nonisolated func cancel(identifier: String) {
        Task { @MainActor in
            self.timers[identifier]?.cancel()
            self.timers.removeValue(forKey: identifier)
        }
    }

    private func scheduleOnMain(identifier: String, date: Date) {
        // Cancel existing timer for this identifier.
        timers[identifier]?.cancel()

        let delay = max(date.timeIntervalSinceNow, 0)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let handler = self?.handlers[identifier] else { return }
                self?.timers.removeValue(forKey: identifier)
                await handler()
            }
        }
        timers[identifier] = timer
        timer.resume()
    }
}
