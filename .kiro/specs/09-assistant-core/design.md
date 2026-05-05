# Spec 09 — Assistant Core: Design

## Architecture Overview

The Assistant is built in three layers. The `LLMProvider` protocol is extended with tool-use support; both `MLXLLMProvider` and `OllamaLLMProvider` implement it — MLX via prompt emulation, Ollama via native `tools` where available and prompt emulation otherwise. Both are primary paths. `AssistantController` is an `@Observable` class that owns a single conversation's lifecycle. `Router` is a pure function (no state) that maps utterances to agent IDs. The `AssistantPaneView` is a SwiftUI view docked on the right side of `MainWindowView`.

The active provider is whichever the user selected during onboarding (MLX or Ollama). The LLM Providers tab in Settings (owned by Spec 04) handles provider switching; this spec adds Assistant-specific settings (rate limits) to that tab.

## Types

### Extended: `LLMProvider` Protocol

```swift
// PodedgeCore/Sources/PodedgeCore/Services/LLMProvider.swift
public struct LLMProviderCapabilities: Sendable {
    public var supportsNativeToolUse: Bool
    public var supportsStreaming: Bool
    public var maxContextTokens: Int
    public var modelID: String
    public var providerID: String  // "mlx", "ollama"
}

public enum LLMStreamEvent: Sendable {
    case textDelta(String)
    case toolCall(id: String, name: String, arguments: Data)
    case done(finishReason: LLMFinishReason)
}

// Add to LLMProvider protocol:
var capabilities: LLMProviderCapabilities { get }
func complete(_ prompt: String, systemPrompt: String?, maxTokens: Int,
              tools: [any ToolDefinition]?) async throws -> LLMResponse
func stream(_ prompt: String, systemPrompt: String?, maxTokens: Int,
            tools: [any ToolDefinition]?) -> AsyncThrowingStream<LLMStreamEvent, Error>
```

Existing `complete(prompt:systemPrompt:maxTokens:)` and `stream(prompt:systemPrompt:maxTokens:)` become default implementations that call the new signatures with `tools: nil`.

### New: `AssistantController`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/AssistantController.swift
@MainActor
@Observable
public final class AssistantController {
    public var messages: [AssistantMessage] = []
    public var isRunning: Bool = false
    public var currentProviderLabel: String = ""

    private let router: Router
    private let toolBroker: ToolBroker
    private let auditLog: AuditLogService
    private var sessionDestructiveCount: Int = 0
    private var sessionToolCallsThisMinute: Int = 0

    public init(router: Router, toolBroker: ToolBroker, auditLog: AuditLogService,
                llmProvider: any LLMProvider)

    public func submit(_ utterance: String) async
    public func reset()
    public static func wrapUntrusted(_ content: String, source: String) -> String
}
```

`submit` orchestrates: route → agent → tool loop → stream response. `reset()` clears `messages` and resets rate-limit counters.

### New: `AssistantMessage`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/AssistantMessage.swift
public struct AssistantMessage: Identifiable, Sendable {
    public var id: UUID
    public var role: MessageRole  // .user, .assistant
    public var text: String
    public var toolCalls: [ToolCallRecord]
    public var providerLabel: String?  // e.g. "Qwen3-8B · MLX" or "llama3.1:8b · Ollama"
    public var isStreaming: Bool
}

public struct ToolCallRecord: Identifiable, Sendable {
    public var id: String
    public var toolName: String
    public var arguments: Data
    public var result: ToolResult?
}
```

### New: `Router`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/Router.swift
public struct Router: Sendable {
    private let llmProvider: any LLMProvider

    public init(llmProvider: any LLMProvider)
    public func route(utterance: String) async -> RouterDecision
}

public enum RouterDecision: Sendable {
    case agent(id: String)
    case unknown
    case clarify(question: String)
}
```

Keyword rules checked first (O(1)). LLM classifier called only when no keyword matches.

### New: `EscapeHatchResponder`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/EscapeHatchResponder.swift
public struct EscapeHatchResponder: Sendable {
    public func response(for failure: AssistantFailure) -> String
}

public enum AssistantFailure: Sendable {
    case iterationCapExceeded(agentID: String)
    case capabilityTierInsufficient(required: CapabilityTier, current: CapabilityTier)
    case providerUnreachable(providerID: String)
    case toolCallFailed(toolName: String, reason: String)
}
```

### New: `AssistantPaneView`

```swift
// Podedge/Podedge/Views/Assistant/AssistantPaneView.swift
struct AssistantPaneView: View {
    @Environment(\.appServices) private var appServices
    @State private var controller: AssistantController
    // Conversation list, input field, tool-call rows, provider label
}
```

