import Foundation
import Testing

@testable import PodedgeCore

/// A mock keychain service for testing ``HostService``.
private actor MockKeychainService {
    private var credentials: [String: HostCredential] = [:]

    func store(_ credential: HostCredential, forKey key: String) {
        credentials[key] = credential
    }

    func load(forKey key: String) -> HostCredential? {
        credentials[key]
    }
}

@Suite("HostService")
struct HostServiceTests {

    private static let testBinding = HostBindingSnapshot(
        id: UUID(),
        kind: .s3,
        displayName: "Test Host",
        bucket: "test-bucket",
        region: "us-east-1",
        prefix: "podcasts",
        publicBaseURL: URL(string: "https://cdn.example.com")!,
        keychainRef: "test-key"
    )

    @Test("resolveHost returns S3Host when credential exists")
    func resolveHostSuccess() async throws {
        let keychain = KeychainService(service: "com.podedge.test.hostservice.\(UUID().uuidString)")
        try await keychain.storeCredential(
            HostCredential(accessKeyID: "AKIA", secretAccessKey: "secret"),
            forKey: "test-key"
        )

        let service = HostService(keychain: keychain)
        let host = try await service.resolveHost(binding: Self.testBinding)
        // Verify it's an S3Host by checking publicURL behavior.
        let url = host.publicURL(for: "ep1.mp3")
        #expect(url.absoluteString.contains("cdn.example.com"))
    }

    @Test("resolveHost throws keychainFailure when credential is missing")
    func resolveHostMissingCredential() async throws {
        let keychain = KeychainService(service: "com.podedge.test.hostservice.empty.\(UUID().uuidString)")

        let service = HostService(keychain: keychain)
        await #expect(throws: PodedgeError.self) {
            try await service.resolveHost(binding: Self.testBinding)
        }
    }
}
