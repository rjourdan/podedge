# Spec 04 — Local LLM Providers: Decisions & Lessons Learned

Date: 2026-05-12

## Key Decisions

1. **MLXLLMProvider is an actor, OllamaLLMProvider is a struct.** MLX holds mutable model state (the loaded `ModelContainer`) requiring isolation. Ollama is stateless HTTP — `Sendable` struct with `URLSession` is sufficient.

2. **Lazy loading via `modelsDirectory` parameter.** Rather than requiring an explicit `loadModel(from:)` call at bootstrap, the provider accepts a `modelsDirectory` URL at init and lazy-loads on first `complete()` call. This avoids blocking app startup with a 5–60s model load.

3. **AppServices.llmProvider is `private(set) var`.** The spec requires no-restart provider swap. `updateLLMProvider()` re-reads UserDefaults and replaces the provider. Views call this after changing settings.

4. **Schema-constrained output uses prompt+retry (not grammar API).** mlx-swift-examples does not expose a public grammar/constrained-decoding API as of 2025. We prepend the schema to the system prompt and retry up to 3 times on JSON parse failure.

5. **Ollama uses `/api/chat` with NDJSON streaming.** Non-streaming uses `stream: false` for simpler response parsing. JSON-constrained output uses `format: "json"` in the request body.

6. **ModelManager.downloadLLMModel is a stub (TODO).** The actual HuggingFace download integration requires wiring mlx-swift-examples' download API, which needs build verification. The directory structure is created correctly; the download body is a placeholder.

7. **UserDefaults keys:** `llm.provider.activeID` ("mlx" | "ollama") and `llm.provider.modelID` (the HF model ID or Ollama model name).

## Architecture Patterns

- **Cancellation in AsyncThrowingStream:** Always store the Task reference and set `continuation.onTermination = { @Sendable _ in task.cancel() }`. Check `Task.isCancelled` inside generation loops.
- **URL construction:** Use `appendingPathComponent("api/chat")` without leading slash to avoid double-slash URLs.
- **Provider resolution:** Static factory method `resolveProvider()` keeps init clean and is reusable from `updateLLMProvider()`.

## Issues Found in Review (deferred to future)

- Schema retry sends identical requests — could add error context on retry (Medium)
- No download size confirmation UX before multi-GB downloads (Medium)
- `isLLMModelDownloaded` returns true for empty directories created by stub download (Medium)
- Missing URLProtocol-stubbed test for Ollama streaming path (Medium)
- Missing parameterized property tests for token counts (Low)

## What Worked Well

- Splitting PodedgeCore (models + providers) from App-layer (views + wiring) into separate agent tasks gave clean boundaries.
- Code review caught 5 real bugs (cancellation, lazy-load, URL paths, live swap, stub download) before they reached integration.
- Swift Testing framework's `#expect(throws:)` pattern is clean for testing error paths on actors.

## What to Watch For

- The mlx-swift-examples API (`ModelContainer`, `GenerateParameters`, `MLXLMCommon.generate`) is approximated from docs. First real build will likely need import/type adjustments.
- Memory pressure: loading both MLX transcription (mlx-audio-swift) and MLX LLM simultaneously on 8 GB Macs needs testing.
