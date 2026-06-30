# Spec 09 — Assistant Core: Decisions & Lessons Learned

Date: 2026-06-02

## Architecture Decisions

1. **AssistantController uses the tool-aware stream interface** (`stream(_:systemPrompt:maxTokens:tools:)` → `AsyncThrowingStream<LLMStreamEvent, Error>`) for generating responses, allowing inline tool execution during streaming.

2. **`AssistantCaller` struct** — A dedicated `ToolCaller` conformance for the assistant with `CapabilityTier.full`. Specialist agents (Spec 10) will introduce per-agent callers with restricted tiers.

3. **⌘K behavior** — When the pane is already visible, ⌘K resets the conversation (fresh session per spec). When hidden, it reveals without resetting, preserving any existing conversation state.

4. **Rate limit tracking** — `toolCallTimestamps` tracks all tool calls (from `generateResponse` and `invokeDestructiveTool`). Per-minute limit applies to all calls. Per-hour limit applies only to destructive calls via `sessionDestructiveCount`.

5. **Provider label is set at construction time** — Changing the LLM provider in Settings does not propagate to an already-constructed `AssistantController`. Users must restart the app. This is a known limitation for v1; v1.1 will make the controller re-constructable on provider switch.

6. **LLMProvider protocol extension provides defaults** — `capabilities`, `complete(_:...:tools:)`, and `stream(_:...:tools:)` all have default implementations. This means existing conformances (private test mocks, `DisabledLLMProvider`) compile without modification.

7. **Tool schema helpers are module-internal** — `buildToolSchemaPrompt` and `parseToolCallFromText` are `internal` free functions, not public API. They're implementation details shared between MLX and Ollama providers within PodedgeCore.

## Lessons Learned

1. **Default protocol implementations prevent cascade breakage** — Adding new requirements to `LLMProvider` would have broken 3 existing test mocks and `DisabledLLMProvider`. Protocol extensions with defaults allowed non-breaking evolution.

2. **Test assertions must validate the intended behavior, not a trivially-true condition** — The destructive cap test originally checked `successCount <= 10`, which was always true (0 successes) because the tool didn't exist. Fixed to verify that the rate limiter actively blocks calls after the 10th attempt.

3. **Notification-based focus management** — Using `Notification.Name.focusAssistantInput` bridges the imperative ⌘K action to SwiftUI's `@FocusState`. This is a pragmatic pattern for cross-view focus control in NavigationSplitView.

4. **Ollama's native tool-use is model-dependent** — `supportsNativeToolUse: true` on the provider is aspirational; the actual capability depends on the model. The provider tries native first, falls back to prompt-emulation. This is runtime-safe but the capability flag is misleading.

## Files Created

- `PodedgeCore/Sources/PodedgeCore/Services/AssistantController.swift`
- `PodedgeCore/Sources/PodedgeCore/Services/AssistantMessage.swift`
- `PodedgeCore/Sources/PodedgeCore/Services/Router.swift`
- `PodedgeCore/Sources/PodedgeCore/Services/EscapeHatchResponder.swift`
- `Podedge/Podedge/Views/Assistant/AssistantPaneView.swift`
- `PodedgeCore/Tests/PodedgeCoreTests/RouterTests.swift`
- `PodedgeCore/Tests/PodedgeCoreTests/AssistantControllerTests.swift`
- `PodedgeCore/Tests/PodedgeCoreTests/MockLLMProvider.swift`

## Files Modified

- `PodedgeCore/Sources/PodedgeCore/Services/LLMProvider.swift` — Extended protocol
- `PodedgeCore/Sources/PodedgeCore/LLM/MLXLLMProvider.swift` — Tool-use methods
- `PodedgeCore/Sources/PodedgeCore/LLM/OllamaLLMProvider.swift` — Native + prompt-emulated tool-use
- `Podedge/Podedge/Views/MainWindowView.swift` — AssistantPaneView integration
- `Podedge/Podedge/Views/Settings/SettingsView.swift` — Assistant rate limit settings
- `Podedge/Podedge/AppServices.swift` — Router + AssistantController wiring
