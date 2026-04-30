import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

// MARK: - Stub Handler

/// A configurable job handler that records calls and can be set to succeed or throw.
final class StubJobHandler: JobHandler, @unchecked Sendable {
    let handledKind: JobKind
    private let lock = NSLock()
    private var _executedJobIDs: [UUID] = []
    private var _shouldThrow: Bool

    /// Job IDs that were passed to ``execute(jobID:container:)``, in order.
    var executedJobIDs: [UUID] {
        lock.withLock { _executedJobIDs }
    }

    /// Number of times ``execute(jobID:container:)`` was called.
    var callCount: Int {
        lock.withLock { _executedJobIDs.count }
    }

    /// When `true`, ``execute(jobID:container:)`` throws an error.
    var shouldThrow: Bool {
        get { lock.withLock { _shouldThrow } }
        set { lock.withLock { _shouldThrow = newValue } }
    }

    init(kind: JobKind, shouldThrow: Bool = false) {
        self.handledKind = kind
        self._shouldThrow = shouldThrow
    }

    func execute(jobID: UUID, container: ModelContainer) async throws {
        lock.withLock { _executedJobIDs.append(jobID) }
        if shouldThrow {
            throw PodedgeError.jobFailed(jobID: jobID, reason: "Stub failure")
        }
    }
}

// MARK: - Pure Logic Tests

@Suite("JobScheduler Pure Logic")
struct JobSchedulerPureLogicTests {

    @Test("Backoff delay uses exponential formula capped at 300s")
    func backoffDelay() {
        #expect(JobScheduler.backoffDelay(attempt: 0) == 1.0)
        #expect(JobScheduler.backoffDelay(attempt: 1) == 2.0)
        #expect(JobScheduler.backoffDelay(attempt: 2) == 4.0)
        #expect(JobScheduler.backoffDelay(attempt: 3) == 8.0)
        #expect(JobScheduler.backoffDelay(attempt: 8) == 256.0)
        #expect(JobScheduler.backoffDelay(attempt: 9) == 300.0)
        #expect(JobScheduler.backoffDelay(attempt: 20) == 300.0)
    }

    @Test("Job defaults to pending state with zero attempts")
    func jobDefaults() {
        let job = Job(kind: .ingest, targetID: UUID())
        #expect(job.state == .pending)
        #expect(job.attempts == 0)
        #expect(job.startedAt == nil)
        #expect(job.finishedAt == nil)
        #expect(job.errorMessage == nil)
    }

    @Test("StubJobHandler records executed job IDs")
    func stubHandlerRecords() async throws {
        let handler = StubJobHandler(kind: .ingest)
        let container = await TestDatabase.shared
        let jobID = UUID()
        try await handler.execute(jobID: jobID, container: container)
        #expect(handler.callCount == 1)
        #expect(handler.executedJobIDs == [jobID])
    }

    @Test("StubJobHandler throws when configured")
    func stubHandlerThrows() async throws {
        let handler = StubJobHandler(kind: .ingest, shouldThrow: true)
        let container = await TestDatabase.shared
        let jobID = UUID()
        do {
            try await handler.execute(jobID: jobID, container: container)
            Issue.record("Expected handler to throw")
        } catch {
            #expect(handler.callCount == 1)
        }
    }

    @Test("StubJobHandler handles multiple calls")
    func stubHandlerMultipleCalls() async throws {
        let handler = StubJobHandler(kind: .upload)
        let container = await TestDatabase.shared
        let id1 = UUID()
        let id2 = UUID()
        try await handler.execute(jobID: id1, container: container)
        try await handler.execute(jobID: id2, container: container)
        #expect(handler.callCount == 2)
        #expect(handler.executedJobIDs == [id1, id2])
    }
}

// MARK: - SwiftData Integration Tests

@Suite("JobScheduler Integration", .serialized, .tags(.swiftData))
@MainActor
struct JobSchedulerIntegrationTests {

    private func makeScheduler() throws -> (JobScheduler, ModelContainer) {
        try TestDatabase.reset()
        let container = TestDatabase.shared
        let scheduler = JobScheduler(modelContainer: container)
        return (scheduler, container)
    }

    @Test("Enqueue persists a job")
    func enqueuePersists() throws {
        let (scheduler, container) = try makeScheduler()
        let job = Job(kind: .ingest, targetID: UUID())
        try scheduler.enqueue(job)

        let context = container.mainContext
        let fetched = try context.fetch(
            FetchDescriptor<Job>()
        ).filter { $0.state == .pending }
        #expect(fetched.count >= 1)
        #expect(fetched.contains { $0.kind == .ingest })
    }

