import Foundation

/// Reads per-show markdown guide files from the filesystem.
///
/// Each show can have named guides stored as markdown files under
/// `~/Library/Application Support/Podedge/Shows/<showID>/`.
/// Agents use these guides to shape their output based on user preferences.
public struct PerShowGuidesService: Sendable {
    private let baseDirectory: URL

    /// Creates a new service.
    /// - Parameter baseDirectory: Override for testing. Defaults to
    ///   `~/Library/Application Support/Podedge/Shows/`
    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            self.baseDirectory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Podedge/Shows", isDirectory: true)
        }
    }

    /// Reads a named guide for a specific show.
    /// - Parameters:
    ///   - name: Guide name without extension (e.g. "promotion-guide", "voice-guide")
    ///   - showID: The show's UUID
    /// - Returns: The markdown content, or nil if the file doesn't exist.
    public func guide(named name: String, for showID: UUID) -> String? {
        let fileURL = baseDirectory
            .appendingPathComponent(showID.uuidString, isDirectory: true)
            .appendingPathComponent("\(name).md")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return try? String(contentsOf: fileURL, encoding: .utf8)
    }
}
