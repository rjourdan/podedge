import Foundation
import SwiftData

/// Immutable record of a single tool invocation by an agent.
@Model public final class AgentAuditEntry {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var agentName: String
    public var toolName: String
    public var scope: ToolScope
    public var inputSummary: String
    public var outputSummary: String
    public var durationSeconds: Double
    public var success: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        agentName: String,
        toolName: String,
        scope: ToolScope,
        inputSummary: String,
        outputSummary: String,
        durationSeconds: Double,
        success: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.agentName = agentName
        self.toolName = toolName
        self.scope = scope
        self.inputSummary = inputSummary
        self.outputSummary = outputSummary
        self.durationSeconds = durationSeconds
        self.success = success
    }
}
