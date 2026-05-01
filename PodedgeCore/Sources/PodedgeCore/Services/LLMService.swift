import Foundation
import os

/// Loads prompt templates from the bundle, renders variables, and calls
/// an ``LLMProvider`` for completions.
public struct LLMService: Sendable {

    // MARK: - Dependencies

    private let provider: any LLMProvider
    private let logger = PodedgeLogger.llm

    // MARK: - Init

    /// Creates an LLM service backed by the given provider.
    ///
    /// - Parameter provider: The LLM provider to delegate completions to.
    public init(provider: any LLMProvider) {
        self.provider = provider
    }

    // MARK: - Prompt Loading

    /// Loads a prompt template from the bundle's `Prompts` directory.
    ///
    /// - Parameter name: The filename without extension (e.g. `"episode-metadata"`).
    /// - Returns: The raw template string.
    /// - Throws: ``PodedgeError/llmFailed(reason:)`` if the resource is missing.
    public func loadPrompt(named name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "md") else {
            throw PodedgeError.llmFailed(reason: "Prompt template '\(name)' not found in bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Renders a prompt template by replacing `{{key}}` placeholders with values.
    ///
    /// Substitution is literal (not regex-based) and keys are case-sensitive.
    /// For example, `{{show_title}}` is replaced by the value for key `"show_title"`.
    ///
    /// - Parameters:
    ///   - template: The raw template string with `{{variable}}` placeholders.
    ///   - variables: A dictionary mapping variable names to their values.
    /// - Returns: The rendered prompt string.
    /// - Throws: ``PodedgeError/llmFailed(reason:)`` if any `{{...}}` placeholders
    ///   remain after substitution.
    public func render(template: String, variables: [String: String]) throws -> String {
        var result = template
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        // Scan for unrendered placeholders.
        var remaining: [String] = []
        var scanner = result[...]
        while let open = scanner.range(of: "{{") {
            guard let close = scanner[open.upperBound...].range(of: "}}") else { break }
            remaining.append(String(scanner[open.lowerBound..<close.upperBound]))
            scanner = scanner[close.upperBound...]
        }
        if !remaining.isEmpty {
            throw PodedgeError.llmFailed(
                reason: "Prompt has unrendered variables: \(remaining.joined(separator: ", "))"
            )
        }
        return result
    }

    // MARK: - Completion

    /// Loads a named prompt, renders variables, and generates a completion.
    ///
    /// - Parameters:
    ///   - promptName: The prompt template filename (without extension).
    ///   - variables: Template variable substitutions.
    ///   - systemPrompt: Optional system-level instruction.
    ///   - maxTokens: Maximum tokens to generate.
    ///   - schema: Optional JSON Schema string to constrain output format.
    /// - Returns: The LLM response.
    /// - Throws: ``PodedgeError/llmFailed(reason:)`` on failure.
    public func complete(
        promptName: String,
        variables: [String: String],
        systemPrompt: String? = nil,
        maxTokens: Int = 2048,
        schema: String? = nil
    ) async throws -> LLMResponse {
        let template = try loadPrompt(named: promptName)
        let prompt = try render(template: template, variables: variables)

        logger.info("Completing prompt '\(promptName, privacy: .public)' (\(prompt.count) chars)")

        do {
            if let schema {
                return try await provider.complete(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    maxTokens: maxTokens,
                    schema: schema
                )
            } else {
                return try await provider.complete(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    maxTokens: maxTokens
                )
            }
        } catch let error as PodedgeError {
            throw error
        } catch {
            throw PodedgeError.llmFailed(reason: error.localizedDescription)
        }
    }
}
