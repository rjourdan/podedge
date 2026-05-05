# Spec 04 — Local LLM Providers (MLX + Ollama)

The local LLM provides on-device text generation for metadata, chapters, social blurbs, and the in-app Assistant. Two providers ship in v1: `MLXLLMProvider` (in-process inference via `mlx-swift-examples`) and `OllamaLLMProvider` (HTTP to a local Ollama service). No cloud providers in v1. `MLXLLMProvider` is currently an explicit stub that throws on every call; this spec replaces it with a real implementation and adds `OllamaLLMProvider`.

## User Stories

- As a user, I want on-device LLM generation so that my transcript and show notes never leave my Mac. *(podedge-spec-user-stories.md — Privacy)*
- As a user, I want to choose between Podedge's built-in MLX engine and my existing Ollama installation so that I can use a model I already have, or take the simplest default.
- As a user, I want Podedge to download required local AI models during onboarding with clear progress. *(podedge-spec-user-stories.md — Onboarding)*
- As a user, I want LLM metadata generation to complete in under 30 seconds for a 45-minute episode transcript. *(podedge-spec-user-stories.md — Performance)*

## Functional Requirements

### MLX Dependency

WHEN `Package.swift` is updated, THE SYSTEM SHALL add:
```
.package(url: "https://github.com/ml-explore/mlx-swift-examples", branch: "main")
```
and add `"LLM"` (from `mlx-swift-examples`) to the `PodedgeCore` target's dependencies.

### MLXLLMProvider Implementation

WHEN `MLXLLMProvider` is initialized with a `modelID`, THE SYSTEM SHALL load the MLX model from `~/Library/Application Support/Podedge/Models/LLM/<modelID>/`.

WHEN `complete(prompt:systemPrompt:maxTokens:)` is called, THE SYSTEM SHALL run synchronous MLX inference and return an `LLMResponse` with the generated text and token counts.

WHEN `stream(prompt:systemPrompt:maxTokens:)` is called, THE SYSTEM SHALL return an `AsyncThrowingStream` that yields `LLMStreamChunk` values as tokens are generated.

WHEN `complete(prompt:systemPrompt:maxTokens:schema:)` is called, THE SYSTEM SHALL attempt grammar-constrained decoding if the current mlx-swift-examples version supports it; otherwise fall back to prompt-level JSON instruction with up to 3 parse-retry attempts.

IF the model is not loaded when a completion is requested, THE SYSTEM SHALL throw `PodedgeError.llmFailed(reason: "Model not loaded: <modelID>")`.

IF the MLX inference throws, THE SYSTEM SHALL wrap the error in `PodedgeError.llmFailed(reason:)` and rethrow.

### OllamaLLMProvider

WHEN the user selects Ollama as the provider, THE SYSTEM SHALL connect to `http://localhost:11434` by default; a custom base URL can be provided.

WHEN Ollama is selected, THE SYSTEM SHALL fetch installed models from `/api/tags` and present them for selection.

WHEN Ollama is unreachable, THE SYSTEM SHALL throw `PodedgeError.ollamaUnreachable(reason:)` and surface the message "Ollama is not running. Start it with `ollama serve` and try again." The Assistant is blocked until Ollama is reachable or the user switches providers.

WHEN a tool call is sent to Ollama, THE SYSTEM SHALL use Ollama's native `tools` field in `/api/chat` where the model supports it, falling back to prompt-emulated tool use otherwise.

WHEN `OllamaLLMProvider.complete(tools:)` is called and the model does not support native tool-use, THE SYSTEM SHALL use prompt-emulated tool use: append a JSON tool-call schema to the system prompt and parse the response for `{"tool": "<name>", "arguments": {...}}` patterns, retrying once on parse failure.

### Model Download (MLX)

WHEN `ModelManager` is extended to support LLM models, THE SYSTEM SHALL add an `LLMModelInfo` catalog with the following three bundled MLX models:

| Display name | Model ID | Approx. size |
|---|---|---|
| Gemma 4 E4B Instruct (4-bit) | `mlx-community/gemma-4-e4b-it-4bit-MAD` | ~2.5 GB |
| Qwen 3 8B (4-bit DWQ) | `mlx-community/Qwen3-8B-4bit-DWQ-053125` | ~4.5 GB |
| Mistral Small 24B Instruct 2501 (4-bit) | `mlx-community/Mistral-Small-24B-Instruct-2501-4bit` | ~14 GB |

WHEN `downloadLLMModel(named:onProgress:)` is called on `ModelManager`, THE SYSTEM SHALL download the model from Hugging Face via the mlx-swift-examples download API and report progress.

### Onboarding Model Picker

WHEN the user reaches the onboarding AI step, THE SYSTEM SHALL present four options, each with a one-line guidance string:

1. **Gemma 4 E4B Instruct (4-bit)** — `mlx-community/gemma-4-e4b-it-4bit-MAD`, ~2.5 GB — "Fast and compact. Good for quick drafts. Works on any Apple Silicon Mac."
2. **Qwen 3 8B (4-bit DWQ)** — `mlx-community/Qwen3-8B-4bit-DWQ-053125`, ~4.5 GB — "Balanced speed and reliability. Strong tool-use. Recommended for 16 GB+ Macs."
3. **Mistral Small 24B Instruct 2501 (4-bit)** — `mlx-community/Mistral-Small-24B-Instruct-2501-4bit`, ~14 GB — "Most capable option. Best tool-use and Publish Assistant reliability. Requires 24 GB+ Mac."
4. **Ollama (advanced)** — "Use a model you already have in Ollama (for example, DeepSeek V4, Qwen 3.5, Gemma 4 31B — these large models work best via Ollama). Runs as a separate local service. Requires `ollama serve` on `localhost:11434`."

