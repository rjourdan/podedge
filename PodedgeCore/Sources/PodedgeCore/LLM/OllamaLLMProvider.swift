import Foundation

/// LLM provider that calls a local Ollama service over HTTP.
public struct OllamaLLMProvider: LLMProvider, Sendable {
    public let baseURL: URL
    public let modelID: String
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        modelID: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.modelID = modelID
        self.session = session
    }

    // MARK: - LLMProvider

    public var capabilities: LLMProviderCapabilities {
        LLMProviderCapabilities(
            supportsNativeToolUse: true,
            supportsStreaming: true,
            maxContextTokens: 8192,
            modelID: modelID,
            providerID: "ollama"
        )
    }

    public func complete(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> LLMResponse {
        let body = chatRequestBody(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens, stream: false)
        let data = try await post(path: "/api/chat", body: body)
        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return LLMResponse(
            text: decoded.message.content,
            inputTokens: decoded.promptEvalCount ?? 0,
            outputTokens: decoded.evalCount ?? 0,
            finishReason: .stop
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
                    let body = chatRequestBody(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens, stream: true)
                    let url = baseURL.appendingPathComponent("api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = body
                    let (bytes, response) = try await self.session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw PodedgeError.ollamaUnreachable(reason: "Unexpected status code")
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let lineData = line.data(using: .utf8) else { continue }
                        let chunk = try JSONDecoder().decode(OllamaChatResponse.self, from: lineData)
                        let isComplete = chunk.done ?? false
                        continuation.yield(LLMStreamChunk(text: chunk.message.content, isComplete: isComplete))
                        if isComplete { break }
                    }
                    continuation.finish()
                } catch let error as PodedgeError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: PodedgeError.ollamaUnreachable(reason: error.localizedDescription))
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
        let body = chatRequestBody(prompt: prompt, systemPrompt: effectiveSystem, maxTokens: maxTokens, stream: false, format: "json")
        for attempt in 1...3 {
            let data = try await post(path: "/api/chat", body: body)
            let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
            if let jsonData = decoded.message.content.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: jsonData)) != nil {
                return LLMResponse(
                    text: decoded.message.content,
                    inputTokens: decoded.promptEvalCount ?? 0,
                    outputTokens: decoded.evalCount ?? 0,
                    finishReason: .stop
                )
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
        // Try native Ollama tool-use first
        let body = chatRequestBodyWithTools(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens, tools: tools, stream: false)
        let data = try await post(path: "/api/chat", body: body)
        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        // Check for native tool_calls in response
        if let nativeToolCalls = decoded.message.toolCalls, !nativeToolCalls.isEmpty {
            let calls = nativeToolCalls.compactMap { tc -> LLMToolCall? in
                guard let argsData = tc.argumentsData else { return nil }
                return LLMToolCall(id: UUID().uuidString, name: tc.function.name, arguments: argsData)
            }
            if !calls.isEmpty {
                return LLMResponse(
                    text: decoded.message.content,
                    inputTokens: decoded.promptEvalCount ?? 0,
                    outputTokens: decoded.evalCount ?? 0,
                    finishReason: .toolUse,
                    toolCalls: calls
                )
            }
        }
        // Check if model returned a text-based tool call (native not supported)
        if let toolCall = parseToolCallFromText(decoded.message.content) {
            return LLMResponse(
                text: decoded.message.content,
                inputTokens: decoded.promptEvalCount ?? 0,
                outputTokens: decoded.evalCount ?? 0,
                finishReason: .toolUse,
                toolCalls: [toolCall]
            )
        }
        // Fall back to prompt-emulated approach
        let toolSchema = buildToolSchemaPrompt(tools: tools)
        let effectiveSystem = [systemPrompt, toolSchema].compactMap { $0 }.joined(separator: "\n\n")
        let fallbackBody = chatRequestBody(prompt: prompt, systemPrompt: effectiveSystem, maxTokens: maxTokens, stream: false)
        let fallbackData = try await post(path: "/api/chat", body: fallbackBody)
        let fallbackDecoded = try JSONDecoder().decode(OllamaChatResponse.self, from: fallbackData)
        if let toolCall = parseToolCallFromText(fallbackDecoded.message.content) {
            return LLMResponse(
                text: fallbackDecoded.message.content,
                inputTokens: fallbackDecoded.promptEvalCount ?? 0,
                outputTokens: fallbackDecoded.evalCount ?? 0,
                finishReason: .toolUse,
                toolCalls: [toolCall]
            )
        }
        return LLMResponse(
            text: fallbackDecoded.message.content,
            inputTokens: fallbackDecoded.promptEvalCount ?? 0,
            outputTokens: fallbackDecoded.evalCount ?? 0,
            finishReason: .stop
        )
    }

    public func stream(
        _ prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [any ToolDefinition]?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body: Data
                    if let tools, !tools.isEmpty {
                        let toolSchema = buildToolSchemaPrompt(tools: tools)
                        let effectiveSystem = [systemPrompt, toolSchema].compactMap { $0 }.joined(separator: "\n\n")
                        body = self.chatRequestBody(prompt: prompt, systemPrompt: effectiveSystem, maxTokens: maxTokens, stream: true)
                    } else {
                        body = self.chatRequestBody(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens, stream: true)
                    }
                    let url = self.baseURL.appendingPathComponent("api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = body
                    let (bytes, response) = try await self.session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw PodedgeError.ollamaUnreachable(reason: "Unexpected status code")
                    }
                    var accumulated = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let lineData = line.data(using: .utf8) else { continue }
                        let chunk = try JSONDecoder().decode(OllamaChatResponse.self, from: lineData)
                        let isComplete = chunk.done ?? false
                        if !chunk.message.content.isEmpty {
                            accumulated += chunk.message.content
                            continuation.yield(.textDelta(chunk.message.content))
                        }
                        // Check for native tool_calls in streaming chunk
                        if let nativeToolCalls = chunk.message.toolCalls, !nativeToolCalls.isEmpty {
                            for tc in nativeToolCalls {
                                if let argsData = tc.argumentsData {
                                    continuation.yield(.toolCall(id: UUID().uuidString, name: tc.function.name, arguments: argsData))
                                }
                            }
                        }
                        if isComplete { break }
                    }
                    // Check accumulated text for tool call pattern
                    if let toolCall = parseToolCallFromText(accumulated) {
                        continuation.yield(.toolCall(id: toolCall.id, name: toolCall.name, arguments: toolCall.arguments))
                        continuation.yield(.done(finishReason: .toolUse))
                    } else {
                        continuation.yield(.done(finishReason: .stop))
                    }
                    continuation.finish()
                } catch let error as PodedgeError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: PodedgeError.ollamaUnreachable(reason: error.localizedDescription))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // MARK: - Tags

    /// Parses an Ollama /api/tags response into model info.
    public static func parseTagsResponse(data: Data) throws -> [OllamaModelInfo] {
        let decoded = try JSONDecoder.ollamaDecoder.decode(OllamaTagsResponse.self, from: data)
        return decoded.models.map {
            OllamaModelInfo(name: $0.name, sizeBytes: $0.size, modifiedAt: $0.modifiedAt)
        }
    }

    // MARK: - Private

    private func post(path: String, body: Data) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PodedgeError.ollamaUnreachable(reason: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PodedgeError.ollamaUnreachable(reason: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return data
    }

    private func chatRequestBody(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        stream: Bool,
        format: String? = nil
    ) -> Data {
        var messages: [[String: String]] = []
        if let systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])
        var payload: [String: Any] = [
            "model": modelID,
            "messages": messages,
            "stream": stream,
            "options": ["num_predict": maxTokens]
        ]
        if let format { payload["format"] = format }
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private func chatRequestBodyWithTools(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [any ToolDefinition],
        stream: Bool
    ) -> Data {
        var messages: [[String: String]] = []
        if let systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])
        let ollamaTools: [[String: Any]] = tools.map { tool in
            let params: Any = (try? JSONSerialization.jsonObject(with: Data(tool.parameterSchema.utf8))) ?? [:]
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": params
                ] as [String: Any]
            ]
        }
        let payload: [String: Any] = [
            "model": modelID,
            "messages": messages,
            "stream": stream,
            "options": ["num_predict": maxTokens],
            "tools": ollamaTools
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}

