import Foundation

/// Role of a message in the assistant conversation.
public enum MessageRole: String, Sendable, Codable {
    case user
    case assistant
}

/// A single message in the assistant conversation.
public struct AssistantMessage: Identifiable, Sendable {
    public var id: UUID
    public var role: MessageRole
    public var text: String
    public var toolCalls: [ToolCallRecord]
    public var providerLabel: String?
    public var isStreaming: Bool

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        toolCalls: [ToolCallRecord] = [],
        providerLabel: String? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.toolCalls = toolCalls
        self.providerLabel = providerLabel
        self.isStreaming = isStreaming
    }
}

/// Record of a single tool invocation during an assistant response.
public struct ToolCallRecord: Identifiable, Sendable {
    public var id: String
    public var toolName: String
    public var arguments: Data
    public var result: ToolResult?

    public init(id: String, toolName: String, arguments: Data, result: ToolResult? = nil) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
    }
}
