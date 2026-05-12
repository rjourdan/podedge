import AVFoundation
import Foundation

/// Reads and writes ID3 tag metadata from/to audio files.
///
/// Uses AVFoundation's metadata APIs (`AVAsset.metadata`) for reading
/// and basic ID3v2 frame construction for writing. Full ID3v2.4
/// compliance is not targeted for v1 — this implementation covers the
/// common frames: TIT2 (title), TPE1 (artist), TALB (album).
///
/// **Limitations:**
/// - Chapter reading (CHAP/CTOC) is not supported via AVFoundation metadata;
///   chapters will always be empty.
/// - Cover art reading uses the AVFoundation common key space.
/// - Writing replaces the entire ID3v2 tag header with a newly constructed one.
/// - Cover art MIME type is auto-detected (JPEG vs PNG) from magic bytes.
public struct ID3TagService: Sendable {

    /// Creates a new ID3 tag service.
    public init() {}

    // MARK: - Reading

    /// Reads ID3 tag metadata from the audio file at `url`.
    ///
    /// - Parameter url: A local file URL pointing to an audio file.
    /// - Returns: An ``ID3Metadata`` value with the extracted tag data.
    /// - Throws: An error if the file cannot be read.
    public func readTags(url: URL) async throws -> ID3Metadata {
        let asset = AVURLAsset(url: url)
        let metadata = try await asset.load(.metadata)

        var title: String?
        var artist: String?
        var album: String?
        var coverImageData: Data?

        for item in metadata {
            guard let commonKey = item.commonKey else { continue }
            switch commonKey {
            case .commonKeyTitle:
                title = try await item.load(.stringValue)
            case .commonKeyArtist:
                artist = try await item.load(.stringValue)
            case .commonKeyAlbumName:
                album = try await item.load(.stringValue)
            case .commonKeyArtwork:
                coverImageData = try await item.load(.dataValue)
            default:
                break
            }
        }

        // Also try ID3-specific keys for fields not found via common keys.
        if title == nil || artist == nil || album == nil {
            let id3TitleItems = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: .id3MetadataTitleDescription
            )
            if title == nil, let item = id3TitleItems.first {
                title = try await item.load(.stringValue)
            }

            let artistItems = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: .id3MetadataLeadPerformer
            )
            if artist == nil, let item = artistItems.first {
                artist = try await item.load(.stringValue)
            }

