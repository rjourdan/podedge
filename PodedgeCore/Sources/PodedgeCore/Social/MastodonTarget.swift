import Foundation

/// Posts to a Mastodon instance via its REST API.
public struct MastodonTarget: SocialPostingTarget {
    public let platformID = "mastodon"
    public let displayName = "Mastodon"
    public let mode: SocialPostingMode = .api

    private let serverURL: URL
    private let keychainService: KeychainService
    private let keychainRef: String
    private let session: URLSession

    public init(serverURL: URL, keychainService: KeychainService, keychainRef: String, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.keychainService = keychainService
        self.keychainRef = keychainRef
        self.session = session
    }

    public func post(text: String, episodeURL: URL?) async throws -> SocialPostResult {
        let token = try await loadToken()
        let truncated = truncateAtWordBoundary(text, limit: 500)
        let postURL = try await createStatus(token: token, text: truncated)
        return SocialPostResult(postURI: postURL, mode: .api)
    }

    // MARK: - Private

    private func loadToken() async throws -> String {
        guard let data = try await keychainService.load(forKey: keychainRef) else {
            throw PodedgeError.socialPostFailed(platform: "mastodon", reason: "No access token found in keychain")
        }
        guard let token = String(data: data, encoding: .utf8) else {
            throw PodedgeError.socialPostFailed(platform: "mastodon", reason: "Invalid token data")
        }
        return token
    }

    private struct StatusResponse: Decodable {
        let url: String
    }

    private func createStatus(token: String, text: String) async throws -> String {
        let url = serverURL.appendingPathComponent("api/v1/statuses")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "status", value: text)]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PodedgeError.socialPostFailed(platform: "mastodon", reason: "HTTP \(httpResponse.statusCode): \(body)")
        }
        let result = try JSONDecoder().decode(StatusResponse.self, from: data)
        return result.url
    }
}
