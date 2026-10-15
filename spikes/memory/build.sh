#!/bin/zsh
# Builds and signs the spike variants into spikes/memory/build/. Usage: ./build.sh [A B C E]
set -euo pipefail
cd "${0:A:h}"
IDENTITY="Developer ID Application: Mubin Ansari (7U6G55576W)"
BUNDLE_ID="tech.teensy.kotoba.memspike"   # shared by all variants so one mic grant covers them
mkdir -p build
(( $# )) || set -- A B C E
for v in "$@"; do
  app="build/MemSpike$v.app"
  rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
  xcrun swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -D "VARIANT_$v" \
    -o "$app/Contents/MacOS/MemSpike$v" Spike.swift
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>MemSpike$v</string>
  <key>CFBundleExecutable</key><string>MemSpike$v</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>NSMicrophoneUsageDescription</key><string>kotoba memory spike: measures audio engine start time.</string>
</dict></plist>
PLIST
  codesign --force --options runtime --timestamp=none --entitlements spike.entitlements \
    --sign "$IDENTITY" "$app"
  echo "built $app"
done
