import Foundation
import os

/// Namespace for pre-configured `os.Logger` instances used throughout PodedgeCore.
public enum PodedgeLogger {

    /// The unified subsystem identifier for all Podedge loggers.
    private static let subsystem = "com.podedge.core"

    /// Creates an `os.Logger` with the Podedge subsystem and the given category.
    ///
    /// - Parameter category: A short label identifying the logging domain (e.g. `"ingest"`).
    /// - Returns: A configured `Logger` instance.
    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    /// Replaces patterns that look like secrets with `[REDACTED]`.
    ///
    /// Delegates to ``AuditLogService/redact(_:)`` for consistent redaction
    /// across the codebase.
    public static func redact(_ message: String) -> String {
        AuditLogService.redact(message)
    }

    // MARK: - Pre-built Loggers

    /// General-purpose logger for uncategorized messages.
    public static let general = logger(category: "general")

    /// Logger for audio ingest operations.
    public static let ingest = logger(category: "ingest")

    /// Logger for file upload operations.
    public static let upload = logger(category: "upload")

    /// Logger for RSS feed generation and validation.
    public static let feed = logger(category: "feed")

    /// Logger for analytics polling and snapshot operations.
    public static let analytics = logger(category: "analytics")

    /// Logger for the job scheduler.
    public static let scheduler = logger(category: "scheduler")

    /// Logger for LLM provider interactions.
    public static let llm = logger(category: "llm")
}
