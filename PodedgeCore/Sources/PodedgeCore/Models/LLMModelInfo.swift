import Foundation

public struct LLMModelInfo: Sendable {
    public var modelID: String
    public var displayName: String
    public var guidanceString: String
    public var sizeBytes: Int64
    public var isDownloaded: Bool

    public init(modelID: String, displayName: String, guidanceString: String, sizeBytes: Int64, isDownloaded: Bool) {
        self.modelID = modelID
        self.displayName = displayName
        self.guidanceString = guidanceString
        self.sizeBytes = sizeBytes
        self.isDownloaded = isDownloaded
    }
}
