import Foundation
import SwiftData

/// Writes and queries agent audit entries, with automatic secret redaction
/// and 90-day retention cleanup.
@MainActor
public final class AuditLogService {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Records a tool invocation, redacting secrets from the input summary.
    public func log(
        agentName: String,
        toolName: String,
        scope: ToolScope,
        inputSummary: String,
        outputSummary: String,
        durationSeconds: Double,
        success: Bool
    ) {
        let entry = AgentAuditEntry(
            agentName: agentName,
            toolName: toolName,
            scope: scope,
            inputSummary: Self.redact(inputSummary),
            outputSummary: outputSummary,
            durationSeconds: durationSeconds,
            success: success
        )
        modelContext.insert(entry)
    }

    /// Returns entries matching the given filters, sorted newest-first.
    public func entries(
        agentName: String? = nil,
        toolName: String? = nil,
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) throws -> [AgentAuditEntry] {
        let descriptor = FetchDescriptor<AgentAuditEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        // SwiftData #Predicate doesn't support optional-conditional composition well,
        // so we fetch all and filter in memory. For audit logs this is acceptable.
        let all = try modelContext.fetch(descriptor)
        return all.filter { entry in
            if let agentName, entry.agentName != agentName { return false }
            if let toolName, entry.toolName != toolName { return false }
            if let startDate, entry.timestamp < startDate { return false }
            if let endDate, entry.timestamp > endDate { return false }
            return true
        }
    }

    /// Deletes entries older than 90 days.
    public func purgeExpiredEntries() throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let all = try modelContext.fetch(FetchDescriptor<AgentAuditEntry>())
        for entry in all where entry.timestamp < cutoff {
            modelContext.delete(entry)
        }
    }

    // MARK: - Redaction

    /// Patterns that look like secrets: API keys, tokens, bearer headers, AWS credentials.
    nonisolated private static let secretPatterns: [NSRegularExpression] = {
        let patterns = [
            #"(?i)(api[_-]?key|token|secret|password|bearer)\s*[:=]\s*\S+"#,
            #"(?i)Bearer\s+\S+"#,
            #"sk-[A-Za-z0-9]{20,}"#,
            #"ghp_[A-Za-z0-9]{36,}"#,
            #"AKIA[A-Z0-9]{16}"#,
            #"(?i)aws[_-]?secret[_-]?access[_-]?key\s*[:=]\s*\S+"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Replaces anything that looks like a secret with `[REDACTED]`.
    nonisolated public static func redact(_ input: String) -> String {
        var result = input
        for regex in secretPatterns {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[REDACTED]")
        }
        return result
    }
}
