import Foundation
import Testing

@testable import PodedgeCore

@Suite("BlueskyTarget", .serialized)
struct BlueskyTargetTests {

    private let keychainService = KeychainService(service: "com.podedge.test.bluesky.\(UUID())")
    private let keychainRef = "bluesky-test-password"

    init() {
        StubURLProtocol.removeStubs(withPathContaining: "bsky.social")
    }

    private func makeTarget(session: URLSession = makeStubSession()) async throws -> BlueskyTarget {
        try await keychainService.store(data: Data("test-password".utf8), forKey: keychainRef)
        return BlueskyTarget(
            handle: "user.bsky.social",
            keychainService: keychainService,
            keychainRef: keychainRef,
            session: session
        )
    }

    private func stubSession(accessJwt: String = "jwt123", did: String = "did:plc:abc") {
        let sessionJSON = """
        {"accessJwt":"\(accessJwt)","did":"\(did)"}
        """.data(using: .utf8)!
        StubURLProtocol.stub(
            path: "com.atproto.server.createSession",
            response: .init(statusCode: 200, body: sessionJSON)
        )
    }

    private func stubRecord(uri: String = "at://did:plc:abc/app.bsky.feed.post/123") {
        let recordJSON = """
        {"uri":"\(uri)"}
        """.data(using: .utf8)!
        StubURLProtocol.stub(
            path: "com.atproto.repo.createRecord",
            response: .init(statusCode: 200, body: recordJSON)
        )
    }

    @Test("Successful post returns URI with api mode")
    func postSuccessReturnsURI() async throws {
        stubSession()
        stubRecord(uri: "at://did:plc:abc/app.bsky.feed.post/456")

        let target = try await makeTarget()
        let result = try await target.post(text: "Hello Bluesky!", episodeURL: nil)

        #expect(result.postURI == "at://did:plc:abc/app.bsky.feed.post/456")
        #expect(result.mode == .api)
    }

    @Test("401 from createSession throws socialPostFailed with Invalid credentials")
    func postFailsOn401() async throws {
        StubURLProtocol.stub(
            path: "com.atproto.server.createSession",
            response: .init(statusCode: 401, body: Data())
        )

        let target = try await makeTarget()

        do {
            _ = try await target.post(text: "Hello", episodeURL: nil)
            Issue.record("Expected socialPostFailed error")
        } catch let error as PodedgeError {
            if case .socialPostFailed(let platform, let reason) = error {
                #expect(platform == "bluesky")
                #expect(reason == "Invalid credentials")
            } else {
                Issue.record("Wrong error case: \(error)")
            }
        }
    }

    @Test("Text longer than 300 chars is truncated at word boundary")
    func textTruncatedToLimit() {
        let longText = String(repeating: "word ", count: 80) // 400 chars
        let truncated = truncateAtWordBoundary(longText, limit: 300)

        #expect(truncated.count <= 300)
        #expect(truncated.hasSuffix("…"))
    }

    @Test("Empty text posts successfully")
    func emptyTextPostsSuccessfully() async throws {
        stubSession()
        stubRecord()

        let target = try await makeTarget()
        let result = try await target.post(text: "", episodeURL: nil)

        #expect(result.mode == .api)
    }
}
