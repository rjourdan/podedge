import Foundation

/// Distribution target that sends a [Podping](https://podping.org) notification
/// to announce feed updates to the podcast ecosystem.
///
/// Podping is a decentralized notification system. This implementation posts
/// to the Podping API endpoint.
public struct PodpingTarget: DistributionTarget, Sendable {

    public let targetID = "podping"
    public let displayName = "Podping"
    public let mode: DistributionMode = .api

    private let baseURL: URL
    private let session: URLSession

    /// Creates a Podping distribution target.
    ///
    /// - Parameters:
    ///   - baseURL: The Podping API base URL.
    ///   - session: URL session for network requests.
    public init(
        baseURL: URL = URL(string: "https://podping.cloud")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - DistributionTarget

    public func submit(feedURL: URL, show: ShowSnapshot) async throws -> DistributionSubmission {
        let url = baseURL.appendingPathComponent("api/ping")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "url": feedURL.absoluteString,
            "reason": "update",
            "medium": "podcast",
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PodedgeError.distributionFailed(target: targetID, reason: "Podping returned status \(code)")
        }

        return DistributionSubmission(
            externalShowID: feedURL.absoluteString,
            status: .live,
            note: "Podping notification sent"
        )
    }

    public func refreshStatus(externalShowID: String) async throws -> DistributionStatus {
        // Podping is fire-and-forget; there's no status to refresh.
        .live
    }
}