WHEN the user selects an MLX model, THE SYSTEM SHALL begin downloading it with visible progress.

WHEN the user selects Ollama, THE SYSTEM SHALL attempt to connect, list installed models from `/api/tags`, and let them pick one. IF Ollama is not running, THE SYSTEM SHALL show a friendly hint ("Start Ollama with `ollama serve` and click Retry").

IF the user skips the AI step, THEN THE SYSTEM SHALL allow onboarding to complete but warn that metadata generation and the Assistant are unavailable until an AI is configured in Settings → LLM Providers.

### Active Provider Selection

WHEN `AppServices` bootstraps, THE SYSTEM SHALL read `UserDefaults` keys `llm.provider.activeID` (`"mlx"` or `"ollama"`) and `llm.provider.modelID` to construct the appropriate provider.

IF no selection exists (fresh install, pre-onboarding), THE SYSTEM SHALL construct a disabled sentinel `LLMProvider` that throws `PodedgeError.llmFailed(reason: "No AI provider configured. Complete onboarding or visit Settings → LLM Providers.")`.

WHEN the user changes the active provider in Settings → LLM Providers, THE SYSTEM SHALL update `UserDefaults` and replace the active provider immediately (no restart required).

Invariant: exactly one active `LLMProvider` is selected at any time.

### LLMProvider Protocol Extension

WHEN the `LLMProvider` protocol is extended for Assistant tool-use (Spec 09), both `MLXLLMProvider` and `OllamaLLMProvider` SHALL implement the extended protocol. MLX uses prompt-emulated tool-use; Ollama uses native `tools` where available, prompt-emulated otherwise.

## Invariants

1. `MLXLLMProvider.complete` never returns an `LLMResponse` with empty `text` on success.
2. `MLXLLMProvider.complete(schema:)` returns text that is valid JSON when the schema is a valid JSON Schema string and the model is loaded.
3. Token counts (`inputTokens`, `outputTokens`) are non-negative integers.
4. The model directory path never contains `..` or other path traversal sequences.
5. `OllamaLLMProvider` never stores credentials (Ollama is unauthenticated by default).

## Property-Based Testing Targets

```swift
// Invariant 3: token counts are non-negative
@Test(arguments: [10, 50, 200, 500])
func tokenCountsAreNonNegative(maxTokens: Int) async throws {
    let provider = try MLXLLMProvider(modelID: TestModels.tinyMLX)
    let response = try await provider.complete(
        prompt: "Hello", systemPrompt: nil, maxTokens: maxTokens
    )
    #expect(response.inputTokens >= 0)
    #expect(response.outputTokens >= 0)
    #expect(response.outputTokens <= maxTokens)
}

// Invariant 2: schema-constrained output is valid JSON
@Test(arguments: [
    #"{"type":"object","properties":{"title":{"type":"string"}},"required":["title"]}"#
])
func schemaConstrainedOutputIsValidJSON(schema: String) async throws {
    let provider = try MLXLLMProvider(modelID: TestModels.tinyMLX)
    let response = try await provider.complete(
        prompt: "Generate a title", systemPrompt: nil, maxTokens: 100, schema: schema
    )
    let data = try #require(response.text.data(using: .utf8))
    _ = try JSONSerialization.jsonObject(with: data)  // throws if invalid
}

// Ollama: /api/tags parsing with 0, 1, N models
@Test(arguments: [0, 1, 5])
func ollamaTagsParsingWithNModels(count: Int) async throws {
    let models = (0..<count).map { OllamaModelInfo(name: "model-\($0)", sizeBytes: 1_000_000, modifiedAt: .now) }
    let result = try OllamaLLMProvider.parseTagsResponse(stubbedModels: models)
    #expect(result.count == count)
}

// Ollama: connection failure produces ollamaUnreachable
@Test
func ollamaUnreachableThrowsCorrectError() async throws {
    let provider = OllamaLLMProvider(baseURL: URL(string: "http://localhost:19999")!, modelID: "any")
    await #expect(throws: PodedgeError.self) {
        try await provider.complete(prompt: "hi", systemPrompt: nil, maxTokens: 10)
    }
}
```

## Non-Functional Requirements

- **Performance:** LLM metadata generation for a 45-minute transcript must complete in ≤ 30 s on M2 with the Qwen 3 8B model.
- **Memory:** MLX model must be loaded once and reused across calls; do not reload per completion.
- **Privacy:** No text is sent to any external endpoint. All inference runs on-device (MLX via Metal; Ollama via localhost).
- **Reliability:** If the MLX model file is corrupted, `MLXLLMProvider.init` throws rather than silently producing garbage output.

## Out of Scope for v1

- Cloud providers (Anthropic, OpenAI, OpenAI-compatible) — v1.1.
- Per-task provider routing — v1.1.
- LLM cost accounting — v1.1.
- Large-model (100 GB+) MLX in-process support — v1.1 (see ADR 0002).
- Fine-tuning or LoRA adapters.
