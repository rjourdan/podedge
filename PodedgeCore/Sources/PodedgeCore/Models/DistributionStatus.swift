/// Status of a show's submission to a distribution directory.
public enum DistributionStatus: String, Codable, Sendable {
    /// The show has not been submitted to this directory.
    case notSubmitted
    /// Submission is awaiting review by the directory.
    case pending
    /// The show is listed and live in the directory.
    case live
    /// The directory rejected the submission.
    case rejected
    /// The submission or status check failed due to an error.
    case failed
}
