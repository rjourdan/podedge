WORKSPACE = Podedge.xcworkspace
SCHEME_APP = Podedge
SCHEME_CORE = PodedgeCore
DESTINATION = platform=macOS

XCODEBUILD = xcodebuild -workspace $(WORKSPACE) -destination '$(DESTINATION)'

.PHONY: build build-core test test-core lint format check clean help

build: ## Build the full app
	$(XCODEBUILD) -scheme $(SCHEME_APP) build

build-core: ## Build PodedgeCore only
	$(XCODEBUILD) -scheme $(SCHEME_CORE) build

test: ## Run all tests
	$(XCODEBUILD) -scheme $(SCHEME_APP) test

test-core: ## Run PodedgeCore tests only
	$(XCODEBUILD) -scheme $(SCHEME_CORE) test

lint: ## Run SwiftLint
	swiftlint lint --strict

format: ## Run swift-format (dry run)
	swift-format lint -r PodedgeCore/Sources Podedge/

format-fix: ## Run swift-format and apply fixes
	swift-format format -i -r PodedgeCore/Sources Podedge/

check: lint build test ## Lint, build, and test everything

check-core-imports: ## Verify PodedgeCore has no SwiftUI/AppKit imports
	@if grep -r 'import SwiftUI\|import AppKit' PodedgeCore/Sources/ 2>/dev/null; then \
		echo "ERROR: PodedgeCore must not import SwiftUI or AppKit"; exit 1; \
	else \
		echo "OK: No SwiftUI/AppKit imports in PodedgeCore"; \
	fi

clean: ## Clean build artifacts
	$(XCODEBUILD) -scheme $(SCHEME_APP) clean
	rm -rf .build

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
