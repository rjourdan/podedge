import Foundation

/// The outcome of a tool invocation through the broker.
public enum ToolResult: Sendable {
    /// Tool executed successfully; payload is JSON-encoded output.
    case success(Data)
    /// Tool execution failed; payload is a human-readable error description.
    case failure(String)
    /// Destructive tool requires user confirmation before execution.
    case needsConfirmation(toolName: String, input: Data)
}

/// A tool that the in-app assistant can invoke.
///
/// Conforming types describe their capabilities declaratively and provide
/// an ``execute(input:)`` method that performs the actual work.
/// Input and output are JSON-encoded `Data` to avoid type-erasure complexity.
public protocol ToolDefinition: Sendable {
    /// Unique machine-readable name (e.g. `"delete_episode"`).
    var name: String { get }
    /// Human-readable description of what the tool does.
    var description: String { get }
    /// The side-effect level of this tool.
    var scope: ToolScope { get }
    /// Minimum capability tier required to use this tool.
    var requiredTier: CapabilityTier { get }
    /// JSON Schema describing the expected input parameters.
    var parameterSchema: String { get }
    /// Executes the tool with JSON-encoded input, returning JSON-encoded output.
    func execute(input: Data) async throws -> Data
}

/// Something that can invoke tools through the broker.
public protocol ToolCaller: Sendable {
    /// The capability tier of this caller, used to gate tool access.
    var capabilityTier: CapabilityTier { get }
}
