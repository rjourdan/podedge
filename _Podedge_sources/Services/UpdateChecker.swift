import Foundation

/// Checks for new releases on GitHub.
actor UpdateChecker {
    /// The GitHub repository in `owner/repo` format.
    private let repository: String
    private let session: URLSession

    /// The latest known release tag, if any.
    private(set) var latestVersion: String?

    /// Whether an update is available compared to the current bundle version.
    private(set) var updateAvailable = false

    init(repository: String = "podedge/podedge", session: URLSession = .shared) {
        self.repository = repository
        self.session = session
    }

    /// Fetches the latest release from GitHub and compares to the current version.
    func checkForUpdate() async {
        let urlString = "https://api.github.com/repos/\(repository)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            latestVersion = release.tagName

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            updateAvailable = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v")) != currentVersion
        } catch {
            // Silently fail — update checks are best-effort.
        }
    }
}

/// Minimal GitHub release response.
private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
