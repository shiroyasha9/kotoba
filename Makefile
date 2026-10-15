# kotoba: every change passes `make check`.
PROJECT     := Kotoba.xcodeproj
SCHEME      := Kotoba
DERIVED     := build/DerivedData
SWIFT_SRC   := App KotobaCore/Sources KotobaCore/Tests KotobaCore/Package.swift
SWIFTFORMAT := xcrun swift-format

.PHONY: gen build test lint format format-lint check

gen:
	xcodegen generate --use-cache --quiet

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet build

test:
	swift test --package-path KotobaCore

lint:
	swiftlint lint --strict --quiet

format:
	$(SWIFTFORMAT) format --in-place --recursive --parallel $(SWIFT_SRC)

format-lint:
	$(SWIFTFORMAT) lint --strict --recursive --parallel $(SWIFT_SRC)

check: format-lint lint build test
