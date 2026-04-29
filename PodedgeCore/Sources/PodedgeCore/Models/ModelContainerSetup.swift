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
    ]

    /// Creates a ``ModelContainer`` configured for the Podedge schema.
    ///
    /// - Parameter inMemory: When `true`, uses an in-memory store (useful for tests and previews).
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let config = ModelConfiguration(
            "Podedge",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
