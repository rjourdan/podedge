import Foundation

/// A placeholder ``LLMProvider`` for on-device inference via MLX-Swift.
///
/// **This is a stub.** Every method throws ``PodedgeError/llmFailed(reason:)``
/// because the `mlx-swift` package is not yet added as a dependency.
///
/// ## Wiring instructions
///
/// 1. Add `mlx-swift` to `Package.swift`:
///    ```swift
///    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.18.0")
///    ```
/// 2. Add the product dependency to the `PodedgeCore` target.
/// 3. Replace the stub implementations below with real MLX inference calls.
///
/// - TODO: Wire mlx-swift dependency and implement real inference (WS5 follow-up).
public struct MLXLLMProvider: LLMProvider, Sendable {

    /// The model identifier (e.g. `"mlx-community/Llama-3.2-3B-Instruct-4bit"`).
    public let modelID: String

    /// Creates a stub MLX provider for the given model.
    ///
    /// - Parameter modelID: The Hugging Face model identifier.
    public init(modelID: String = "mlx-community/Llama-3.2-3B-Instruct-4bit") {
        self.modelID = modelID
    }

    private var stubError: PodedgeError {
        .llmFailed(reason: "MLX provider not yet linked — add mlx-swift dependency to Package.swift")
    }

    public func complete(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> LLMResponse {
        throw stubError
    }

    public func stream(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: stubError)
        }
    }

    public func complete(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        schema: String
    ) async throws -> LLMResponse {
        throw stubError
    }
}
