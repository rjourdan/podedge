# Architecture Decision Records

> Log of significant architectural decisions made on Podedge, and why.
> **Audience:** any contributor trying to understand why the system is shaped the way it is.

## How this works

Podedge uses a lightweight [MADR](https://adr.github.io/madr/)-style format. Each decision is a numbered Markdown file in this directory.

- **File name:** `NNNN-short-title.md` with a zero-padded sequential number (e.g., `0001-layered-architecture.md`).
- **One decision per file.** If a new decision supersedes an older one, write a new ADR and set the old one's status to `Superseded by NNNN`.
- **ADRs are append-only.** To revise a decision, add a new ADR rather than editing the original. The history is the point.
- **Status values:** `Proposed`, `Accepted`, `Superseded by NNNN`, `Deprecated`, or `Inferred — needs confirmation` (used when we document a decision that was made implicitly and the author is reconstructing the rationale).

## Index

*(No ADRs have been written yet. Candidate decisions to capture, drawn from the existing design and steering documents:)*

- `0001-layered-architecture.md` — UI Layer → Service Layer → Models, no upward arrows.
- `0002-podedgecore-no-ui-imports.md` — `PodedgeCore` must not import SwiftUI or AppKit.
- `0003-toolbroker-as-single-action-layer.md` — All user actions route through `ToolBroker`.
- `0004-swiftdata-over-coredata.md` — SwiftData as the persistence layer.
- `0005-durable-jobs-for-long-running-work.md` — `JobScheduler` owns all multi-step and long-running work.
- `0006-keychain-only-for-credentials.md` — No credentials in SwiftData, `UserDefaults`, or files.
- `0007-protocol-based-extension-points.md` — New capabilities via protocol conformers, not by modifying existing code.

## Template

Copy this into a new file when writing an ADR.

```markdown
# NNNN — <short title in sentence case>

<!--
Changelog
- YYYY-MM-DD: <one line>
-->

- **Status:** Proposed | Accepted | Superseded by NNNN | Deprecated | Inferred — needs confirmation
- **Date:** YYYY-MM-DD
- **Deciders:** <names or roles>

## Context

What is the problem we are trying to solve? What forces are at play (technical, organizational, product)? What constraints must the decision respect?

## Decision

The decision in one or two sentences. Be specific enough that a reader can tell whether a given future change honors or violates this decision.

## Consequences

What becomes easier after this decision. What becomes harder. What new obligations (tests, checks, review rules) does it create. What trade-offs are we accepting.

## Alternatives considered

Short list of alternatives with a one-line reason each was not chosen. Include "do nothing" if it was a real option.

## References

Links to relevant code, design documents, prior ADRs, or external material.
```

## Writing guidance

- **Write ADRs for decisions, not for plans.** A decision is something that constrains future code. A plan is something that describes future work. Plans belong in `.kiro/idea/`.
- **The "why" is the valuable part.** A reader five years from now can see *what* the code does. They cannot see *why* the decision was made unless you write it down.
- **Name the alternatives.** If you cannot list the alternatives you rejected, you have not made a decision yet — you have made an assumption.
- **If you are reconstructing a decision that was already made implicitly**, mark the status as `Inferred — needs confirmation` and ask the lead developer to confirm the rationale before changing the status to `Accepted`.
