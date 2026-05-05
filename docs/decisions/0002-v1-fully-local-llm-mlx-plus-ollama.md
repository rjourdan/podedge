# 0002 — v1 is fully local: MLX in-process plus Ollama, no cloud providers

<!--
Changelog
- 2026-05-05: Initial draft. Accepted.
-->

- **Status:** Accepted
- **Date:** 2026-05-05
- **Deciders:** Lead developer

## Context

Several forces shaped the v1 LLM provider decision:

**Privacy guarantee.** Podedge's core promise is that audio and transcripts never leave the user's Mac. Routing any LLM task to a cloud API would break this guarantee for that task, require explicit consent UI, and split the "fully local" story.

**Tool-use reliability.** The in-app Assistant (a v1 feature) requires the LLM to invoke tools reliably across multi-step flows. This demands a provider with reasonable tool-use support.

**Hardware range.** Target hardware spans 8 GB M1 (entry) to 192 GB M2 Ultra (high end). A single bundled model cannot serve both ends well. Users at the high end often already run Ollama with large models they prefer.

**Large MoE models don't fit in-process.** Models like DeepSeek V4 (~140 GB at 4-bit) and Qwen 3.5 (~200 GB at 4-bit) exceed the unified memory of all but the highest-end Macs. Running them in-process inside Podedge is not viable for most users.

**Ollama is already installed by many target users.** Developers and power users who run local AI commonly have Ollama running. Integrating with it is zero-friction for them.

## Decision

v1 ships two local `LLMProvider` implementations: `MLXLLMProvider` (in-process inference via `mlx-swift-examples`, for models up to ~14 GB) and `OllamaLLMProvider` (HTTP to `localhost:11434`, for larger models and user-managed installs). Onboarding offers three first-class MLX model options plus Ollama as an advanced path. No cloud providers ship in v1.

## Consequences

**Easier:**
- The on-device privacy guarantee holds end-to-end with no exceptions or consent dialogs.
- No API-key friction at onboarding; users can be productive immediately.
- Users with existing Ollama installs integrate with zero additional setup.
- Process isolation for large models: Ollama runs in its own process, so a model-load failure or OOM does not take down Podedge.
- The `LLMProvider` protocol abstraction is validated by two real implementations before cloud providers are added.

**Harder:**
- Every LLM task must tolerate two wire formats: MLX (in-process actor calls) and Ollama (HTTP NDJSON streaming). Both providers must implement the same `LLMProvider` protocol including the tool-use extension from Spec 09.
- Onboarding must handle a new "Ollama not running" error path with a clear recovery hint.
- Users who want models beyond the three MLX defaults must install Ollama separately.
- Tool-use reliability varies by model. The `CapabilityTierService` tier warnings exist to surface this to users.

## Alternatives considered

**(a) MLX only, in-process, for all models including 100 GB+ class.**
Rejected for v1 for five reasons:
1. Resumable 100 GB+ downloads require engineering (range-get, integrity check, pause/resume UI) that is out of v1 scope.
2. Pre-flight RAM gating requires an empirical model→RAM table that must be maintained as new models are released.
3. `mlx-swift-examples` support for specific MoE architectures (DeepSeek V4 routing, Qwen 3.5 A17B) is an empirical unknown and may lag `mlx-python` by weeks or months.
4. MLX model load failures crash Podedge's address space; Ollama's process isolation avoids this.
5. Cold-start latency of 60–120 seconds on first inference is poor UX for large models.
Deferred to v1.1+ as a known-gap item.

**(b) Anthropic Claude API as the reliable tool-use option, MLX as local fallback.**
Rejected for v1 because it contradicts the on-device privacy promise, creates a cloud dependency users did not opt into, and forces consent dialogs and API-key management into the v1 onboarding flow. Deferred to v1.1 as an opt-in upgrade for users who want top-tier quality or are comfortable with cloud providers.

**(c) MLX + Ollama, both local, in v1.** Chosen.

## References

- [`.kiro/specs/04-local-llm-mlx/`](../../.kiro/specs/04-local-llm-mlx/) — the spec these constraints land in.
- [`.kiro/specs/09-assistant-core/`](../../.kiro/specs/09-assistant-core/) — how tool-use flows through these providers.
- [`.kiro/idea/podedge-spec-user-stories.md`](../../.kiro/idea/podedge-spec-user-stories.md) — privacy guarantees this decision protects.
