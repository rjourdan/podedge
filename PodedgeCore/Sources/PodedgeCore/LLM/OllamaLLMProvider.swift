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
                    let (bytes, response) = try await session.bytes(for: request)
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
}

// MARK: - Response Types

private struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
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
