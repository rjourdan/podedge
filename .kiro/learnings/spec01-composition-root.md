# Spec 01 — Composition Root: Decisions & Learnings

Date: 2026-05-09

---

## Decisions

### 1. AppServices uses @State in PodedgeApp

SwiftUI can reinitialize App structs. Using `@State` ensures the AppServices instance survives reinitialization, maintaining the single-instance invariant.

### 2. Bootstrap idempotency via guard

`bootstrap()` uses a `hasBootstrapped` flag and early-returns on subsequent calls. This is simpler than `precondition` (which would crash) and allows `.task` modifiers to safely re-fire.

### 3. ConfirmationCoordinator stays internal

`ConfirmationCoordinator` is defined in the app target with internal access. AppServices exposes it as `let` (internal) rather than `public let` to avoid the access-level mismatch compiler error.

### 4. Environment key must be optional (no preconditionFailure)

SwiftUI's internal `ChildEnvironment.updateValue()` reads environment key paths during propagation even when no view explicitly accesses them. A `preconditionFailure` in the getter crashes the app at launch. The key must return `AppServices?` with a nil default. Views that need it can force-unwrap at the call site.

### 5. Placeholder implementations for unbuilt services

Protocols without real implementations (AudioPipeline, TranscriptionEngine, AnalyticsProvider) get private placeholder structs in AppServices.swift. These will be replaced by real implementations in Specs 02-04. The existing `MLXLLMProvider` stub serves as the LLM placeholder.

### 6. Removed standalone ToolBrokerKey

Views access `ToolBroker` directly via constructor injection (ToolButton takes a `broker` parameter), not via `@Environment(\.toolBroker)`. The standalone environment key was dead code.

### 7. shutdown() called on scenePhase .background

macOS apps don't have applicationWillTerminate in SwiftUI App lifecycle. Using `.onChange(of: scenePhase)` with `.background` is the closest equivalent for stopping the scheduler cleanly.

## Pre-existing Issues Found

- `ShowEditorView.swift` line 160: `#Predicate` macro type mismatch with `HostBinding.id == show.hostBindingID`. This is a pre-existing bug unrelated to Spec 01 that blocks the test target from building. Filed for separate fix.

## What Went Well

- All service init signatures were already public and well-documented
- JobScheduler already had the right architecture for handler registration
- PodedgeCore builds cleanly with zero changes beyond adding CaseIterable and handler(for:)