            let albumItems = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: .id3MetadataAlbumTitle
            )
            if album == nil, let item = albumItems.first {
                album = try await item.load(.stringValue)
            }
        }

        return ID3Metadata(
            title: title,
            artist: artist,
            album: album,
            coverImageData: coverImageData,
            chapters: []
        )
    }

    // MARK: - Writing

    /// Writes ID3v2 tag metadata to the audio file at `url`.
    ///
    /// Constructs a minimal ID3v2.4 header with TIT2, TPE1, TALB, and APIC frames
    /// and prepends it to the audio data (replacing any existing ID3v2 header).
    ///
    /// - Parameters:
    ///   - url: A local file URL pointing to an audio file.
    ///   - metadata: The ``ID3Metadata`` to write.
    /// - Throws: An error if the file cannot be read or written.
    public func writeTags(to url: URL, metadata: ID3Metadata) throws {
        var fileData = try Data(contentsOf: url, options: .mappedIfSafe)

        // Strip existing ID3v2 header if present.
        let existingHeaderSize = id3v2HeaderSize(in: fileData)
        if existingHeaderSize > 0 {
            fileData = fileData.dropFirst(existingHeaderSize).asData
        }

        // Build new ID3v2.3 tag.
        var frames = Data()
        if let title = metadata.title {
            frames.append(buildTextFrame(id: "TIT2", text: title))
        }
        if let artist = metadata.artist {
            frames.append(buildTextFrame(id: "TPE1", text: artist))
        }
        if let album = metadata.album {
            frames.append(buildTextFrame(id: "TALB", text: album))
        }
        if let imageData = metadata.coverImageData {
            frames.append(try buildAPICFrame(imageData: imageData))
        }

        // Build ID3v2.4 header (10 bytes).
        var header = Data()
        header.append(contentsOf: [0x49, 0x44, 0x33]) // "ID3"
        header.append(contentsOf: [0x04, 0x00])         // Version 2.4.0
        header.append(0x00)                              // Flags
        header.append(contentsOf: encodeSynchsafe(UInt32(frames.count)))

        var output = Data()
        output.append(header)
        output.append(frames)
        output.append(fileData)

        try output.write(to: url, options: .atomic)
    }

    // MARK: - Private Helpers

    /// Returns the total size of an existing ID3v2 header (header + tag body), or 0 if none.
    private func id3v2HeaderSize(in data: Data) -> Int {
        guard data.count >= 10 else { return 0 }
        // Check for "ID3" magic.
        guard data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 else { return 0 }
        // Decode synchsafe size from bytes 6–9.
        let size = decodeSynchsafe(data[6], data[7], data[8], data[9])
        return 10 + Int(size)
    }

    /// Decodes a 4-byte synchsafe integer (each byte uses only 7 bits).
    private func decodeSynchsafe(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> UInt32 {
        (UInt32(b0) << 21) | (UInt32(b1) << 14) | (UInt32(b2) << 7) | UInt32(b3)
    }

    /// Encodes a UInt32 as a 4-byte synchsafe integer.
    private func encodeSynchsafe(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 21) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8(value & 0x7F),
        ]
    }

    /// Builds an ID3v2.4 text frame (e.g. TIT2, TPE1, TALB).
    private func buildTextFrame(id: String, text: String) -> Data {
        // Frame: 4-byte ID + 4-byte synchsafe size + 2-byte flags + 1-byte encoding + text bytes
        let encoding: UInt8 = 0x03 // UTF-8 (valid in ID3v2.4)
        guard let textData = text.data(using: .utf8) else { return Data() }
        let frameSize = UInt32(1 + textData.count) // encoding byte + text

        var frame = Data()
        frame.append(contentsOf: Array(id.utf8))
        frame.append(contentsOf: encodeSynchsafe(frameSize))
        frame.append(contentsOf: [0x00, 0x00]) // Flags
        frame.append(encoding)
        frame.append(textData)
        return frame
    }

    /// Maximum allowed cover art size in bytes (2 MB).
    private static let maxCoverArtSize = 2 * 1024 * 1024

    /// Builds an ID3v2.4 APIC (attached picture) frame.
    ///
    /// - Throws: ``PodedgeError/invalidMP3(reason:)`` if `imageData` exceeds 2 MB.
    private func buildAPICFrame(imageData: Data) throws -> Data {
        guard imageData.count <= Self.maxCoverArtSize else {
            throw PodedgeError.invalidMP3(
                reason: "Cover art exceeds maximum size of \(Self.maxCoverArtSize / (1024 * 1024)) MB"
            )
        }
        let encoding: UInt8 = 0x00 // ISO-8859-1 for MIME type

        // Detect MIME type from magic bytes.
        let mimeType: String
        if imageData.count >= 8,
           imageData[imageData.startIndex] == 0x89,
           imageData[imageData.startIndex + 1] == 0x50 {
            mimeType = "image/png"
        } else {
            mimeType = "image/jpeg"
        }

        let pictureType: UInt8 = 0x03 // Cover (front)

        var payload = Data()
        payload.append(encoding)
        payload.append(contentsOf: Array(mimeType.utf8))
        payload.append(0x00) // Null terminator for MIME
        payload.append(pictureType)
        payload.append(0x00) // Empty description + null terminator
        payload.append(imageData)

        let frameSize = UInt32(payload.count)
        var frame = Data()
        frame.append(contentsOf: Array("APIC".utf8))
        frame.append(contentsOf: encodeSynchsafe(frameSize))
        frame.append(contentsOf: [0x00, 0x00]) // Flags
        frame.append(payload)
        return frame
    }
}

// MARK: - Data Extension

private extension Data.SubSequence {
    /// Converts a `Data.SubSequence` back to `Data`.
    var asData: Data { Data(self) }
}