### New: `AssistantShortcut`

```swift
// Podedge/Podedge/Views/Assistant/AssistantShortcut.swift
// .keyboardShortcut("k", modifiers: .command) on the main window
// Reveals pane, resets controller, focuses input
```

### Modified: `MainWindowView`

```swift
// Podedge/Podedge/Views/MainWindowView.swift
// Add AssistantPaneView as trailing column in NavigationSplitView
// @AppStorage("assistantPaneVisible") var paneVisible = true
```

### Modified: `SettingsView`

```swift
// Podedge/Podedge/Views/Settings/SettingsView.swift
// The LLM Providers tab is created by Spec 04.
// This spec adds Assistant-specific settings to that tab:
//   - Per-session rate limits (tool calls/min, destructive/hour)
//   - "Always propose, never execute" toggle
```

## File Map

| Action | Path |
|--------|------|
| **Modify** | `PodedgeCore/Sources/PodedgeCore/Services/LLMProvider.swift` — extend protocol |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/AssistantController.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/AssistantMessage.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/Router.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/EscapeHatchResponder.swift` |
| **Create** | `Podedge/Podedge/Views/Assistant/AssistantPaneView.swift` |
| **Create** | `Podedge/Podedge/Views/Assistant/AssistantShortcut.swift` |
| **Modify** | `Podedge/Podedge/Views/MainWindowView.swift` — add pane |
| **Modify** | `Podedge/Podedge/Views/Settings/SettingsView.swift` — add Assistant settings to LLM Providers tab |
| **Modify** | `Podedge/Podedge/AppServices.swift` — construct `AssistantController`, `Router` |

## Data Flow

1. User presses ⌘K → `AssistantController.reset()`, pane revealed, input focused.
2. User submits utterance → `AssistantController.submit(utterance)`.
3. `Router.route(utterance)` → keyword check → LLM classifier if needed → `RouterDecision.agent("promoter")`.
4. `PromoterAgent.run(utterance:context:)` → calls tools via `ToolBroker`.
5. Each tool call: rate-limit check → `ToolBroker.invoke` → `AuditLogService.record`.
6. Destructive tool: `ToolBroker` returns `.needsConfirmation` → `ConfirmationCoordinator` sheet.
7. Agent streams response text → `AssistantMessage.text` updated incrementally.
8. Final message includes `toolCalls` array and `providerLabel` (e.g. "Qwen3-8B · MLX" or "llama3.1:8b · Ollama").

## Error Model

| Failure | Response |
|---------|----------|
| Rate limit hit | "I've reached the limit for this session. You can continue manually: [deep-link]" |
| Provider unreachable (Ollama not running) | `EscapeHatchResponder.response(.providerUnreachable)` with Settings link |
| Iteration cap | `EscapeHatchResponder.response(.iterationCapExceeded)` with manual UI link |
| Tool call failed | Inline error in tool-call row; agent may retry once |

## Concurrency Model

- `AssistantController` is `@MainActor @Observable` — all state mutations on main actor.
- `Router` is a `Sendable` struct; its `route` method is `async` (may call LLM).
- `MLXLLMProvider` is an `actor`; `OllamaLLMProvider` is a `Sendable` struct — both are `async`.
- Streaming: `AsyncThrowingStream` is consumed in `AssistantController.submit` with `for await event in stream`.

## Test Strategy

**Unit tests** (`RouterTests.swift`):
- `testKeywordRulePromoter` — "/promote" → `.agent("promoter")`.
- `testKeywordRulePublish` — "/publish" → `.agent("publish-assistant")`.
- `testUnknownUtteranceCallsLLM` — no keyword → LLM classifier called.

**Unit tests** (`AssistantControllerTests.swift`):
- `testDestructiveCapEnforced` — property test (see requirements).
- `testUntrustedContentIsWrapped` — property test (see requirements).
- `testResetClearsMessages` — `reset()` → `messages.isEmpty`.

## Open Questions / Risks

1. **`LLMProvider` protocol extension is breaking:** Adding `capabilities`, `complete(tools:)`, and `stream(tools:)` requires all existing conformances to be updated. Add default implementations where possible to ease migration.
2. **`AssistantController` in `PodedgeCore`:** `@Observable` requires the `Observation` framework (macOS 14+). Confirmed acceptable given the macOS 15+ deployment target.
3. **Router LLM call latency:** The classifier LLM call adds latency before the first agent response. Consider caching recent routing decisions with a short TTL.
4. **Ollama tool-use detection:** The provider must detect at runtime whether the selected Ollama model supports native tool-use. See Spec 04 design for the detection strategy.
