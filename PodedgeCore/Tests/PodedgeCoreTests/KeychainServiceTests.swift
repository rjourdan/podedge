import Foundation
import Testing

@testable import PodedgeCore

@Suite("KeychainService")
struct KeychainServiceTests {

    /// Returns a unique service identifier to isolate each test.
    private func makeService() -> KeychainService {
        KeychainService(service: "com.podedge.test.\(UUID().uuidString)")
    }

    @Test("Store and load raw data")
    func storeAndLoadRawData() async throws {
        let service = makeService()
        let key = "test-raw-\(UUID().uuidString)"
        let data = Data("hello keychain".utf8)

        try await service.store(data: data, forKey: key)
        let loaded = try await service.load(forKey: key)

        #expect(loaded == data)

        // Cleanup
        try await service.delete(forKey: key)
    }

    @Test("Store and load HostCredential")
    func storeAndLoadCredential() async throws {
        let service = makeService()
        let key = "test-cred-\(UUID().uuidString)"
        let credential = HostCredential(
            accessKeyID: "AKIAEXAMPLE",
            secretAccessKey: "secret123",
            endpoint: URL(string: "https://s3.example.com")
        )

        try await service.storeCredential(credential, forKey: key)
        let loaded = try await service.loadCredential(forKey: key)

        let result = try #require(loaded)
        #expect(result.accessKeyID == "AKIAEXAMPLE")
        #expect(result.secretAccessKey == "secret123")
        #expect(result.endpoint == URL(string: "https://s3.example.com"))

        // Cleanup
        try await service.delete(forKey: key)
    }

    @Test("Delete removes stored data")
    func deleteRemovesData() async throws {
        let service = makeService()
        let key = "test-delete-\(UUID().uuidString)"
        let data = Data("to be deleted".utf8)

        try await service.store(data: data, forKey: key)
        try await service.delete(forKey: key)

        let loaded = try await service.load(forKey: key)
        #expect(loaded == nil)
    }

    @Test("Load non-existent key returns nil")
    func loadNonExistentReturnsNil() async throws {
        let service = makeService()
        let loaded = try await service.load(forKey: "nonexistent-\(UUID().uuidString)")
        #expect(loaded == nil)
    }

    @Test("Overwrite existing key")
    func overwriteExistingKey() async throws {
        let service = makeService()
        let key = "test-overwrite-\(UUID().uuidString)"
        let original = Data("original".utf8)
        let updated = Data("updated".utf8)

        try await service.store(data: original, forKey: key)
        try await service.store(data: updated, forKey: key)

        let loaded = try await service.load(forKey: key)
        #expect(loaded == updated)

        // Cleanup
        try await service.delete(forKey: key)
    }

    @Test("Load credential for non-existent key returns nil")
    func loadCredentialNonExistent() async throws {
        let service = makeService()
        let loaded = try await service.loadCredential(forKey: "no-cred-\(UUID().uuidString)")
        #expect(loaded == nil)
    }
}
