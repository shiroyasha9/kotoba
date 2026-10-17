# kotoba: every change passes `make check`.
PROJECT     := Kotoba.xcodeproj
SCHEME      := Kotoba
# `make build` writes the app the owner runs; `make check` builds into its own folder and never replaces it.
DERIVED     := build/DerivedData
# Several agents can run `make check` at once: `AGENT=<name>` gives each its own build folders.
CHECK_DERIVED := build/DerivedData-check$(if $(AGENT),-$(AGENT))
SCRATCH = $(if $(AGENT),--scratch-path $(1)/.build-$(AGENT))
DEBUG_APP = $(1)/Build/Products/Debug/kotoba.app
SWIFT_SRC   := App KotobaCore/Sources KotobaCore/Tests KotobaCore/Package.swift \
               KotobaProviders/Sources KotobaProviders/Tests KotobaProviders/Package.swift \
               KotobaStorage/Sources KotobaStorage/Tests KotobaStorage/Package.swift
SWIFTFORMAT := xcrun swift-format

.PHONY: gen build build-check test lint lint-files format format-lint privacy check view-checks snapshots readme-images memory window-memory latency latency-log \
	release dmg appcast

gen:
	xcodegen generate --use-cache --quiet

XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
	-destination 'platform=macOS,arch=arm64' -quiet build

# A Debug build is its own install (App/Install.swift); each build checks it does not carry the release's identity.
build: gen
	$(XCODEBUILD) -derivedDataPath $(DERIVED)
	scripts/check-dev-install.sh $(call DEBUG_APP,$(DERIVED))

build-check: gen
	$(XCODEBUILD) -derivedDataPath $(CHECK_DERIVED)
	scripts/check-dev-install.sh $(call DEBUG_APP,$(CHECK_DERIVED))

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

# The repo is public: no home or temp paths, personal email addresses, API keys or private key blocks in tracked files.
privacy:
	scripts/privacy.sh

check: privacy format-lint lint build-check view-checks test

# Every registered view's layout checks and the pills' VoiceOver checks (App/Snapshots.swift `--snapshot-checks`), with
# no image written.
view-checks: build-check
	$(call DEBUG_APP,$(CHECK_DERIVED))/Contents/MacOS/kotoba --snapshot-checks

# Renders the registered views (App/Snapshots.swift) to PNGs, light and dark, offscreen: no screen capture, no TCC.
SNAPSHOTS := build/snapshots$(if $(AGENT),-$(AGENT))
snapshots: build-check
	$(call DEBUG_APP,$(CHECK_DERIVED))/Contents/MacOS/kotoba --snapshots $(SNAPSHOTS)

# The README's screenshots (`Pane.readmeSnapshots`) in macOS's default blue accent, not this Mac's (-AppleAccentColor 4
# sets it for this run only), copied to docs/images.
README_SHOTS := build/readme-images$(if $(AGENT),-$(AGENT))
readme-images: build-check
	$(call DEBUG_APP,$(CHECK_DERIVED))/Contents/MacOS/kotoba --snapshots $(README_SHOTS) -AppleAccentColor 4
	cp $(README_SHOTS)/readme-*.png docs/images/

# The main window's memory, offscreen, with sample data (App/Settings/SettingsSnapshots.swift `measureWindowMemory`):
# footprint at launch, with every pane shown and after close. Run with the environment the app gets from Launch Services
# (`LSEnvironment` in project.yml), which a binary started from the shell does not get.
LS_ENVIRONMENT = $(shell /usr/libexec/PlistBuddy -c 'Print :LSEnvironment' App/Info.plist 2>/dev/null | awk '/=/ { print $$1 "=" $$3 }')
window-memory: build-check
	env $(LS_ENVIRONMENT) $(call DEBUG_APP,$(CHECK_DERIVED))/Contents/MacOS/kotoba --window-memory

# System checks (docs/spec.md, "Testing Decisions"): run by hand against the running app, not part of `check`.
memory:
	PID="$(PID)" APP="$(if $(filter 1,$(DEV)),$(abspath $(call DEBUG_APP,$(DERIVED))),$(APP))" scripts/memory.sh

latency:
	RUN=$(RUN) DEV=$(DEV) scripts/latency.sh

# The same gate and the stop path split from the unified log (`log show`), with no database read.
latency-log:
	DEV=$(DEV) LAST=$(LAST) FROM=$(FROM) scripts/latency-log.sh

