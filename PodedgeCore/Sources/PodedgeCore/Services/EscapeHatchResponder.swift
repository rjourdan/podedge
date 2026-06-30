import Foundation

/// Describes why the assistant could not complete a request.
public enum AssistantFailure: Sendable {
    case iterationCapExceeded(agentID: String)
    case providerUnreachable(providerID: String)
    case toolCallFailed(toolName: String, reason: String)
    case rateLimitHit(type: String)
    case unknownIntent
}

/// Produces human-readable fallback responses when the assistant cannot complete a request.
///
/// Each response includes guidance on how to accomplish the task manually via the UI.
public struct EscapeHatchResponder: Sendable {

    public init() {}

    /// Generates a fallback response for the given failure.
    public func response(for failure: AssistantFailure) -> String {
        switch failure {
        case .iterationCapExceeded(let agentID):
            return "I've reached my iteration limit for this request. You can complete the \(agentID) task manually — open the episode editor and use the relevant tab."
        case .providerUnreachable(let providerID):
            return "I can't reach the \(providerID) provider right now. Check that it's running, or switch providers in Settings → LLM Providers."
        case .toolCallFailed(let toolName, let reason):
            return "The \(toolName.replacingOccurrences(of: "_", with: " ")) action failed: \(reason). You can try it manually from the UI."
        case .rateLimitHit(let type):
            return "I've hit the \(type) rate limit for this session. You can continue working manually, or press ⌘K to start a fresh session."
        case .unknownIntent:
            return "I'm not sure what you'd like to do. Try starting with /promote or /publish, or describe what you'd like help with."
        }
    }
}
