import Foundation
import os

/// Manages local transcription model storage and downloads.
///
/// Models are stored under `~/Library/Application Support/Podedge/Models/`.
/// `ModelManager` delegates actual downloads to the ``TranscriptionEngine``
/// protocol and manages the filesystem layer.
///
/// - Note: Integrity verification (e.g. SHA-256 checksums) is not yet implemented.
///   TODO: Add SHA-256 field to ``TranscriptionModelInfo`` and verify after download.
public actor ModelManager {

    // MARK: - Dependencies

    private let engine: any TranscriptionEngine
    private let modelsDirectory: URL
    private let logger = PodedgeLogger.logger(category: "models")

    // MARK: - State

    /// Download progress per model name, from 0.0 to 1.0.
    public private(set) var downloadProgress: [String: Double] = [:]

    // MARK: - Init

    /// Creates a model manager backed by the given engine.
    ///
    /// - Parameters:
    ///   - engine: The transcription engine that provides model listing and downloads.
    ///   - modelsDirectory: Override for the models storage directory. Defaults to
    ///     `~/Library/Application Support/Podedge/Models/`.
    public init(
        engine: any TranscriptionEngine,
        modelsDirectory: URL? = nil
    ) {
        self.engine = engine
        self.modelsDirectory = modelsDirectory ?? Self.defaultModelsDirectory
    }

    // MARK: - Model Listing

    /// Returns metadata for all models known to the engine, with local
    /// availability updated from the filesystem.
    public func availableModels() async throws -> [TranscriptionModelInfo] {
        try await engine.availableModels()
    }

    // MARK: - Download

    /// Downloads the model with the given name, reporting progress.
    ///
    /// - Parameters:
    ///   - name: The model name as returned by ``availableModels()``.
    ///   - onProgress: Callback invoked with download progress from 0.0 to 1.0.
    /// - Throws: ``PodedgeError/transcriptionFailed(reason:)`` on failure.
    public func downloadModel(
        named name: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        try validateModelName(name)
        logger.info("Starting download for model: \(name, privacy: .public)")
        downloadProgress[name] = 0.0
        defer { downloadProgress.removeValue(forKey: name) }

        do {
            // The engine's progress closure is synchronous (`@Sendable (Double) -> Void`),
            // so we cannot `await` inside it. We use an unstructured Task to bridge back
            // to actor isolation. `[weak self]` is removed because actors should not be
            // weakly captured — the actor must stay alive for the duration of the download.
            try await engine.downloadModel(named: name) { fraction in
                Task { await self.updateProgress(name: name, fraction: fraction) }
                onProgress?(fraction)
            }
        } catch {
            logger.error("Model download failed: \(error.localizedDescription, privacy: .public)")
            throw PodedgeError.transcriptionFailed(
                reason: "Model download failed for '\(name)': \(error.localizedDescription)"
            )
        }

        logger.info("Model download complete: \(name, privacy: .public)")
    }

    // MARK: - Storage

    /// Returns the local directory where models are stored.
    public var storageDirectory: URL { modelsDirectory }

    /// Returns `true` if a directory exists for the given model name.
    ///
    /// - Throws: ``PodedgeError/preconditionViolated(reason:)`` if the name contains path traversal characters.
    public func isModelDownloaded(named name: String) throws -> Bool {
        try validateModelName(name)
        let modelDir = modelsDirectory.appendingPathComponent(name, isDirectory: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: modelDir.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue
    }

    /// Deletes the local copy of the model with the given name.
    ///
    /// - Parameter name: The model name to remove.
    /// - Throws: ``PodedgeError/preconditionViolated(reason:)`` if the name contains
    ///   path traversal characters, or if the filesystem operation fails.
    public func deleteModel(named name: String) throws {
        try validateModelName(name)
        let modelDir = modelsDirectory.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelDir.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: modelDir)
        logger.info("Deleted model: \(name, privacy: .public)")
    }

    /// Returns the total disk space used by all downloaded models, in bytes.
    public func totalStorageBytes() throws -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: modelsDirectory.path(percentEncoded: false)) else { return 0 }
        let enumerator = fm.enumerator(at: modelsDirectory, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Private

    private static var defaultModelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Podedge", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// Validates that a model name is safe for use as a filesystem path component.
    ///
    /// Rejects names containing `/`, `\`, or `..` to prevent path traversal.
    private func validateModelName(_ name: String) throws {
        if name.contains("/") || name.contains("\\") || name.contains("..") {
            throw PodedgeError.preconditionViolated(reason: "Invalid model name: \(name)")
        }
    }

    private func updateProgress(name: String, fraction: Double) {
        downloadProgress[name] = fraction
    }
}
