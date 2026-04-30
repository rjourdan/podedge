import Foundation

/// Gates which tools are available to a caller based on trust level.
public enum CapabilityTier: Int, Codable, Sendable, Comparable {
    /// Limited read-only access.
    case basic = 0
    /// Read and mutate access.
    case standard = 1
    /// Full access including destructive operations.
    case full = 2

    public static func < (lhs: CapabilityTier, rhs: CapabilityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
