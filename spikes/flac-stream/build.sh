#!/bin/zsh
# Builds the FLAC writer into build/writer. No signing needed: it reads and writes files only. Usage: ./build.sh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
xcrun swiftc -O -swift-version 6 -target arm64-apple-macos26.0 main.swift -o build/writer
echo "built build/writer"
