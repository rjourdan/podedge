import Foundation
import SwiftData

/// Tracks a show's submission to a distribution directory.
@Model public final class DistributionRecord {
    @Attribute(.unique) public var id: UUID
    /// The show this distribution record belongs to. Always non-nil after insertion;
    /// optional to satisfy SwiftData inverse relationship requirements.
    public var show: Show?
    public var targetID: String
    public var status: DistributionStatus
    public var externalShowID: String?
    public var submittedAt: Date?
    public var lastCheckedAt: Date?
    public var note: String?

    public init(
        id: UUID = UUID(),
        show: Show? = nil,
        targetID: String,
        status: DistributionStatus = .notSubmitted,
        externalShowID: String? = nil,
        submittedAt: Date? = nil,
        lastCheckedAt: Date? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.show = show
        self.targetID = targetID
        self.status = status
        self.externalShowID = externalShowID
        self.submittedAt = submittedAt
        self.lastCheckedAt = lastCheckedAt
        self.note = note
    }
}
