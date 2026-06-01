import Foundation

/// Manages registered social posting targets and dispatches posts.
public actor SocialPostingService {
    private var targets: [String: any SocialPostingTarget] = [:]

    public init() {}

    /// Registers a target for its platform identifier.
    public func register(_ target: any SocialPostingTarget) {
        targets[target.platformID] = target
    }

    /// Posts text to the specified platform.
    public func post(platformID: String, text: String, episodeURL: URL?) async throws -> SocialPostResult {
        guard let target = targets[platformID] else {
            throw PodedgeError.socialPostFailed(platform: platformID, reason: "No target registered for platform")
        }
        return try await target.post(text: text, episodeURL: episodeURL)
    }

    /// Returns all registered targets.
    public func allTargets() -> [any SocialPostingTarget] {
        Array(targets.values)
    }

    /// Returns the target for a given platform, if registered.
    public func target(for platformID: String) -> (any SocialPostingTarget)? {
        targets[platformID]
    }
}