# Release (docs/release.md): `make dmg` builds, notarizes and staples the app and the DMG; `make appcast` writes the
# Sparkle feed for that DMG. Everything lands in build/release/; nothing is uploaded.
RELEASE        := build/release
ARCHIVE        := $(RELEASE)/kotoba.xcarchive
RELEASE_APP    := $(RELEASE)/export/kotoba.app
VERSION        := $(shell awk '$$1 == "MARKETING_VERSION:" { gsub(/"/, "", $$2); print $$2 }' project.yml)
DMG            := $(RELEASE)/kotoba-$(VERSION).dmg
SIGN_IDENTITY  := $(shell awk -F'"' '/CODE_SIGN_IDENTITY:/ { print $$2; exit }' project.yml)
# Your notarytool keychain profile (`xcrun notarytool store-credentials`): `make dmg NOTARY_PROFILE=<name>`.
NOTARY_PROFILE ?=
SPARKLE_BIN    := $(RELEASE)/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
# The Keychain account of the EdDSA private key (`generate_keys --account kotoba`); SUPublicEDKey is its public key.
SPARKLE_ACCOUNT := kotoba
DOWNLOAD_URL   := https://github.com/shiroyasha9/kotoba/releases/download/v$(VERSION)/

# Archive, not build: only the archive export re-signs Sparkle's XPC services, Autoupdate and Updater.app with the
# Developer ID, hardened runtime and a secure timestamp. The archive is also universal (arm64 and x86_64).
release: gen
	test -n "$(NOTARY_PROFILE)" || { echo "Set NOTARY_PROFILE to your notarytool keychain profile: make dmg NOTARY_PROFILE=<name>"; exit 1; }
	rm -rf $(ARCHIVE) $(RELEASE)/export
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -quiet \
		-destination 'generic/platform=macOS' -archivePath $(ARCHIVE) -derivedDataPath $(RELEASE)/DerivedData \
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp archive
	xcodebuild -exportArchive -quiet -archivePath $(ARCHIVE) -exportPath $(RELEASE)/export \
		-exportOptionsPlist scripts/ExportOptions.plist
	scripts/verify-release.sh $(RELEASE_APP)
	ditto -c -k --keepParent $(RELEASE_APP) $(RELEASE)/kotoba-notarize.zip
	xcrun notarytool submit $(RELEASE)/kotoba-notarize.zip --keychain-profile $(NOTARY_PROFILE) --wait
	rm $(RELEASE)/kotoba-notarize.zip
	xcrun stapler staple $(RELEASE_APP)

# APFS with lzfse, as Sparkle recommends for DMG updates. The DMG gets its own signature, notarization and ticket,
# so Gatekeeper accepts it before it is opened.
dmg: release
	rm -rf $(RELEASE)/dmg $(DMG) && mkdir -p $(RELEASE)/dmg
	ditto $(RELEASE_APP) $(RELEASE)/dmg/kotoba.app
	ln -s /Applications $(RELEASE)/dmg/Applications
	hdiutil create -quiet -volname kotoba -srcfolder $(RELEASE)/dmg -fs APFS -format ULFO $(DMG)
	rm -rf $(RELEASE)/dmg
	codesign --sign "$(SIGN_IDENTITY)" --timestamp $(DMG)
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DMG)
	xcrun stapler validate $(DMG)
	spctl -a -vv -t install $(DMG)

# One item, the current DMG: each GitHub release carries its own appcast.xml, and the feed URL reads the latest
# release's copy. NOTES=<file.md> embeds release notes. generate_appcast signs with the key in the login Keychain.
appcast:
	test -f $(DMG) || { echo "$(DMG) is missing: run make dmg first"; exit 1; }
	rm -rf $(RELEASE)/updates && mkdir -p $(RELEASE)/updates
	cp -c $(DMG) $(RELEASE)/updates/
	$(if $(NOTES),cp $(NOTES) $(RELEASE)/updates/kotoba-$(VERSION).md)
	$(SPARKLE_BIN)/generate_appcast --account $(SPARKLE_ACCOUNT) --download-url-prefix $(DOWNLOAD_URL) \
		--maximum-versions 1 --maximum-deltas 0 $(if $(NOTES),--embed-release-notes) \
		-o $(RELEASE)/appcast.xml $(RELEASE)/updates
