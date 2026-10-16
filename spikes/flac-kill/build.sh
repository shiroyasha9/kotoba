#!/bin/zsh
# Builds the probe into build/probe. No signing needed: it reads and writes files only. Usage: ./build.sh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos26.0 main.swift -o build/probe
echo "built build/probe"
