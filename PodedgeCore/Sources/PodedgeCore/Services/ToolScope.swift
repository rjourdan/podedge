import Foundation

/// The side-effect level of a tool invocation.
public enum ToolScope: Int, Codable, Sendable, Comparable {
    /// Tool only reads data; no mutations.
    case readOnly = 0
    /// Tool creates, updates, or modifies data.
    case mutating = 1
    /// Tool deletes data or performs irreversible operations.
    case destructive = 2

    public static func < (lhs: ToolScope, rhs: ToolScope) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
