import Foundation

/// Tests connectivity to a host binding.
public struct TestBindingTool: ToolDefinition, Sendable {
    public let name = "host.test_binding"
    public let description = "Tests whether the host binding is reachable."
    public let scope: ToolScope = .mutating
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"bindingID":"UUID"}"#

    private let store: LibraryStore
    private let hostService: HostService

    public init(store: LibraryStore, hostService: HostService) {
        self.store = store
        self.hostService = hostService
    }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(TestBindingInput.self, from: input)
        let snapshot = try await MainActor.run {
            guard let binding = try store.hostBinding(id: params.bindingID) else {
                throw PodedgeError.notFound(entity: "HostBinding", id: params.bindingID.uuidString)
            }
            return binding.snapshot
        }
        let reachable: Bool
        do {
            _ = try await hostService.resolveHost(binding: snapshot)
            reachable = true
        } catch {
            reachable = false
        }
        return try JSONEncoder().encode(TestBindingOutput(reachable: reachable))
    }
}

/// Removes a host binding from the library.
public struct RemoveBindingTool: ToolDefinition, Sendable {
    public let name = "host.remove_binding"
    public let description = "Permanently removes a host binding."
    public let scope: ToolScope = .destructive
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"bindingID":"UUID"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(RemoveBindingInput.self, from: input)
        try await MainActor.run {
            guard let binding = try store.hostBinding(id: params.bindingID) else {
                throw PodedgeError.notFound(entity: "HostBinding", id: params.bindingID.uuidString)
            }
            store.deleteHostBinding(binding)
            try store.save()
        }
        return try JSONEncoder().encode(EmptyOutput())
    }
}
