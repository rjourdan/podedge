import Foundation
import os

/// Manages podcast hosting operations, resolving the appropriate ``PodcastHost``
/// for a given ``HostBinding`` and coordinating uploads and deletions.
public actor HostService {

    private let keychain: KeychainService
    private let sessionProvider: @Sendable () -> URLSession
    private let logger = PodedgeLogger.upload

    /// Creates a host service.
    ///
    /// - Parameters:
    ///   - keychain: Keychain service for loading host credentials.
    ///   - sessionProvider: Factory for URL sessions. Defaults to `.shared`.
    public init(
        keychain: KeychainService,
        sessionProvider: @escaping @Sendable () -> URLSession = { .shared }
    ) {
        self.keychain = keychain
        self.sessionProvider = sessionProvider
    }

    /// Resolves a ``PodcastHost`` from a host binding snapshot.
    ///
    /// - Parameter binding: A sendable snapshot of the host binding's properties.
    /// - Returns: A configured ``S3Host``.
    public func resolveHost(binding: HostBindingSnapshot) async throws -> any PodcastHost {
        guard let credential = try await keychain.loadCredential(forKey: binding.keychainRef) else {
            throw PodedgeError.keychainFailure(reason: "No credential found for key \(binding.keychainRef)")
        }
        return S3Host(
            bucket: binding.bucket,
            region: binding.region,
            prefix: binding.prefix,
            publicBaseURL: binding.publicBaseURL,
            credential: credential,
            session: sessionProvider()
        )
    }

    /// Uploads a local file to the hosting backend.
    ///
    /// - Parameters:
    ///   - host: The resolved podcast host.
    ///   - localURL: Path to the local file.
    ///   - remotePath: Destination path on the host.
    ///   - contentType: MIME type of the file.
    ///   - progress: Upload progress callback.
    /// - Returns: The public URL of the uploaded file.
    public func upload(
        host: any PodcastHost,
        localURL: URL,
        remotePath: String,
        contentType: String,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        logger.info("Uploading \(remotePath, privacy: .public)")
        let url = try await host.put(
            localURL: localURL,
            remotePath: remotePath,
            contentType: contentType,
            progress: progress
        )
        logger.info("Upload complete: \(url.absoluteString, privacy: .public)")
        return url
    }
}
