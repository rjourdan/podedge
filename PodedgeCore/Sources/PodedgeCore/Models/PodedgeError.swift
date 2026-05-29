import Foundation

/// Domain errors surfaced throughout PodedgeCore.
public enum PodedgeError: LocalizedError, Sendable {
    case invalidMP3(reason: String)
    case uploadFailed(reason: String)
    case feedValidation(reason: String)
    case keychainFailure(reason: String)
    case jobFailed(jobID: UUID, reason: String)
    case hostUnreachable(reason: String)
    case notFound(entity: String, id: String = "")
    case preconditionViolated(reason: String)
    case transcriptionFailed(reason: String)
    case llmFailed(reason: String)
    case distributionFailed(target: String, reason: String)
    case analyticsUnavailable(reason: String)
    case ollamaUnreachable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidMP3(let reason): return "Invalid MP3: \(reason)"
        case .uploadFailed(let reason): return "Upload failed: \(reason)"
        case .feedValidation(let reason): return "Feed validation: \(reason)"
        case .keychainFailure(let reason): return "Keychain error: \(reason)"
        case .jobFailed(let id, let reason): return "Job \(id) failed: \(reason)"
        case .hostUnreachable(let reason): return "Host unreachable: \(reason)"
        case .notFound(let entity, let id):
            if id.isEmpty {
                return "\(entity) not found"
            }
            return "\(entity) not found: \(id)"
        case .preconditionViolated(let reason): return "Precondition violated: \(reason)"
        case .transcriptionFailed(let reason): return "Transcription failed: \(reason)"
        case .llmFailed(let reason): return "LLM failed: \(reason)"
        case .distributionFailed(let target, let reason): return "Distribution to \(target) failed: \(reason)"
        case .analyticsUnavailable(let reason): return "Analytics unavailable: \(reason)"
        case .ollamaUnreachable(let reason): return "Ollama unreachable: \(reason)"
        }
    }
}
