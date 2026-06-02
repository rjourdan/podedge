import Foundation

/// Creates a new show in the library.
public struct CreateShowTool: ToolDefinition, Sendable {
    public let name = "show.create"
    public let description = "Creates a new podcast show."
    public let scope: ToolScope = .mutating
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"title":"String","author":"String","summary":"String","language":"String","category":"String","ownerEmail":"String","ownerName":"String"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(CreateShowInput.self, from: input)
        let snapshot = try await MainActor.run {
            let show = Show(
                title: params.title,
                author: params.author,
                summary: params.summary,
                language: params.language,
                category: params.category,
                ownerEmail: params.ownerEmail,
                ownerName: params.ownerName,
                hostBindingID: UUID(),
                feedRemotePath: "shows/\(params.title.lowercased().replacingOccurrences(of: " ", with: "-"))/feed.xml"
            )
            store.addShow(show)
            try store.save()
            return show.snapshot
        }
        return try JSONEncoder().encode(snapshot)
    }
}

/// Updates metadata fields on a show.
public struct UpdateShowMetadataTool: ToolDefinition, Sendable {
    public let name = "show.update_metadata"
    public let description = "Updates title, author, or summary on a show."
    public let scope: ToolScope = .mutating
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"showID":"UUID","title":"String?","author":"String?","summary":"String?"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(UpdateShowMetadataInput.self, from: input)
        let snapshot = try await MainActor.run {
            guard let show = try store.show(id: params.showID) else {
                throw PodedgeError.notFound(entity: "Show", id: params.showID.uuidString)
            }
            if let title = params.title { show.title = title }
            if let author = params.author { show.author = author }
            if let summary = params.summary { show.summary = summary }
            show.updatedAt = Date()
            try store.save()
            return show.snapshot
        }
        return try JSONEncoder().encode(snapshot)
    }
}

/// Deletes a show from the library.
public struct DeleteShowTool: ToolDefinition, Sendable {
    public let name = "show.delete"
    public let description = "Permanently deletes a show and all its episodes."
    public let scope: ToolScope = .destructive
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"showID":"UUID"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(DeleteShowInput.self, from: input)
        try await MainActor.run {
            guard let show = try store.show(id: params.showID) else {
                throw PodedgeError.notFound(entity: "Show", id: params.showID.uuidString)
            }
            store.deleteShow(show)
            try store.save()
        }
        return try JSONEncoder().encode(EmptyOutput())
    }
}
