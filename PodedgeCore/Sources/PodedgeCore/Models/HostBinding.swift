import Foundation
import SwiftData

/// Configuration for a podcast hosting destination (e.g. an S3 bucket).
@Model public final class HostBinding {
    @Attribute(.unique) public var id: UUID
    public var kind: HostKind
    public var displayName: String
    public var bucket: String
    public var region: String
    public var prefix: String
    public var publicBaseURL: URL

    /// Opaque Keychain item reference. The actual credentials are stored in the
    /// system Keychain; this string identifies the entry.
    public var keychainRef: String

    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: HostKind = .s3,
        displayName: String,
        bucket: String,
        region: String,
        prefix: String = "",
        publicBaseURL: URL,
        keychainRef: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bucket = bucket
        self.region = region
        self.prefix = prefix
        self.publicBaseURL = publicBaseURL
        self.keychainRef = keychainRef
        self.createdAt = createdAt
    }
}
