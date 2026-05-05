# Spec 04 — Local LLM Providers (MLX + Ollama): Design

## Architecture Overview

Two `LLMProvider` implementations ship in v1. `MLXLLMProvider` is an `actor` that runs inference in-process via `mlx-swift-examples`. `OllamaLLMProvider` is a `Sendable` struct that calls a local Ollama service over HTTP. Both implement the same `LLMProvider` protocol (extended in Spec 09 with tool-use). `AppServices` reads `UserDefaults` at bootstrap to construct whichever provider the user selected during onboarding.

`ModelManager` gains an `LLMModelInfo` catalog and download support for the three bundled MLX models. A new `AIProviderPickerView` is rendered in `OnboardingView` step 4. Settings → LLM Providers (owned by this spec) lets the user switch providers post-onboarding.

## Types

### Modified: `MLXLLMProvider`

```swift
// PodedgeCore/Sources/PodedgeCore/LLM/MLXLLMProvider.swift
import MLXLMCommon  // from mlx-swift-examples LLM product

public actor MLXLLMProvider: LLMProvider {
    public let modelID: String
    private var loadedModel: (any LanguageModel)?

    public init(modelID: String)

    /// Loads the model from disk. Called lazily on first completion request.
    public func loadModel(from directory: URL) async throws

    public func complete(
        prompt: String, systemPrompt: String?, maxTokens: Int
    ) async throws -> LLMResponse

    public func stream(
        prompt: String, systemPrompt: String?, maxTokens: Int
    ) -> AsyncThrowingStream<LLMStreamChunk, Error>

    public func complete(
        prompt: String, systemPrompt: String?, maxTokens: Int, schema: String
    ) async throws -> LLMResponse
}
```

The actor serializes model access. `loadModel` is called lazily inside `complete` if `loadedModel == nil`.

**Schema-constrained output:** Check at runtime whether `mlx-swift-examples` exposes a grammar/constrained-decoding API. If yes, use it. If not, prepend the schema to the system prompt as `"Respond with JSON matching this schema: <schema>"` and retry up to 3 times on `JSONSerialization` failure.

**Bundled model IDs** (user picks one during onboarding):
- `mlx-community/gemma-4-e4b-it-4bit-MAD` (~2.5 GB)
- `mlx-community/Qwen3-8B-4bit-DWQ-053125` (~4.5 GB)
- `mlx-community/Mistral-Small-24B-Instruct-2501-4bit` (~14 GB)

### New: `OllamaLLMProvider`

```swift
// PodedgeCore/Sources/PodedgeCore/LLM/OllamaLLMProvider.swift
public struct OllamaLLMProvider: LLMProvider, Sendable {
    public let baseURL: URL      // default: http://localhost:11434
    public let modelID: String

    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        modelID: String
    )

    public func complete(
        prompt: String, systemPrompt: String?, maxTokens: Int
    ) async throws -> LLMResponse

    public func stream(
        prompt: String, systemPrompt: String?, maxTokens: Int
    ) -> AsyncThrowingStream<LLMStreamChunk, Error>

    public func complete(
        prompt: String, systemPrompt: String?, maxTokens: Int, schema: String
    ) async throws -> LLMResponse
}
```

Uses `URLSession` against `/api/chat` (streaming NDJSON) and `/api/tags`. No Keychain dependency. Throws `PodedgeError.ollamaUnreachable(reason:)` on connection failure.

**Tool-use:** Uses Ollama's native `tools` field in `/api/chat` where the model supports it. Falls back to prompt-emulated tool use (same pattern as `MLXLLMProvider`) when the model does not support native tools.

### New: `OllamaModelInfo`

```swift
// PodedgeCore/Sources/PodedgeCore/Models/OllamaModelInfo.swift
public struct OllamaModelInfo: Sendable {
    public var name: String         // e.g. "llama3.1:8b"
    public var sizeBytes: Int64
    public var modifiedAt: Date
}
```

Matches the `/api/tags` response shape (`models[].name`, `models[].size`, `models[].modified_at`).

### New: `LLMModelInfo`

