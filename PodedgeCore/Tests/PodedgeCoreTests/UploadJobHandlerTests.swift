import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

@Suite("UploadJobHandler", .serialized, .tags(.swiftData))
@MainActor
struct UploadJobHandlerTests {

    private static let db = "uploadJobHandler"

    private func makeContainer() throws -> ModelContainer {
        let container = TestDatabase.container(for: Self.db)
        try TestDatabase.reset(container)
        return container
    }

    @Test("Handler decodes payload JSON correctly and uploads")
    func testDecodesPayloadJSON() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mp3")
        try Data(repeating: 0xAB, count: 64).write(to: fileURL)
        let asset = Asset(kind: .audioOriginal, localURL: fileURL, sha256: "abc", byteSize: 64, contentType: "audio/mpeg")
        context.insert(asset)

        let keychainRef = "upload-decode-\(UUID())"
        let binding = HostBinding(
            displayName: "Test", bucket: "decode-bucket", region: "us-east-1",
            publicBaseURL: URL(string: "https://cdn.test.com")!,
            keychainRef: keychainRef
        )
        context.insert(binding)

        let payload = """
        {"assetID":"\(asset.id.uuidString)","remotePath":"shows/ep/audio.mp3","contentType":"audio/mpeg","hostBindingID":"\(binding.id.uuidString)"}
        """
        let job = Job(kind: .upload, targetID: asset.id, payloadJSON: payload)
        context.insert(job)
        try context.save()

        // Setup stubs for both HEAD and PUT on S3.
        StubURLProtocol.stub(path: "decode-bucket", response: .init(statusCode: 200, body: Data()))

        let session = makeStubSession()
        let keychain = KeychainService(service: "com.podedge.test.upload.decode")
        try await keychain.storeCredential(
            HostCredential(accessKeyID: "AKIA", secretAccessKey: "secret"),
            forKey: keychainRef
        )
        let hostService = HostService(keychain: keychain, sessionProvider: { session })
        let handler = UploadJobHandler(hostService: hostService)

        try await handler.execute(jobID: job.id, container: container)

        // Re-fetch asset from a fresh context since handler uses its own ModelContext.
        let freshContext = ModelContext(container)
        let assetID = asset.id
        var assetDesc = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID })
        assetDesc.fetchLimit = 1
        let updated = try freshContext.fetch(assetDesc).first
        #expect(updated?.remotePath == "shows/ep/audio.mp3")
        #expect(updated?.remoteURL != nil)
    }

    @Test("Handler throws when asset is missing")
    func testThrowsWhenAssetMissing() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let binding = HostBinding(
            displayName: "Test", bucket: "b", region: "us-east-1",
            publicBaseURL: URL(string: "https://cdn.test.com")!,
            keychainRef: "k"
        )
        context.insert(binding)

        let missingAssetID = UUID()
        let payload = """
        {"assetID":"\(missingAssetID.uuidString)","remotePath":"x.mp3","contentType":"audio/mpeg","hostBindingID":"\(binding.id.uuidString)"}
        """
        let job = Job(kind: .upload, targetID: missingAssetID, payloadJSON: payload)
        context.insert(job)
        try context.save()

        let keychain = KeychainService(service: "com.podedge.test.upload.missing.\(UUID())")
        let hostService = HostService(keychain: keychain)
        let handler = UploadJobHandler(hostService: hostService)

        await #expect(throws: PodedgeError.self) {
            try await handler.execute(jobID: job.id, container: container)
        }
    }

    @Test("Handler updates asset remotePath on success")
    func testUpdatesAssetRemotePath() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mp3")
        try Data(repeating: 0xCD, count: 32).write(to: fileURL)
        let asset = Asset(kind: .audioOriginal, localURL: fileURL, sha256: "def", byteSize: 32, contentType: "audio/mpeg")
        context.insert(asset)
        #expect(asset.remotePath == nil)

        let keychainRef = "upload-update-\(UUID())"
        let binding = HostBinding(
            displayName: "Test", bucket: "update-bucket", region: "us-east-1",
            publicBaseURL: URL(string: "https://cdn.test.com")!,
            keychainRef: keychainRef
        )
        context.insert(binding)

        let payload = """
        {"assetID":"\(asset.id.uuidString)","remotePath":"episodes/test.mp3","contentType":"audio/mpeg","hostBindingID":"\(binding.id.uuidString)"}
        """
        let job = Job(kind: .upload, targetID: asset.id, payloadJSON: payload)
        context.insert(job)
        try context.save()

        StubURLProtocol.stub(path: "update-bucket", response: .init(statusCode: 200, body: Data()))
        let session = makeStubSession()
        let keychain = KeychainService(service: "com.podedge.test.upload.update")
        try await keychain.storeCredential(
            HostCredential(accessKeyID: "AKIA", secretAccessKey: "secret"),
            forKey: keychainRef
        )
        let hostService = HostService(keychain: keychain, sessionProvider: { session })
        let handler = UploadJobHandler(hostService: hostService)

        try await handler.execute(jobID: job.id, container: container)

        // Re-fetch from fresh context since handler uses its own ModelContext.
        let freshContext = ModelContext(container)
        let assetID = asset.id
        var assetDesc = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID })
        assetDesc.fetchLimit = 1
        let updated = try freshContext.fetch(assetDesc).first
        #expect(updated?.remotePath == "episodes/test.mp3")
        #expect(updated?.remoteURL != nil)
    }
}
