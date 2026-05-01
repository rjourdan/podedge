import Foundation
import os

/// Analytics provider backed by [OP3](https://op3.dev), the open podcast prefix project.
///
/// OP3 works by prefixing enclosure URLs so downloads route through their servers
/// before redirecting to the original file. The prefix format is:
/// `https://op3.dev/e/<original-url-without-scheme>`
public struct OP3AnalyticsProvider: AnalyticsProvider, Sendable {

    public let providerName = "op3"

    private let baseURL: URL
    private let apiToken: String?
    private let session: URLSession
    private let logger = PodedgeLogger.analytics

    /// Creates an OP3 analytics provider.
    ///
    /// - Parameters:
    ///   - baseURL: The OP3 base URL. Defaults to `https://op3.dev`.
    ///   - apiToken: Optional bearer token for authenticated API access.
    ///   - session: URL session for network requests.
    public init(
        baseURL: URL = URL(string: "https://op3.dev")!,
        apiToken: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.session = session
    }

    // MARK: - AnalyticsProvider

    public func register(feedURL: URL, podcastGUID: UUID) async throws -> String {
        // OP3 registration: POST /api/1/shows with the feed URL and podcast GUID.
        // The response includes a showUuid that serves as the external show ID.
        let url = baseURL.appendingPathComponent("api/1/shows")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)

        let body = [
            "podcastGuid": podcastGUID.uuidString.lowercased(),
            "feedUrl": feedURL.absoluteString,
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, context: "register")

        // Parse showUuid from response.
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let showUUID = json?["showUuid"] as? String else {
            throw PodedgeError.analyticsUnavailable(reason: "OP3 register response missing showUuid")
        }
        return showUUID
    }

    public func prefixURL(for enclosureURL: URL) -> URL {
        // Format: https://op3.dev/e/<original-url-without-scheme>
        // Use explicit string building to avoid appendingPathComponent percent-encoding slashes.
        let stripped = enclosureURL.absoluteString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return URL(string: baseURL.absoluteString + "/e/" + stripped)!
    }

    public func fetchSnapshot(
        externalShowID: String,
        window: DateInterval
    ) async throws -> AnalyticsFetchResult {
        // OP3 API: GET /api/1/shows/{showUuid}/downloads?start=...&end=...
        // TODO: Confirm exact OP3 endpoint shape when network access is available.
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/1/shows/\(externalShowID)/downloads"),
            resolvingAgainstBaseURL: false
        )!
        let iso = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "start", value: iso.string(from: window.start)),
            URLQueryItem(name: "end", value: iso.string(from: window.end)),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        applyAuth(&request)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, context: "fetchSnapshot")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let downloads = json?["downloads"] as? Int ?? 0
        let uniqueListeners = json?["uniqueListeners"] as? Int ?? 0
        let appBreakdown = json?["apps"] as? [String: Int] ?? [:]
        let geoBreakdown = json?["geos"] as? [String: Int] ?? [:]

        return AnalyticsFetchResult(
            downloads: downloads,
            uniqueListeners: uniqueListeners,
            appBreakdown: appBreakdown,
            geoBreakdown: geoBreakdown
        )
    }

    // MARK: - Private

    private func applyAuth(_ request: inout URLRequest) {
        if let token = apiToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func validateResponse(_ response: URLResponse, context: String) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PodedgeError.analyticsUnavailable(reason: "OP3 \(context) returned status \(code)")
        }
    }
}
