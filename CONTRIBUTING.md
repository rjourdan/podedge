# Contributing to Podedge

## Prerequisites

### Hardware

- Apple Silicon Mac (M1 or later). Intel is not supported.
- 16 GB RAM minimum (32 GB recommended — MLX model inference is memory-hungry).
- ~20 GB free disk space (Xcode + models + build artifacts).

### Software

| Tool | Minimum Version | Install |
|---|---|---|
| macOS | 15.0 (Sequoia) | System Settings → Software Update |
| Xcode | 16.0 | Mac App Store or [developer.apple.com/xcode](https://developer.apple.com/xcode/) |
| Xcode Command Line Tools | (bundled with Xcode) | `xcode-select --install` |
| Git | 2.39+ | Bundled with CLT |
| SwiftLint | latest | `brew install swiftlint` |

### Verify your setup

```bash
# Apple Silicon check
uname -m
# Expected: arm64

# macOS version
sw_vers --productVersion
# Expected: 15.x

# Xcode
xcodebuild -version
# Expected: Xcode 16.x

# Swift
swift --version
# Expected: Apple Swift version 6.x

# Accept Xcode license (first time only)
sudo xcodebuild -license accept
```

### Optional (for specific features)

| Tool | Purpose | Install |
|---|---|---|
| [Homebrew](https://brew.sh) | Package manager for optional tools | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| [Ollama](https://ollama.com) | Run larger local LLMs for assistant testing (v1.1) | `brew install ollama` |
| [LocalStack](https://localstack.cloud) | Mock S3 for integration tests | `brew install localstack/tap/localstack-cli` |
| [swift-format](https://github.com/swiftlang/swift-format) | Code formatting | `brew install swift-format` |

## Getting Started

```bash
git clone https://github.com/rjourdan/podedge.git
cd podedge
open Podedge.xcworkspace
```

Select the **Podedge** scheme, target **My Mac**, and build (⌘B).

## Project Structure

```
Podedge.xcworkspace
├── PodedgeCore/              # Swift package — all non-UI code
│   ├── Sources/PodedgeCore/
│   │   ├── Models/           # SwiftData @Model types + enums
│   │   ├── Services/         # Business logic
│   │   ├── Extensions/       # Protocol definitions
│   │   ├── Hosts/            # PodcastHost implementations
│   │   ├── Distribution/     # DistributionTarget implementations
│   │   ├── LLM/              # LLMProvider implementations
│   │   ├── Analytics/        # AnalyticsProvider implementations
│   │   └── Utilities/        # Logger, helpers
│   └── Tests/PodedgeCoreTests/
├── Podedge/                  # macOS app target (SwiftUI)
│   ├── UI/
│   ├── Resources/
│   └── PodedgeApp.swift
└── PodedgeTests/             # App-level + integration tests
```

**Rule:** `PodedgeCore` must not import SwiftUI or AppKit. This keeps it
reusable for the CLI and MCP server targets.

## Building & Testing

```bash
# Build the full workspace
xcodebuild -workspace Podedge.xcworkspace -scheme Podedge -destination 'platform=macOS' build

# Run PodedgeCore tests
xcodebuild -workspace Podedge.xcworkspace -scheme PodedgeCore -destination 'platform=macOS' test

# Run all tests
xcodebuild -workspace Podedge.xcworkspace -scheme Podedge -destination 'platform=macOS' test

# Lint
swiftlint lint --strict
```

## Code Style

- Follow existing patterns in the codebase.
- Run `swiftlint` before committing. The pre-commit hook enforces this.
- No `import SwiftUI` or `import AppKit` in `PodedgeCore/`.
- Credentials go in Keychain — never in SwiftData, UserDefaults, or files.
- Secrets must be redacted in log output.

## Architecture Notes

- **Extension points** are protocols (`PodcastHost`, `LLMProvider`, `TranscriptionEngine`, etc.). Add new implementations without modifying existing code.
- **Action Layer** — all actions go through `ToolBroker`. UI buttons and the assistant both call the same tools. Don't bypass the broker with direct service calls from views.
- **Destructive operations** (publish, delete, unpublish) always require UI confirmation via `ConfirmationCoordinator`, regardless of caller.

## Troubleshooting

**"No such module 'SwiftData'"** — Ensure deployment target is macOS 15.0+ and you're building with Xcode 16+.

**Build fails on `aws-sdk-swift` resolution** — Clean the SPM cache: `rm -rf ~/Library/Caches/org.swift.swiftpm` and resolve packages again (File → Packages → Resolve).

**MLX model download hangs** — Check network. Models are ~4–8 GB. The app stores them in `~/Library/Application Support/Podedge/Models/`.
