import Foundation
import CommonCrypto

/// Distribution target for the [Podcast Index](https://podcastindex.org) directory.
///
/// Uses the Podcast Index API for programmatic feed submission and status checks.
public struct PodcastIndexTarget: DistributionTarget, Sendable {

    public let targetID = "podcastindex"
    public let displayName = "Podcast Index"
    public let mode: DistributionMode = .api

    private let apiKey: String
    private let apiSecret: String
    private let baseURL: URL
    private let session: URLSession

    /// Creates a Podcast Index distribution target.
    ///
    /// - Parameters:
    ///   - apiKey: Podcast Index API key.
    ///   - apiSecret: Podcast Index API secret.
    ///   - baseURL: API base URL. Defaults to `https://api.podcastindex.org`.
    ///   - session: URL session for network requests.
    public init(
        apiKey: String,
        apiSecret: String,
        baseURL: URL = URL(string: "https://api.podcastindex.org")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - DistributionTarget

    public func submit(feedURL: URL, show: ShowSnapshot) async throws -> DistributionSubmission {
        let url = baseURL.appendingPathComponent("api/1.0/add/byfeedurl")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "url", value: feedURL.absoluteString)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        applyAuth(&request)

        let (data, response) = try await session.data(for: request)
        try validate(response, context: "submit")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let feedID = (json?["feed"] as? [String: Any])?["id"] as? Int
            ?? (json?["feedId"] as? Int)

        guard let id = feedID else {
            throw PodedgeError.distributionFailed(target: targetID, reason: "No feed ID in response")
        }

        return DistributionSubmission(
            externalShowID: String(id),
            status: .pending,
            note: "Submitted to Podcast Index"
        )
    }

    public func refreshStatus(externalShowID: String) async throws -> DistributionStatus {
        let url = baseURL.appendingPathComponent("api/1.0/podcasts/byfeedid")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: externalShowID)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        applyAuth(&request)

        let (data, response) = try await session.data(for: request)
        try validate(response, context: "refreshStatus")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let status = json?["status"] as? String

        if status == "true" {
            return .live
        }
        return .pending
    }

    // MARK: - Private

    private func applyAuth(_ request: inout URLRequest) {
        let epoch = String(Int(Date().timeIntervalSince1970))
        let hashInput = "\(apiKey)\(apiSecret)\(epoch)"
        let hash = sha1Hex(hashInput)

        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Key")
        request.setValue(epoch, forHTTPHeaderField: "X-Auth-Date")
        request.setValue(hash, forHTTPHeaderField: "X-Auth-Hash")
        request.setValue("PodedgeCore/1.0", forHTTPHeaderField: "User-Agent")
    }

    private func sha1Hex(_ string: String) -> String {
        let data = string.data(using: .utf8)!
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA1(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func validate(_ response: URLResponse, context: String) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PodedgeError.distributionFailed(target: targetID, reason: "\(context) returned status \(code)")
        }
    }
}
