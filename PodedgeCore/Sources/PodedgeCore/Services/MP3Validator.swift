import Foundation

/// Validates that a file is a legitimate MP3 audio file by inspecting magic bytes
/// and verifying the presence of MPEG frame sync words.
public enum MP3Validator: Sendable {

    /// Minimum file size in bytes below which a file is considered suspicious.
    private static let minimumFileSize: Int = 1024

    /// Number of bytes to read from the head of the file for validation.
    private static let headerReadSize: Int = 8192

    /// Validates that the file at `url` is a valid MP3 file.
    ///
    /// Checks include:
    /// - File is not empty or suspiciously small (< 1 KB).
    /// - Magic bytes match an ID3 header or MPEG sync word.
    /// - At least one valid MPEG frame sync word exists in the first 8 KB.
    ///
    /// - Parameter url: The local file URL to validate.
    /// - Throws: ``PodedgeError/invalidMP3(reason:)`` when the file is not a valid MP3.
    public static func validate(url: URL) throws {
        // 1. Check file exists and get size.
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        } catch {
            throw PodedgeError.invalidMP3(reason: "Cannot read file: \(error.localizedDescription)")
        }

        guard let fileSize = attributes[.size] as? Int64 else {
            throw PodedgeError.invalidMP3(reason: "Cannot determine file size")
        }

        // 2. Check file is not empty.
        guard fileSize > 0 else {
            throw PodedgeError.invalidMP3(reason: "File is empty")
        }

        // 3. Check file is not suspiciously small.
        guard fileSize >= minimumFileSize else {
            throw PodedgeError.invalidMP3(reason: "File is too small (\(fileSize) bytes)")
        }

        // 4. Read the first few KB for inspection.
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw PodedgeError.invalidMP3(reason: "Cannot open file: \(error.localizedDescription)")
        }
        defer { try? handle.close() }

        let headerData = handle.readData(ofLength: headerReadSize)
        guard headerData.count >= 2 else {
            throw PodedgeError.invalidMP3(reason: "File is too short to contain audio data")
        }

        // 5. Check magic bytes — either ID3 header or MPEG sync word.
        let hasID3Header = checkID3Header(headerData)
        let hasInitialSync = checkMPEGSyncAtStart(headerData)

        guard hasID3Header || hasInitialSync else {
            throw PodedgeError.invalidMP3(
                reason: "File does not start with an ID3 header or MPEG sync word"
            )
        }

        // 6. Verify at least one MPEG frame sync word exists in the data.
        if !findMPEGSyncWord(in: headerData) {
            if hasID3Header {
                // The sync word may be past the ID3 tag. Seek beyond the
                // declared tag size and check for a sync word there.
                let tagSize = id3v2TagSize(in: headerData)
                if tagSize > 0, tagSize < fileSize {
                    handle.seek(toFileOffset: UInt64(tagSize))
                    let postID3 = handle.readData(ofLength: 4)
                    guard postID3.count >= 2,
                          isMPEGSyncWord(byte0: postID3[postID3.startIndex],
                                         byte1: postID3[postID3.startIndex + 1])
                    else {
                        throw PodedgeError.invalidMP3(
                            reason: "No MPEG frame found after ID3 header"
                        )
                    }
                } else {
                    throw PodedgeError.invalidMP3(
                        reason: "ID3 header present but no MPEG audio data found"
                    )
                }
            } else {
                throw PodedgeError.invalidMP3(
                    reason: "No valid MPEG frame sync word found"
                )
            }
        }
    }

    // MARK: - Private Helpers

    /// Returns `true` if the data begins with the ID3v2 magic bytes `"ID3"` (0x49 0x44 0x33).
    private static func checkID3Header(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data[data.startIndex] == 0x49
            && data[data.startIndex + 1] == 0x44
            && data[data.startIndex + 2] == 0x33
    }

    /// Returns `true` if the data begins with a valid MPEG audio sync word.
    ///
    /// Valid first-byte pairs: `0xFF 0xFB`, `0xFF 0xF3`, `0xFF 0xF2`,
    /// or more generally any `0xFF` followed by `0xE0` or higher (11 sync bits set).
    private static func checkMPEGSyncAtStart(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        return isMPEGSyncWord(byte0: data[data.startIndex], byte1: data[data.startIndex + 1])
    }

    /// Scans `data` for any valid MPEG frame sync word (0xFF followed by 0xE0+).
    private static func findMPEGSyncWord(in data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        for i in data.startIndex ..< (data.endIndex - 1) {
            if isMPEGSyncWord(byte0: data[i], byte1: data[i + 1]) {
                return true
            }
        }
        return false
    }

    /// Returns `true` when the two bytes form a valid MPEG audio frame sync word.
    ///
    /// The sync word is 11 set bits: byte0 == 0xFF and the top 3 bits of byte1 are set (0xE0 mask).
    private static func isMPEGSyncWord(byte0: UInt8, byte1: UInt8) -> Bool {
        byte0 == 0xFF && (byte1 & 0xE0) == 0xE0
    }

    /// Returns the total size of an ID3v2 tag (10-byte header + body), or 0 if none.
    private static func id3v2TagSize(in data: Data) -> Int {
        guard data.count >= 10 else { return 0 }
        guard data[data.startIndex] == 0x49,
              data[data.startIndex + 1] == 0x44,
              data[data.startIndex + 2] == 0x33
        else { return 0 }
        // Decode synchsafe size from bytes 6–9.
        let b0 = UInt32(data[data.startIndex + 6])
        let b1 = UInt32(data[data.startIndex + 7])
        let b2 = UInt32(data[data.startIndex + 8])
        let b3 = UInt32(data[data.startIndex + 9])
        let bodySize = (b0 << 21) | (b1 << 14) | (b2 << 7) | b3
        return 10 + Int(bodySize)
    }
}
