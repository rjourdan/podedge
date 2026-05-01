import Foundation
import os

/// Coordinates distribution of podcast feeds to multiple directories.
///
/// Manages a registry of ``DistributionTarget`` implementations and provides
/// batch submission and status refresh operations.
public actor DistributionService {

    private var targets: [String: any DistributionTarget] = [:]
    private let logger = PodedgeLogger.general

    public init() {}

    /// Registers a distribution target.
    ///
    /// - Parameter target: The target to register. Replaces any existing target with the same ID.
    public func register(_ target: any DistributionTarget) {
        targets[target.targetID] = target
    }

    /// Returns all registered target IDs.
    public var registeredTargetIDs: [String] {
        Array(targets.keys)
    }

    /// Submits a feed to a specific distribution target.
    ///
    /// - Parameters:
    ///   - targetID: The ID of the registered target.
    ///   - feedURL: The public URL of the show's RSS feed.
    ///   - show: A sendable snapshot of the show.
    /// - Returns: The submission result.
    public func submit(
        targetID: String,
        feedURL: URL,
        show: ShowSnapshot
    ) async throws -> DistributionSubmission {
        guard let target = targets[targetID] else {
            throw PodedgeError.distributionFailed(target: targetID, reason: "No target registered with ID '\(targetID)'")
        }
        logger.info("Submitting to \(target.displayName, privacy: .public)")
        let result = try await target.submit(feedURL: feedURL, show: show)
        logger.info("Submission to \(target.displayName, privacy: .public): \(result.status.rawValue, privacy: .public)")
        return result
    }

    /// Refreshes the submission status for a previously submitted show.
    ///
    /// - Parameters:
    ///   - targetID: The ID of the registered target.
    ///   - externalShowID: The ID returned by a prior submission.
    /// - Returns: The current distribution status.
    public func refreshStatus(
        targetID: String,
        externalShowID: String
    ) async throws -> DistributionStatus {
        guard let target = targets[targetID] else {
            throw PodedgeError.distributionFailed(target: targetID, reason: "No target registered with ID '\(targetID)'")
        }
        return try await target.refreshStatus(externalShowID: externalShowID)
    }

    /// Submits a feed to all registered targets concurrently.
    ///
    /// - Parameters:
    ///   - feedURL: The public URL of the show's RSS feed.
    ///   - show: A sendable snapshot of the show.
    /// - Returns: A dictionary mapping target IDs to their submission results or errors.
    public func submitToAll(
        feedURL: URL,
        show: ShowSnapshot
    ) async -> [String: Result<DistributionSubmission, Error>] {
        let snapshot = targets
        return await withTaskGroup(
            of: (String, Result<DistributionSubmission, Error>).self
        ) { group in
            for (id, target) in snapshot {
                group.addTask {
                    do {
                        let submission = try await target.submit(feedURL: feedURL, show: show)
                        return (id, .success(submission))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            var results: [String: Result<DistributionSubmission, Error>] = [:]
            for await (id, result) in group {
                results[id] = result
            }
            return results
        }
    }
}
