import Foundation
import MLXLMCommon
import MLXLLM

/// On-device LLM inference via MLX.
public actor MLXLLMProvider: LLMProvider {
    public let modelID: String
    public var modelsDirectory: URL?
    private var container: ModelContainer?

    public init(modelID: String, modelsDirectory: URL? = nil) {
        self.modelID = modelID
        self.modelsDirectory = modelsDirectory
    }

    // MARK: - LLMProvider

    public nonisolated var capabilities: LLMProviderCapabilities {
        LLMProviderCapabilities(
            supportsNativeToolUse: false,
            supportsStreaming: true,
            maxContextTokens: 8192,
            modelID: modelID,
            providerID: "mlx"
        )
    }

    /// Loads the model from a local directory.
    public func loadModel(from directory: URL) async throws {
        let config = ModelConfiguration(directory: directory)
        container = try await loadModelContainer(configuration: config)
    }

    public func complete(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> LLMResponse {
        let container = try await requireLoadedOrLazyLoad()
        let userInput = makeUserInput(prompt: prompt, systemPrompt: systemPrompt)
        let input = try await container.prepare(input: userInput)
        let params = GenerateParameters(maxTokens: maxTokens)
        let stream = try await container.generate(input: input, parameters: params)
        var output = ""
        var info: GenerateCompletionInfo?
        for await generation in stream {
            switch generation {
            case .chunk(let text):
                output += text
            case .info(let completionInfo):
                info = completionInfo
            case .toolCall:
                break
            }
        }
        let outputTokens = info?.generationTokenCount ?? 0
        let inputTokens = info?.promptTokenCount ?? 0
        return LLMResponse(
            text: output,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            finishReason: outputTokens >= maxTokens ? .length : .stop
        )
    }

    nonisolated public func stream(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let container = try await self.requireLoadedOrLazyLoad()
                    let userInput = self.makeUserInput(prompt: prompt, systemPrompt: systemPrompt)
                    let input = try await container.prepare(input: userInput)
                    let params = GenerateParameters(maxTokens: maxTokens)
                    let generationStream = try await container.generate(input: input, parameters: params)
                    var totalText = ""
                    for await generation in generationStream {
                        if Task.isCancelled { break }
                        switch generation {
                        case .chunk(let text):
                            totalText += text
                            let isComplete = false
                            continuation.yield(LLMStreamChunk(text: totalText, isComplete: isComplete))
                        case .info:
                            continuation.yield(LLMStreamChunk(text: totalText, isComplete: true))
                        case .toolCall:
                            break
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

    // MARK: - Tool-Aware Completion

    public func complete(
        _ prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [any ToolDefinition]?
    ) async throws -> LLMResponse {
        guard let tools, !tools.isEmpty else {
            return try await complete(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
        }
        let toolSchema = buildToolSchemaPrompt(tools: tools)
        let effectiveSystem = [systemPrompt, toolSchema].compactMap { $0 }.joined(separator: "\n\n")
        let response = try await complete(prompt: prompt, systemPrompt: effectiveSystem, maxTokens: maxTokens)
        if let toolCall = parseToolCallFromText(response.text) {
            return LLMResponse(
                text: response.text,
                inputTokens: response.inputTokens,
                outputTokens: response.outputTokens,
                finishReason: .toolUse,
                toolCalls: [toolCall]
            )
        }
        // Retry once with error context
        let retryPrompt = prompt + "\n\nYour previous response was not a valid tool call JSON. Please respond with ONLY a JSON object in the format: {\"tool\": \"tool_name\", \"arguments\": {...}}"
        let retryResponse = try await complete(prompt: retryPrompt, systemPrompt: effectiveSystem, maxTokens: maxTokens)
        if let toolCall = parseToolCallFromText(retryResponse.text) {
            return LLMResponse(
                text: retryResponse.text,
                inputTokens: retryResponse.inputTokens,
                outputTokens: retryResponse.outputTokens,
                finishReason: .toolUse,
                toolCalls: [toolCall]
            )
        }
        return retryResponse
    }

    nonisolated public func stream(
        _ prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [any ToolDefinition]?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let effectiveSystem: String?
                    if let tools, !tools.isEmpty {
                        let toolSchema = buildToolSchemaPrompt(tools: tools)
                        effectiveSystem = [systemPrompt, toolSchema].compactMap { $0 }.joined(separator: "\n\n")
                    } else {
                        effectiveSystem = systemPrompt
                    }
                    let container = try await self.requireLoadedOrLazyLoad()
                    let userInput = self.makeUserInput(prompt: prompt, systemPrompt: effectiveSystem)
                    let input = try await container.prepare(input: userInput)
                    let params = GenerateParameters(maxTokens: maxTokens)
                    let generationStream = try await container.generate(input: input, parameters: params)
                    var accumulated = ""
                    for await generation in generationStream {
                        if Task.isCancelled { break }
                        switch generation {
                        case .chunk(let text):
                            accumulated += text
                            continuation.yield(.textDelta(text))
                        case .info:
                            break
                        case .toolCall:
                            break
                        }
                    }
                    if let toolCall = parseToolCallFromText(accumulated) {
                        continuation.yield(.toolCall(id: toolCall.id, name: toolCall.name, arguments: toolCall.arguments))
                        continuation.yield(.done(finishReason: .toolUse))
                    } else {
                        continuation.yield(.done(finishReason: .stop))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: PodedgeError.llmFailed(reason: error.localizedDescription))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // MARK: - Private

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

    private nonisolated func makeUserInput(prompt: String, systemPrompt: String?) -> UserInput {
        let messages: [Message]
        if let systemPrompt {
            messages = [["role": "system", "content": systemPrompt], ["role": "user", "content": prompt]]
        } else {
            messages = [["role": "user", "content": prompt]]
        }
        return UserInput(messages: messages)
    }
}
