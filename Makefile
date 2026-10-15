# kotoba: every change passes `make check`.
PROJECT     := Kotoba.xcodeproj
SCHEME      := Kotoba
# `make build` writes the app the owner runs; `make check` builds into its own folder and never replaces it.
DERIVED     := build/DerivedData
# Several agents can run `make check` at once: `AGENT=<name>` gives each its own build folders.
CHECK_DERIVED := build/DerivedData-check$(if $(AGENT),-$(AGENT))
SCRATCH = $(if $(AGENT),--scratch-path $(1)/.build-$(AGENT))
SWIFT_SRC   := App KotobaCore/Sources KotobaCore/Tests KotobaCore/Package.swift \
               KotobaProviders/Sources KotobaProviders/Tests KotobaProviders/Package.swift \
               KotobaStorage/Sources KotobaStorage/Tests KotobaStorage/Package.swift
SWIFTFORMAT := xcrun swift-format

.PHONY: gen build build-check test lint lint-files format format-lint check snapshots memory latency

gen:
	xcodegen generate --use-cache --quiet

XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
	-destination 'platform=macOS,arch=arm64' -quiet build

build: gen
	$(XCODEBUILD) -derivedDataPath $(DERIVED)

build-check: gen
	$(XCODEBUILD) -derivedDataPath $(CHECK_DERIVED)

# Tests build first, then run under a hard limit: a hung test (an await that never resumes) fails
# the run after TEST_LIMIT seconds instead of blocking every agent. Pass FILTER=<name> for one test.
TEST_LIMIT ?= 120
RUN_TESTS = swift build --build-tests --package-path $(1) $(call SCRATCH,$(1)) && \
	scripts/timeout.pl $(TEST_LIMIT) \
	swift test --skip-build --package-path $(1) $(call SCRATCH,$(1)) $(if $(FILTER),--filter $(FILTER)) \
	|| { echo "tests failed or ran over $(TEST_LIMIT) s in $(1)"; exit 1; }

test:
	$(call RUN_TESTS,KotobaCore)
	$(call RUN_TESTS,KotobaProviders)
	$(call RUN_TESTS,KotobaStorage)

lint:
	swiftlint lint --strict --quiet

format:
	$(SWIFTFORMAT) format --in-place --recursive --parallel $(or $(FILES),$(SWIFT_SRC))

# Format check and lint for only the given files, so an agent can test its own work while others edit.
lint-files:
	$(SWIFTFORMAT) lint --strict --parallel $(FILES)
	swiftlint lint --strict --quiet $(FILES)

format-lint:
	$(SWIFTFORMAT) lint --strict --recursive --parallel $(SWIFT_SRC)

check: format-lint lint build-check test

# Renders the registered views (App/Snapshots.swift) to PNGs, light and dark, offscreen: no screen capture, no TCC.
SNAPSHOTS := build/snapshots$(if $(AGENT),-$(AGENT))
snapshots: build-check
	$(CHECK_DERIVED)/Build/Products/Debug/kotoba.app/Contents/MacOS/kotoba --snapshots $(SNAPSHOTS)

# System checks (docs/spec.md, "Testing Decisions"): run by hand against the running app, not part of `check`.
memory:
	scripts/memory.sh

latency:
	RUN=$(RUN) scripts/latency.sh
