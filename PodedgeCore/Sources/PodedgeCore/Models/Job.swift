import Foundation
import SwiftData

/// A durable, schedulable unit of work tracked by the job scheduler.
@Model public final class Job {
    @Attribute(.unique) public var id: UUID
    public var kind: JobKind

    /// The episode or show ID this job operates on, depending on ``kind``.
    public var targetID: UUID

    public var state: JobState
    public var attempts: Int
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var parentJobID: UUID?

    /// Kind-specific serialized payload (e.g. processing options, upload manifest).
    public var payloadJSON: String?

    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        kind: JobKind,
        targetID: UUID,
        state: JobState = .pending,
        attempts: Int = 0,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        parentJobID: UUID? = nil,
        payloadJSON: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.targetID = targetID
        self.state = state
        self.attempts = attempts
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.parentJobID = parentJobID
        self.payloadJSON = payloadJSON
        self.errorMessage = errorMessage
    }
}
