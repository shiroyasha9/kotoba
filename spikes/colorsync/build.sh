#!/bin/zsh
# Builds build/ColorSpike.app (ad hoc signed, no hardened runtime, so `heap` can read it). Usage: ./build.sh
set -euo pipefail
cd "${0:A:h}"
app=build/ColorSpike.app
rm -rf build; mkdir -p "$app/Contents/MacOS"
xcrun swiftc -O -swift-version 6 -target arm64-apple-macos26.0 -o "$app/Contents/MacOS/ColorSpike" Spike.swift
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>tech.teensy.kotoba.colorspike</string>
  <key>CFBundleName</key><string>ColorSpike</string>
  <key>CFBundleExecutable</key><string>ColorSpike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "built $app"
