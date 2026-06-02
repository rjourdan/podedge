import Foundation
import SwiftData

/// Lists jobs, optionally filtered by state.
public struct ListJobsTool: ToolDefinition, Sendable {
    public let name = "jobs.list"
    public let description = "Lists jobs, optionally filtered by state."
    public let scope: ToolScope = .readOnly
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"state":"String?"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(ListJobsInput.self, from: input)
        let summaries = try await MainActor.run {
            let descriptor = FetchDescriptor<Job>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            var jobs = try store.modelContext.fetch(descriptor)
            if let stateFilter = params.state {
                jobs = jobs.filter { $0.state.rawValue == stateFilter }
            }
            return jobs.map { job in
                JobSummary(
                    id: job.id, kind: job.kind.rawValue, targetID: job.targetID,
                    state: job.state.rawValue, attempts: job.attempts, createdAt: job.createdAt
                )
            }
        }
        return try JSONEncoder().encode(ListJobsOutput(jobs: summaries))
    }
}
