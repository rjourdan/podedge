import Foundation

// MARK: - Supporting Types

/// Result of a HEAD request against a remote hosting path.
public struct HostHeadResult: Sendable {
    /// Whether the object exists at the remote path.
    public var exists: Bool
    /// Content length in bytes, or `nil` if unavailable.
    public var contentLength: Int64?
    /// Entity tag for cache validation, or `nil` if unavailable.
    public var eTag: String?

    public init(exists: Bool, contentLength: Int64? = nil, eTag: String? = nil) {
        self.exists = exists
        self.contentLength = contentLength
        self.eTag = eTag
    }
}

// MARK: - Protocol

/// Abstraction over podcast file hosting (e.g. S3, R2, B2).
///
/// Implementations handle uploading, deleting, and querying files on a
/// remote hosting backend.
public protocol PodcastHost: Sendable {
    /// Uploads the file at `localURL` to `remotePath` and returns the public URL.
    ///
    /// - Parameters:
    ///   - localURL: Path to the local file to upload.
    ///   - remotePath: Destination path on the hosting backend.
    ///   - contentType: MIME type of the file (e.g. `"audio/mpeg"`).
    ///   - progress: Callback invoked with upload progress from 0.0 to 1.0.
    /// - Returns: The publicly accessible URL of the uploaded file.
    func put(
        localURL: URL,
        remotePath: String,
        contentType: String,
        progress: @Sendable (Double) -> Void
    ) async throws -> URL

    /// Deletes the object at `remotePath` from the hosting backend.
    func delete(remotePath: String) async throws

    /// Returns the public URL for the given `remotePath` without making a network request.
    func publicURL(for remotePath: String) -> URL

    /// Performs a HEAD request against `remotePath` to check existence and metadata.
    func head(remotePath: String) async throws -> HostHeadResult
}