```swift
// PodedgeCore/Sources/PodedgeCore/Models/LLMModelInfo.swift
public struct LLMModelInfo: Sendable {
    public var modelID: String       // e.g. "mlx-community/Qwen3-8B-4bit-DWQ-053125"
    public var displayName: String
    public var guidanceString: String
    public var sizeBytes: Int64
    public var isDownloaded: Bool
}
```

### Modified: `ModelManager`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/ModelManager.swift
// Add:
public func availableLLMModels() async -> [LLMModelInfo]
public func downloadLLMModel(
    named modelID: String,
    onProgress: (@Sendable (Double) -> Void)?
) async throws
public func isLLMModelDownloaded(modelID: String) -> Bool
public func availableOllamaModels(
    baseURL: URL = URL(string: "http://localhost:11434")!
) async throws -> [OllamaModelInfo]
```

`availableOllamaModels` calls `/api/tags` and decodes the response. Throws `PodedgeError.ollamaUnreachable(reason:)` on connection failure.

LLM models are stored at `~/Library/Application Support/Podedge/Models/LLM/<modelID-sanitized>/`. The `modelID` is sanitized by replacing `/` with `_` for the filesystem path.

### Modified: `PodedgeError`

```swift
// PodedgeCore/Sources/PodedgeCore/Models/PodedgeError.swift
// Add:
case ollamaUnreachable(reason: String)
```

### Modified: `AppServices`

```swift
// Podedge/Podedge/AppServices.swift
// Reads UserDefaults at bootstrap:
//   llm.provider.activeID: "mlx" | "ollama"
//   llm.provider.modelID: the selected model ID
// Constructs MLXLLMProvider or OllamaLLMProvider accordingly.
// If no selection: constructs a DisabledLLMProvider sentinel.
public let llmProvider: any LLMProvider
```

`LLMService` is already constructed with an `LLMProvider`; `AppServices` passes `llmProvider`.

### New: `AIProviderPickerView`

```swift
// Podedge/Podedge/Views/Onboarding/AIProviderPickerView.swift
// Renders the four onboarding options (3 MLX + Ollama).
// On MLX selection: triggers download via ModelManager, shows progress.
// On Ollama selection: calls ModelManager.availableOllamaModels(), shows picker.
//   If Ollama unreachable: shows hint + Retry button.
// Writes selection to UserDefaults on completion.
```

### Modified: `OnboardingView`

Step 4 is rewritten to render `AIProviderPickerView`. The previous single-model download list is replaced.

### Modified: `SettingsView`

Adds a "LLM Providers" tab (owned by this spec, not Spec 09) showing:
- Active provider (MLX or Ollama) with current model ID.
- Model selector (for MLX: the three bundled options; for Ollama: fetched from `/api/tags`).
- Test Connection button.
- Change provider button.

## File Map

| Action | Path |
|--------|------|
| **Modify** | `PodedgeCore/Sources/PodedgeCore/LLM/MLXLLMProvider.swift` — replace stub with real implementation; support 3 bundled model IDs |
| **Create** | `PodedgeCore/Sources/PodedgeCore/LLM/OllamaLLMProvider.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Models/LLMModelInfo.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Models/OllamaModelInfo.swift` |
| **Modify** | `PodedgeCore/Sources/PodedgeCore/Services/ModelManager.swift` — add LLM model methods + `availableOllamaModels` |
| **Modify** | `PodedgeCore/Sources/PodedgeCore/Models/PodedgeError.swift` — add `.ollamaUnreachable` |
| **Modify** | `PodedgeCore/Package.swift` — add mlx-swift-examples dependency |
| **Modify** | `Podedge/Podedge/AppServices.swift` — construct active provider from UserDefaults |
| **Create** | `Podedge/Podedge/Views/Onboarding/AIProviderPickerView.swift` |
| **Modify** | `Podedge/Podedge/Views/Onboarding/OnboardingView.swift` — step 4 rewrite |
| **Modify** | `Podedge/Podedge/Views/Settings/SettingsView.swift` — add LLM Providers tab |

## Data Flow

**MLX path:**
1. `AppServices.bootstrap()` reads `UserDefaults` → constructs `MLXLLMProvider(modelID: savedID)`.
2. `llmProvider.loadModel(from: modelsDirectory)` called during bootstrap (if model is downloaded).
3. `LLMService.complete(promptName:variables:schema:)` → `llmProvider.complete(prompt:systemPrompt:maxTokens:schema:)`.
4. MLX inference runs on Metal GPU → returns generated text + token counts.
5. `LLMResponse` returned to `LLMService` → decoded by `MetadataGenerationService`.

**Ollama path:**
1. `AppServices.bootstrap()` reads `UserDefaults` → constructs `OllamaLLMProvider(baseURL:modelID:)`.
2. No model loading step (Ollama manages its own models).
3. `LLMService.complete(...)` → `OllamaLLMProvider.complete(...)` → POST `/api/chat` to `localhost:11434`.
4. NDJSON stream decoded → `LLMResponse` assembled.

**Schema fallback path (both providers):**
1. `complete(schema:)` called.
2. Native grammar/constrained API available? → use it.
3. Not available? → prepend schema instruction to system prompt.
4. Parse response as JSON. If parse fails, retry with error context (max 3 attempts).
5. All retries fail → throw `PodedgeError.llmFailed(reason: "JSON parse failed after 3 retries")`.

## Error Model

| Error | Trigger | Handling |
|-------|---------|----------|
| `PodedgeError.llmFailed(reason: "Model not loaded")` | `complete` called before MLX model downloaded | UI shows "Model not available — visit Settings → LLM Providers" |
| `PodedgeError.llmFailed(reason: "JSON parse failed")` | Schema-constrained output not valid JSON after retries | Propagated to `MetadataGenerationService` |
| `PodedgeError.ollamaUnreachable(reason:)` | Ollama not running or wrong port | UI shows "Ollama is not running. Start it with `ollama serve` and try again." |
| `PodedgeError.llmFailed(reason: "No AI provider configured")` | Pre-onboarding sentinel | UI prompts user to complete onboarding or visit Settings |
| Any MLX error | Inference failure | Wrapped in `PodedgeError.llmFailed(reason:)` |

## Concurrency Model

- `MLXLLMProvider` is an `actor` — MLX model state is not `Sendable`.
- `OllamaLLMProvider` is a `Sendable` struct — `URLSession` calls are `async`.
- `ModelManager` is already an `actor`; `downloadLLMModel` and `availableOllamaModels` run within it.
- `AppServices.bootstrap()` calls `await llmProvider.loadModel(...)` for MLX — safe because `bootstrap()` is `async`.

## Test Strategy

**Unit tests** (`MLXLLMProviderTests.swift`):
- Use a tiny test model to avoid large downloads in CI.
- `testCompleteReturnsNonEmptyText`, `testTokenCountsAreNonNegative`, `testSchemaConstrainedOutputIsValidJSON`, `testStreamYieldsChunks`, `testModelNotLoadedThrows`.

**Unit tests** (`OllamaLLMProviderTests.swift`):
- URLProtocol stubs for `/api/tags` and `/api/chat` (including streaming NDJSON and tool-use events).
- `testTagsParsingWithZeroModels`, `testTagsParsingWithNModels` — property tests.
- `testCompleteReturnsText` — 200 response → non-empty text.
- `testToolCallParsed` — response with tool-use block → `.toolCall` event.
- `testOllamaUnreachableThrows` — connection refused → `PodedgeError.ollamaUnreachable`.
- `testUnreachableMidStream` — stream interrupted → error propagated cleanly.

**Integration:** Covered by Spec 05 tests (metadata generation uses the real provider in integration tests).

## Open Questions / Risks

1. **`mlx-swift-examples` API surface:** Confirm the exact import name (`MLXLMCommon`? `MLXLLM`?) and the `generate` function signature against the `main` branch at implementation time.
2. **Grammar-constrained decoding:** As of early 2025, mlx-swift-examples does not expose a public grammar API. The prompt+retry fallback is the expected path for v1.
3. **Model loading time:** Loading a large MLX model takes 5–60 seconds. `bootstrap()` should load the model in the background; consider lazy loading on first use.
4. **Memory pressure:** On 8 GB Macs, loading both WhisperKit and a large MLX model simultaneously may cause pressure. Consider unloading WhisperKit after transcription before loading MLX.
5. **Ollama tool-use model detection:** Ollama's `/api/tags` does not indicate whether a model supports native tool-use. Detect at runtime by attempting a tool-use call and falling back to prompt emulation on error or malformed response.
