import Foundation

/// Posts to Bluesky via the AT Protocol.
public struct BlueskyTarget: SocialPostingTarget {
    public let platformID = "bluesky"
    public let displayName = "Bluesky"
    public let mode: SocialPostingMode = .api

    private let handle: String
    private let keychainService: KeychainService
    private let keychainRef: String
    private let session: URLSession

    public init(handle: String, keychainService: KeychainService, keychainRef: String, session: URLSession = .shared) {
        self.handle = handle
        self.keychainService = keychainService
        self.keychainRef = keychainRef
        self.session = session
    }

    public func post(text: String, episodeURL: URL?) async throws -> SocialPostResult {
        let password = try await loadPassword()
        let session = try await createSession(password: password)
        let truncated = truncateAtWordBoundary(text, limit: 300)
        let uri = try await createRecord(session: session, text: truncated)
        return SocialPostResult(postURI: uri, mode: .api)
    }

    // MARK: - Private

    private func loadPassword() async throws -> String {
        guard let data = try await keychainService.load(forKey: keychainRef) else {
            throw PodedgeError.socialPostFailed(platform: "bluesky", reason: "No credentials found in keychain")
        }
        guard let password = String(data: data, encoding: .utf8) else {
            throw PodedgeError.socialPostFailed(platform: "bluesky", reason: "Invalid credential data")
        }
        return password
    }

    private struct SessionResponse: Decodable {
        let accessJwt: String
        let did: String
    }

    private func createSession(password: String) async throws -> SessionResponse {
        let url = URL(string: "https://bsky.social/xrpc/com.atproto.server.createSession")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["identifier": handle, "password": password]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode == 401 {
            throw PodedgeError.socialPostFailed(platform: "bluesky", reason: "Invalid credentials")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PodedgeError.socialPostFailed(platform: "bluesky", reason: "HTTP \(httpResponse.statusCode): \(body)")
        }
        return try JSONDecoder().decode(SessionResponse.self, from: data)
    }

    private struct CreateRecordResponse: Decodable {
        let uri: String
    }

    private func createRecord(session: SessionResponse, text: String) async throws -> String {
        let url = URL(string: "https://bsky.social/xrpc/com.atproto.repo.createRecord")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessJwt)", forHTTPHeaderField: "Authorization")

        let record: [String: String] = [
            "$type": "app.bsky.feed.post",
            "text": text,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let payload: [String: Any] = [
            "repo": session.did,
            "collection": "app.bsky.feed.post",
            "record": record,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await self.session.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PodedgeError.socialPostFailed(platform: "bluesky", reason: "HTTP \(httpResponse.statusCode): \(body)")
        }
        let result = try JSONDecoder().decode(CreateRecordResponse.self, from: data)
        return result.uri
    }
}

// MARK: - Text Truncation

func truncateAtWordBoundary(_ text: String, limit: Int) -> String {
    guard text.count > limit else { return text }
    let truncLimit = limit - 1 // Room for "…"
    let prefix = text.prefix(truncLimit)
    if let lastSpace = prefix.lastIndex(of: " ") {
        return String(prefix[prefix.startIndex..<lastSpace]) + "…"
    }
    return String(prefix) + "…"
}