// MARK: - Response Types

private struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
        let toolCalls: [OllamaToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }

    struct OllamaToolCall: Decodable {
        struct Function: Decodable {
            let name: String
            let arguments: AnyCodableArguments

            struct AnyCodableArguments: Decodable {
                let data: Data

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    // Decode raw JSON as dictionary then re-serialize to Data
                    if let dict = try? container.decode([String: CodableValue].self) {
                        let mapped = dict.mapValues { $0.value }
                        self.data = (try? JSONSerialization.data(withJSONObject: mapped)) ?? Data()
                    } else {
                        self.data = Data()
                    }
                }
            }
        }
        let function: Function

        var argumentsData: Data? { function.arguments.data }
    }

    let message: Message
    let done: Bool?
    let promptEvalCount: Int?
    let evalCount: Int?

    enum CodingKeys: String, CodingKey {
        case message, done
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}

/// Helper for decoding arbitrary JSON values in tool call arguments.
private enum CodableValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    var value: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .null: return NSNull()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if container.decodeNil() { self = .null }
        else { self = .null }
    }
}

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
        let size: Int64
        let modifiedAt: Date

        enum CodingKeys: String, CodingKey {
            case name, size
            case modifiedAt = "modified_at"
        }
    }
    let models: [Model]
}

extension JSONDecoder {
    static var ollamaDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
