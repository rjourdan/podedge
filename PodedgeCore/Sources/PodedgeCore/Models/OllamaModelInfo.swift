import Foundation

public struct OllamaModelInfo: Sendable {
    public var name: String
    public var sizeBytes: Int64
    public var modifiedAt: Date

    public init(name: String, sizeBytes: Int64, modifiedAt: Date) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }
}