    @Test("Cancel marks job as cancelled")
    func cancelJob() throws {
        let (scheduler, _) = try makeScheduler()
        let job = Job(kind: .ingest, targetID: UUID())
        try scheduler.enqueue(job)

        try scheduler.cancel(jobID: job.id)

        #expect(job.state == .cancelled)
        #expect(job.finishedAt != nil)
    }

    @Test("Cancel throws for non-existent job")
    func cancelNonExistent() throws {
        let (scheduler, _) = try makeScheduler()
        #expect(throws: PodedgeError.self) {
            try scheduler.cancel(jobID: UUID())
        }
    }

    @Test("Cancel throws for already-done job")
    func cancelDoneJob() throws {
        let (scheduler, container) = try makeScheduler()
        let job = Job(kind: .ingest, targetID: UUID(), state: .done)
        container.mainContext.insert(job)
        try container.mainContext.save()

        #expect(throws: PodedgeError.self) {
            try scheduler.cancel(jobID: job.id)
        }
    }

    @Test("Retry resets failed job to pending")
    func retryFailedJob() throws {
        let (scheduler, _) = try makeScheduler()
        let job = Job(kind: .upload, targetID: UUID(), state: .failed, attempts: 1)
        job.errorMessage = "network timeout"
        job.finishedAt = Date()
        try scheduler.enqueue(job)
        // Manually set to failed after enqueue (enqueue inserts as-is).
        job.state = .failed

        try scheduler.retry(jobID: job.id)

        #expect(job.state == .pending)
        #expect(job.attempts == 2)
        #expect(job.errorMessage == nil)
        #expect(job.finishedAt == nil)
        #expect(job.startedAt == nil)
    }

    @Test("Retry throws for pending job")
    func retryPendingJob() throws {
        let (scheduler, _) = try makeScheduler()
        let job = Job(kind: .ingest, targetID: UUID())
        try scheduler.enqueue(job)

        #expect(throws: PodedgeError.self) {
            try scheduler.retry(jobID: job.id)
        }
    }

    @Test("Retry resets cancelled job to pending")
    func retryCancelledJob() throws {
        let (scheduler, _) = try makeScheduler()
        let job = Job(kind: .transcribe, targetID: UUID())
        try scheduler.enqueue(job)
        // Cancel it first, then retry.
        try scheduler.cancel(jobID: job.id)
        #expect(job.state == .cancelled)

        try scheduler.retry(jobID: job.id)

        #expect(job.state == .pending)
        #expect(job.attempts == 1)
    }

    @Test("Handler registration works")
    func handlerRegistration() throws {
        let (scheduler, _) = try makeScheduler()
        let handler = StubJobHandler(kind: .ingest)
        scheduler.registerHandler(handler)
        // No assertion needed — just verifying it doesn't crash.
        // The handler will be used when start() picks up jobs.
    }

    @Test("Stop is idempotent")
    func stopIdempotent() throws {
        let (scheduler, _) = try makeScheduler()
        scheduler.stop()
        scheduler.stop()
        // No crash = pass.
    }

    @Test("start() picks up and executes a pending job")
    func startExecutesJob() async throws {
        let (scheduler, container) = try makeScheduler()
        let handler = StubJobHandler(kind: .ingest)
        scheduler.registerHandler(handler)

        let job = Job(kind: .ingest, targetID: UUID())
        try scheduler.enqueue(job)
        let jobID = job.id

        scheduler.start()
        try await Task.sleep(for: .seconds(2))
        scheduler.stop()

        #expect(handler.callCount >= 1)
        #expect(handler.executedJobIDs.contains(jobID))

        let context = container.mainContext
        var descriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.state == .done)
    }

    @Test("Jobs exceeding maxAttempts are marked failed")
    func maxAttemptsExceeded() async throws {
        try TestDatabase.reset()
        let container = TestDatabase.shared
        let scheduler = JobScheduler(modelContainer: container, maxAttempts: 3)

        let job = Job(kind: .ingest, targetID: UUID(), attempts: 3)
        try scheduler.enqueue(job)
        let jobID = job.id

        scheduler.start()
        try await Task.sleep(for: .seconds(2))
        scheduler.stop()

        let context = container.mainContext
        var descriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.state == .failed)
        #expect(fetched?.errorMessage == "Max attempts exceeded")
    }
}
