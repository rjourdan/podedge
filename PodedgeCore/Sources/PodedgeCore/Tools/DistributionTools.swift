import Foundation

/// Returns distribution status records for a show.
public struct GetDistributionStatusTool: ToolDefinition, Sendable {
    public let name = "distribution.get_status"
    public let description = "Returns distribution records for a show across all directories."
    public let scope: ToolScope = .readOnly
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"showID":"UUID"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(GetDistributionStatusInput.self, from: input)
        let records = try await MainActor.run {
            try store.distributions(for: params.showID).map { rec in
                DistributionRecordSummary(
                    id: rec.id,
                    targetID: rec.targetID,
                    status: rec.status.rawValue,
                    externalShowID: rec.externalShowID,
                    submittedAt: rec.submittedAt
                )
            }
        }
        return try JSONEncoder().encode(DistributionStatusOutput(records: records))
    }
}
