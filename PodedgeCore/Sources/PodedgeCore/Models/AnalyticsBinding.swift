import Foundation
import SwiftData

/// Binding between a show and an analytics provider (e.g. OP3).
@Model public final class AnalyticsBinding {
    @Attribute(.unique) public var id: UUID
    public var provider: String
    public var externalShowID: String?
    public var prefixBaseURL: URL

    /// Opaque Keychain item reference for the analytics provider API key.
    /// The actual secret is stored in the system Keychain.
    public var keychainRef: String?

    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        provider: String = "op3",
        externalShowID: String? = nil,
        prefixBaseURL: URL,
        keychainRef: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.externalShowID = externalShowID
        self.prefixBaseURL = prefixBaseURL
        self.keychainRef = keychainRef
        self.createdAt = createdAt
    }
}
