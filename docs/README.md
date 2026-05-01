# Podedge Documentation

This tree holds all written documentation for the Podedge project.

## Who each section is for

- **[`dev/`](dev/)** — developers building or maintaining Podedge. Start with [`dev/onboarding.md`](dev/onboarding.md), then skim [`dev/mental-model.md`](dev/mental-model.md).
- **[`user/`](user/)** — end users of the Podedge macOS app. *(Placeholder — no pages written yet.)*
- **[`decisions/`](decisions/)** — Architecture Decision Records. See [`decisions/README.md`](decisions/README.md) for the index and template.

## Authoring conventions

- Plain GitHub-flavored Markdown. Diagrams use Mermaid fenced blocks; ASCII is a fallback only when Mermaid cannot express the idea cleanly.
- Every page starts with a one-sentence summary and its audience.
- Every major page has a short changelog comment near the top: last-updated date and a one-line summary of what changed.
- Prefer linking to source files over copying code into docs. Copied code goes stale.
- Use the project's established vocabulary: *Show*, *Episode*, *Host*, *FeedConfig*, *JobScheduler*, *ToolBroker*, *ConfirmationCoordinator*, *DistributionTarget*, *PodcastHost*, *LLMProvider*, *TranscriptionEngine*.
- Refer to Apple platforms by their official names (macOS, iOS, visionOS).

## Canonical sources this documentation links to

These are the authoritative references. Documentation summarizes and links; it does not duplicate.

- [`.kiro/idea/podedge-technical-design.md`](../.kiro/idea/podedge-technical-design.md) — the full technical design.
- [`.kiro/idea/podedge-spec-user-stories.md`](../.kiro/idea/podedge-spec-user-stories.md) — user stories.
- [`.kiro/idea/podedge-implementation-tasks.md`](../.kiro/idea/podedge-implementation-tasks.md) — implementation plan.
- [`.kiro/steering/swift-general.md`](../.kiro/steering/swift-general.md) and [`swift-api-design-guidelines.md`](../.kiro/steering/swift-api-design-guidelines.md) — Swift and API conventions.
- [`CONTRIBUTING.md`](../CONTRIBUTING.md) — prerequisites, setup, and contribution rules.
