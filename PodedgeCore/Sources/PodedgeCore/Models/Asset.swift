import Foundation
import SwiftData

/// A file tracked by the library — audio, cover art, transcript, or waveform.
@Model public final class Asset {
    @Attribute(.unique) public var id: UUID
    public var kind: AssetKind
    public var localURL: URL
    public var remotePath: String?
    public var remoteURL: URL?

    /// Hex-encoded SHA-256 digest of the file bytes, used for integrity checks.
    public var sha256: String

    public var byteSize: Int64
    public var contentType: String
    public var durationSeconds: Double?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: AssetKind,
        localURL: URL,
        remotePath: String? = nil,
        remoteURL: URL? = nil,
        sha256: String,
        byteSize: Int64,
        contentType: String,
        durationSeconds: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.localURL = localURL
        self.remotePath = remotePath
        self.remoteURL = remoteURL
        self.sha256 = sha256
        self.byteSize = byteSize
        self.contentType = contentType
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
    }
}
