import Foundation
import SwiftData

/// Namespace for the Podedge SwiftData schema and container factory.
public enum PodedgeSchema {

    /// All SwiftData model types managed by PodedgeCore.
    public static let modelTypes: [any PersistentModel.Type] = [
        Show.self,
        Episode.self,
        Asset.self,
        HostBinding.self,
        AnalyticsBinding.self,
        DistributionRecord.self,
        Job.self,
        AnalyticsSnapshot.self,
        AgentAuditEntry.self,
    ]

    /// Creates a ``ModelContainer`` configured for the Podedge schema.
    ///
    /// - Parameters:
    ///   - inMemory: When `true`, uses an in-memory store (useful for tests and previews).
    ///   - url: Optional file URL for the store. When `nil` and `inMemory` is `false`,
    ///     SwiftData uses its default location.
    public static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(modelTypes)
        var config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        } else if let url {
            config = ModelConfiguration(
                schema: schema,
                url: url
            )
        } else {
            config = ModelConfiguration(
                "Podedge",
                schema: schema
            )
        }
        return try ModelContainer(for: schema, configurations: [config])
    }
}
