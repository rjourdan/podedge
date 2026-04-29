import Foundation

/// Domain errors surfaced throughout PodedgeCore.
public enum PodedgeError: LocalizedError, Sendable {
    case invalidMP3(reason: String)
    case uploadFailed(reason: String)
    case feedValidation(reason: String)
    case keychainFailure(reason: String)
    case jobFailed(jobID: UUID, reason: String)
    case hostUnreachable(reason: String)
    case notFound(entity: String, id: String)
    case preconditionViolated(reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidMP3(let reason): "Invalid MP3: \(reason)"
        case .uploadFailed(let reason): "Upload failed: \(reason)"
        case .feedValidation(let reason): "Feed validation: \(reason)"
        case .keychainFailure(let reason): "Keychain error: \(reason)"
        case .jobFailed(let id, let reason): "Job \(id) failed: \(reason)"
        case .hostUnreachable(let reason): "Host unreachable: \(reason)"
        case .notFound(let entity, let id): "\(entity) not found: \(id)"
        case .preconditionViolated(let reason): "Precondition violated: \(reason)"
        }
    }
}
