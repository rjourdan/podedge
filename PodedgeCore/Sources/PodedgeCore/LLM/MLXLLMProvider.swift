import Foundation
import MLXLMCommon
import LLM

/// On-device LLM inference via MLX.
public actor MLXLLMProvider: LLMProvider {
    public let modelID: String
    public var modelsDirectory: URL?
    private var container: ModelContainer?

    public init(modelID: String, modelsDirectory: URL? = nil) {
        self.modelID = modelID
        self.modelsDirectory = modelsDirectory
    }

    /// Loads the model from a local directory.
    public func loadModel(from directory: URL) async throws {
        let config = ModelConfiguration(id: modelID, directory: directory)
        container = try await LLM.loadModelContainer(configuration: config)
    }

    public func complete(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> LLMResponse {
        let container = try await requireLoadedOrLazyLoad()
        let messages: [[String: String]]
        if let systemPrompt {
            messages = [["role": "system", "content": systemPrompt], ["role": "user", "content": prompt]]
        } else {
            messages = [["role": "user", "content": prompt]]
        }
        let input = try await container.perform { context, model in
            try await context.processor.prepare(input: .init(messages: messages))
        }
        let params = GenerateParameters(maxTokens: maxTokens)
        var output = ""
        var outputTokens = 0
        let result = try await container.perform { context, model in
            try MLXLMCommon.generate(input: input, parameters: params, context: context) { tokens in
                outputTokens = tokens.count
                if let text = context.tokenizer.decode(tokens: tokens) {
                    output = text
                }
                return tokens.count >= maxTokens ? .stop : .more
            }
        }
        return LLMResponse(
            text: output,
            inputTokens: result.promptTokenCount,
            outputTokens: outputTokens,
            finishReason: outputTokens >= maxTokens ? .length : .stop
        )
    }

    public func stream(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let container = try await self.requireLoadedOrLazyLoad()
                    let messages: [[String: String]]
                    if let systemPrompt {
                        messages = [["role": "system", "content": systemPrompt], ["role": "user", "content": prompt]]
                    } else {
                        messages = [["role": "user", "content": prompt]]
                    }
                    let input = try await container.perform { context, model in
                        try await context.processor.prepare(input: .init(messages: messages))
                    }
                    let params = GenerateParameters(maxTokens: maxTokens)
                    _ = try await container.perform { context, model in
                        try MLXLMCommon.generate(input: input, parameters: params, context: context) { tokens in
                            if Task.isCancelled { return .stop }
                            if let text = context.tokenizer.decode(tokens: tokens) {
                                let isComplete = tokens.count >= maxTokens
                                continuation.yield(LLMStreamChunk(text: text, isComplete: isComplete))
                                if isComplete { return .stop }
                            }
                            return .more
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: PodedgeError.llmFailed(reason: error.localizedDescription))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func complete(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        schema: String
    ) async throws -> LLMResponse {
        let schemaInstruction = "Respond with JSON matching this schema: \(schema)"
        let effectiveSystem = [systemPrompt, schemaInstruction].compactMap { $0 }.joined(separator: "\n\n")
        for attempt in 1...3 {
            let response = try await complete(prompt: prompt, systemPrompt: effectiveSystem, maxTokens: maxTokens)
            if let data = response.text.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return response
            }
            if attempt == 3 {
                throw PodedgeError.llmFailed(reason: "JSON parse failed after 3 retries")
            }
        }
        throw PodedgeError.llmFailed(reason: "JSON parse failed after 3 retries")
    }

    private func requireLoadedOrLazyLoad() async throws -> ModelContainer {
        if let container { return container }
        guard let dir = modelsDirectory else {
            throw PodedgeError.llmFailed(reason: "Model not loaded: \(modelID)")
        }
        try await loadModel(from: dir)
        guard let container else {
            throw PodedgeError.llmFailed(reason: "Model failed to load: \(modelID)")
        }
        return container
    }
}
