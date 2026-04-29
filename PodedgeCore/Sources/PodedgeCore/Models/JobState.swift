/// Execution state of a job in the scheduler.
public enum JobState: String, Codable, Sendable {
    /// Queued and waiting to be picked up by the scheduler.
    case pending
    /// Currently being executed.
    case running
    /// Completed successfully.
    case done
    /// Terminated due to an unrecoverable error.
    case failed
    /// Cancelled by the user before completion.
    case cancelled
}
