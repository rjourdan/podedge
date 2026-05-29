import Foundation
import SwiftData

/// Bridges the job scheduler to ``HostService``, executing `.upload` jobs.
public struct UploadJobHandler: JobHandler, Sendable {

    public let handledKind: JobKind = .upload

    private let hostService: HostService

    /// Creates a handler that delegates uploads to the given host service.
    ///
    /// - Parameter hostService: The service used to resolve hosts and upload assets.
    public init(hostService: HostService) {
        self.hostService = hostService
    }

    public func execute(jobID: UUID, container: ModelContainer) async throws {
        let context = ModelContext(container)

        // Fetch job.
        var jobDescriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        jobDescriptor.fetchLimit = 1
        guard let job = try context.fetch(jobDescriptor).first else {
            throw PodedgeError.notFound(entity: "Job", id: jobID.uuidString)
        }

        // Decode payload.
        guard let payloadJSON = job.payloadJSON,
              let payloadData = payloadJSON.data(using: .utf8) else {
            throw PodedgeError.preconditionViolated(reason: "Upload job missing payloadJSON")
        }
        let payload = try JSONDecoder().decode(UploadPayload.self, from: payloadData)

        // Fetch asset.
        let assetID = payload.assetID
        var assetDescriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID })
        assetDescriptor.fetchLimit = 1
        guard let asset = try context.fetch(assetDescriptor).first else {
            throw PodedgeError.notFound(entity: "Asset", id: assetID.uuidString)
        }

        // Fetch host binding.
        let hostBindingID = payload.hostBindingID
        var bindingDescriptor = FetchDescriptor<HostBinding>(predicate: #Predicate { $0.id == hostBindingID })
        bindingDescriptor.fetchLimit = 1
        guard let binding = try context.fetch(bindingDescriptor).first else {
            throw PodedgeError.notFound(entity: "HostBinding", id: hostBindingID.uuidString)
        }

        // Resolve host and upload.
        let host = try await hostService.resolveHost(binding: binding.snapshot)
        let remoteURL = try await host.put(
            localURL: asset.localURL,
            remotePath: payload.remotePath,
            contentType: payload.contentType,
            progress: { _ in }
        )

        // Update asset.
        asset.remotePath = payload.remotePath
        asset.remoteURL = remoteURL
        try context.save()
    }
}

// MARK: - Payload

private struct UploadPayload: Codable {
    var assetID: UUID
    var remotePath: String
    var contentType: String
    var hostBindingID: UUID
}
