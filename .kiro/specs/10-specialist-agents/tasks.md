# Tasks — Spec 10: Specialist Agents

- [-] Task 1: Create `SpecialistAgent` protocol and supporting types
  Create the `SpecialistAgent` protocol plus `AgentContext` and `AgentResponse` value types. Also create a `ModelCapabilityTier` enum with `.t1`, `.t2`, `.t3` levels for model quality gating (distinct from the existing tool-access `CapabilityTier`).
  Files: `PodedgeCore/Sources/PodedgeCore/Services/SpecialistAgent.swift`

- [~] Task 2: Create `CapabilityTierService` with known-models lookup
  Create `CapabilityTierService` struct with a static `tier(for:)` method that maps `LLMProviderCapabilities.modelID` to `ModelCapabilityTier` (.t1/.t2/.t3) using prefix matching. Include the lookup table from the design doc.
  Files: `PodedgeCore/Sources/PodedgeCore/Services/CapabilityTierService.swift`
  Dependencies: Task 1

- [-] Task 3: Create `PerShowGuidesService`
  Create `PerShowGuidesService` struct that reads per-show markdown guide files from `~/Library/Application Support/Podedge/Shows/<showID>/<name>.md`. Returns nil if file doesn't exist.
  Files: `PodedgeCore/Sources/PodedgeCore/Services/PerShowGuidesService.swift`

- [-] Task 4: Write agent prompt resources
  Create the four markdown resource files: `_safety.md`, `_escape-hatch.md`, `promoter.md`, `publish-assistant.md` in `Resources/Agents/`.
  Files: `PodedgeCore/Sources/PodedgeCore/Resources/Agents/_safety.md`, `PodedgeCore/Sources/PodedgeCore/Resources/Agents/_escape-hatch.md`, `PodedgeCore/Sources/PodedgeCore/Resources/Agents/promoter.md`, `PodedgeCore/Sources/PodedgeCore/Resources/Agents/publish-assistant.md`

- [~] Task 5: Create `PromoterAgent`
  Create `PromoterAgent` struct conforming to `SpecialistAgent`. Implements the tool-loop: loads system prompt from bundled resources, appends per-show guide, calls LLM with tool whitelist, executes tool calls via `ToolBroker`, respects iteration cap.
  Files: `PodedgeCore/Sources/PodedgeCore/Agents/PromoterAgent.swift`
  Dependencies: Task 1, Task 4

- [~] Task 6: Create `PublishAssistantAgent`
  Create `PublishAssistantAgent` struct conforming to `SpecialistAgent`. Follows the publish flow: identify episode, validate feed, dry-run, confirm, publish. Uses its tool whitelist and respects iteration cap.
  Files: `PodedgeCore/Sources/PodedgeCore/Agents/PublishAssistantAgent.swift`
  Dependencies: Task 1, Task 4

- [~] Task 7: Add `allowedTools` to `ToolCaller` and enforce in `ToolBroker`
  Extend `ToolCaller` protocol with `var allowedTools: Set<String>? { get }` (defaulting to nil = all tools). Update `ToolBroker.invoke` and `ToolBroker.invokeConfirmed` to check caller's `allowedTools` before executing. Create `AgentCaller` struct used by specialist agents.
  Files: `PodedgeCore/Sources/PodedgeCore/Services/ToolDefinition.swift`, `PodedgeCore/Sources/PodedgeCore/Services/ToolBroker.swift`
  Dependencies: Task 1

- [~] Task 8: Add agent registry to `AssistantController` and wire in `AppServices`
  Add `agents: [String: any SpecialistAgent]` dictionary and `register(_:)` method to `AssistantController`. Modify `generateResponse` to look up the agent, check capability tier (warn if below minimum), load per-show guide, and call `agent.run`. Update `AppServices` to construct `CapabilityTierService`, `PerShowGuidesService`, both agents, and register them.
  Files: `PodedgeCore/Sources/PodedgeCore/Services/AssistantController.swift`, `Podedge/Podedge/AppServices.swift`
  Dependencies: Task 2, Task 3, Task 5, Task 6, Task 7

- [~] Task 9: Write unit tests
  Write `PromoterAgentTests`, `PublishAssistantAgentTests`, `CapabilityTierServiceTests`, and `PerShowGuidesServiceTests`. Test whitelist enforcement, iteration cap, safety prompt prepending, tier lookups, and guide reading.
  Files: `PodedgeCore/Tests/PodedgeCoreTests/PromoterAgentTests.swift`, `PodedgeCore/Tests/PodedgeCoreTests/PublishAssistantAgentTests.swift`, `PodedgeCore/Tests/PodedgeCoreTests/CapabilityTierServiceTests.swift`, `PodedgeCore/Tests/PodedgeCoreTests/PerShowGuidesServiceTests.swift`
  Dependencies: Task 5, Task 6, Task 2, Task 3, Task 8
