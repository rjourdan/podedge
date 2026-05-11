import Foundation
import os
import SwiftData

// MARK: - JobHandler Protocol

/// A handler that performs the actual work for a specific ``JobKind``.
///
/// Handlers receive the job's persistent model ID and a reference to the
/// model container so they can create their own ``ModelContext`` on the
/// appropriate isolation domain.
public protocol JobHandler: Sendable {
    /// The kind of job this handler processes.
    var handledKind: JobKind { get }

    /// Executes the job identified by `jobID`.
    ///
    /// - Parameters:
    ///   - jobID: The persistent identifier of the job to execute.
    ///   - container: The model container for creating a context if needed.
    func execute(jobID: UUID, container: ModelContainer) async throws
}

// MARK: - JobScheduler

/// Processes durable ``Job`` records from the SwiftData store, respecting
/// concurrency limits, parent-job dependencies, and exponential backoff on failure.
///
/// The scheduler is `@MainActor`-isolated because it reads and writes
/// ``Job`` models through a ``ModelContext``, which is not `Sendable`.
/// Actual job work is dispatched to ``JobHandler`` implementations that
/// manage their own concurrency.
@MainActor
public final class JobScheduler {

    // MARK: - Configuration

    /// Maximum number of jobs that may run concurrently.
    private let maxConcurrent: Int

    /// Maximum number of execution attempts before a job is permanently failed.
    private let maxAttempts: Int

    /// Maximum backoff delay in seconds.
    nonisolated public static let maxBackoffSeconds: Double = 300

    // MARK: - State

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private var handlers: [JobKind: any JobHandler] = [:]
    private var isRunning = false
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var processingTask: Task<Void, Never>?

    private let logger = PodedgeLogger.scheduler

    // MARK: - Init

    /// Creates a scheduler backed by the given model container.
    ///
    /// - Parameters:
    ///   - modelContainer: The SwiftData container used for job persistence.
    ///   - maxConcurrent: Maximum number of jobs to run in parallel. Defaults to 3.
    ///   - maxAttempts: Maximum execution attempts before a job is permanently failed. Defaults to 5.
    public init(modelContainer: ModelContainer, maxConcurrent: Int = 3, maxAttempts: Int = 5) {
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
        self.maxConcurrent = maxConcurrent
        self.maxAttempts = maxAttempts
    }

    // MARK: - Handler Registration

    /// Registers a handler for a specific job kind.
    ///
    /// Replaces any previously registered handler for the same kind.
    public func registerHandler(_ handler: any JobHandler) {
        handlers[handler.handledKind] = handler
    }

    /// Returns the registered handler for the given job kind, or `nil`.
    public func handler(for kind: JobKind) -> (any JobHandler)? {
        handlers[kind]
    }

    // MARK: - Job Management

    /// Inserts a new job into the persistent store.
    public func enqueue(_ job: Job) throws {
        modelContext.insert(job)
        try modelContext.save()
    }

    /// Marks a pending or running job as cancelled.
    public func cancel(jobID: UUID) throws {
        guard let job = fetchJob(id: jobID) else {
            throw PodedgeError.notFound(entity: "Job", id: jobID.uuidString)
        }
        guard job.state == .pending || job.state == .running else {
            throw PodedgeError.preconditionViolated(
                reason: "Cannot cancel job in state \(job.state.rawValue)")
        }
        job.state = .cancelled
        job.finishedAt = Date()
        try modelContext.save()

        // Cancel the in-flight task if running.
        activeTasks[jobID]?.cancel()
        activeTasks.removeValue(forKey: jobID)
    }

    /// Resets a failed or cancelled job to pending and increments its attempt count.
    public func retry(jobID: UUID) throws {
        guard let job = fetchJob(id: jobID) else {
            throw PodedgeError.notFound(entity: "Job", id: jobID.uuidString)
        }
        guard job.state == .failed || job.state == .cancelled else {
            throw PodedgeError.preconditionViolated(
                reason: "Cannot retry job in state \(job.state.rawValue)")
        }
        job.state = .pending
        job.attempts += 1
        job.finishedAt = nil
        job.startedAt = nil
        job.errorMessage = nil
        try modelContext.save()
    }

