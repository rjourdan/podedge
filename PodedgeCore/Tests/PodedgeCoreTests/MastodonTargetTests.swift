import Foundation
import Testing

@testable import PodedgeCore

@Suite("MastodonTarget", .serialized)
struct MastodonTargetTests {

    private let keychainService = KeychainService(service: "com.podedge.test.mastodon.\(UUID())")
    private let keychainRef = "mastodon-test-token"
    private let serverURL = URL(string: "https://mastodon.social")!

    init() {
        StubURLProtocol.removeStubs(withPathContaining: "api/v1/statuses")
    }

    private func makeTarget(session: URLSession = makeStubSession()) async throws -> MastodonTarget {
        try await keychainService.store(data: Data("test-token".utf8), forKey: keychainRef)
        return MastodonTarget(
            serverURL: serverURL,
            keychainService: keychainService,
            keychainRef: keychainRef,
            session: session
        )
    }

    @Test("Successful post returns URI")
    func postSuccessReturnsURI() async throws {
        let json = #"{"url":"https://mastodon.social/@user/12345"}"#.data(using: .utf8)!
        StubURLProtocol.stub(
            path: "api/v1/statuses",
            response: .init(statusCode: 200, body: json)
        )

        let target = try await makeTarget()
        let result = try await target.post(text: "Hello Mastodon!", episodeURL: nil)

        #expect(result.postURI == "https://mastodon.social/@user/12345")
        #expect(result.mode == .api)
    }

    @Test("Non-2xx response throws socialPostFailed")
    func postFailsOnNon2xx() async throws {
        StubURLProtocol.stub(
            path: "api/v1/statuses",
            response: .init(statusCode: 403, body: Data("Forbidden".utf8))
        )

        let target = try await makeTarget()

        do {
            _ = try await target.post(text: "Hello", episodeURL: nil)
            Issue.record("Expected socialPostFailed error")
        } catch let error as PodedgeError {
            if case .socialPostFailed(let platform, let reason) = error {
                #expect(platform == "mastodon")
                #expect(reason.contains("403"))
            } else {
                Issue.record("Wrong error case: \(error)")
            }
        }
    }

    @Test("Text longer than 500 chars is truncated at word boundary")
    func textTruncatedTo500() {
        let longText = String(repeating: "hello ", count: 100) // 600 chars
        let truncated = truncateAtWordBoundary(longText, limit: 500)

        #expect(truncated.count <= 500)
        #expect(truncated.hasSuffix("…"))
    }

    @Test("CopyPasteTarget never throws for various inputs")
    func copyPasteTargetNeverThrows() async throws {
        let target = CopyPasteTarget(platformID: "clipboard", displayName: "Clipboard")
        let inputs = ["", "Normal text", String(repeating: "x", count: 500)]

        for input in inputs {
            let result = try await target.post(text: input, episodeURL: nil)
            #expect(result.mode == .copyPaste)
        }
    }
}