    // MARK: - Processing Loop

    /// Begins the processing loop. Call once at app launch.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        processingTask = Task { @MainActor [weak self] in
            await self?.processLoop()
        }
    }

    /// Gracefully stops the processing loop and cancels in-flight tasks.
    public func stop() {
        isRunning = false
        processingTask?.cancel()
        processingTask = nil
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }

    // MARK: - Internal

    private func processLoop() async {
        while isRunning, !Task.isCancelled {
            let availableSlots = maxConcurrent - activeTasks.count
            if availableSlots > 0 {
                pickAndRun(slots: availableSlots)
            }
            // Poll interval — 1 second between scheduling passes.
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func pickAndRun(slots: Int) {
        let descriptor = FetchDescriptor<Job>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let allJobs: [Job]
        do {
            allJobs = try modelContext.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch jobs: \(error.localizedDescription, privacy: .public)")
            return
        }

        let now = Date()

        // Fail jobs that have exceeded maxAttempts.
        for job in allJobs where job.state == .pending && job.attempts >= maxAttempts {
            job.state = .failed
            job.errorMessage = "Max attempts exceeded"
            job.finishedAt = now
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save max-attempts failure for job \(job.id): \(error.localizedDescription, privacy: .public)")
            }
        }

        let pendingJobs = allJobs.filter { $0.state == .pending }

        var launched = 0
        for job in pendingJobs where launched < slots {
            // Skip jobs that have exceeded maxAttempts (just marked failed above, but guard anyway).
            guard job.attempts < maxAttempts else { continue }

            // Enforce backoff: skip jobs whose finishedAt + backoff is in the future.
            if let finishedAt = job.finishedAt {
                let backoff = Self.backoffDelay(attempt: job.attempts)
                if finishedAt.addingTimeInterval(backoff) > now {
                    continue
                }
            }

            // Skip jobs whose parent hasn't finished.
            if let parentID = job.parentJobID {
                if let parent = fetchJob(id: parentID), parent.state != .done {
                    continue
                }
            }

            // Skip if already active.
            guard activeTasks[job.id] == nil else { continue }

            guard let handler = handlers[job.kind] else { continue }

            let jobID = job.id

            // Mark as running.
            job.state = .running
            job.startedAt = Date()
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save running state for job \(jobID): \(error.localizedDescription, privacy: .public)")
            }

            let container = modelContainer
            let task = Task { @MainActor [weak self] in
                do {
                    try await handler.execute(jobID: jobID, container: container)
                    self?.markDone(jobID: jobID)
                } catch {
                    self?.markFailed(jobID: jobID, error: error)
                }
            }
            activeTasks[jobID] = task
            launched += 1
        }
    }

    private func markDone(jobID: UUID) {
        if let job = fetchJob(id: jobID) {
            job.state = .done
            job.finishedAt = Date()
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save done state for job \(jobID): \(error.localizedDescription, privacy: .public)")
            }
        }
        activeTasks.removeValue(forKey: jobID)
    }

    private func markFailed(jobID: UUID, error: Error) {
        if let job = fetchJob(id: jobID) {
            job.state = .failed
            job.errorMessage = error.localizedDescription
            job.finishedAt = Date()
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save failure state for job \(jobID): \(error.localizedDescription, privacy: .public)")
            }
        }
        activeTasks.removeValue(forKey: jobID)
    }

    /// Fetches a single job by ID.
    private func fetchJob(id: UUID) -> Job? {
        var descriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch job \(id): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Calculates exponential backoff delay for the given attempt number.
    ///
    /// Formula: min(2^attempt, 300) seconds.
    nonisolated public static func backoffDelay(attempt: Int) -> Double {
        min(pow(2.0, Double(attempt)), maxBackoffSeconds)
    }
}
