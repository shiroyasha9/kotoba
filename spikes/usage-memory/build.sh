#!/bin/zsh
# Builds UsageSpike (real App/Settings window and Usage pane + KotobaCore, KotobaStorage and KotobaProviders sources,
# one module) and UsageBase (no SwiftUI) into build/. Same signing as spikes/memory. Usage: ./build.sh
set -euo pipefail
cd "${0:A:h}"
ROOT=../..
IDENTITY="Developer ID Application: Mubin Ansari (7U6G55576W)"
mkdir -p build/src
# One module: drop the package imports and the snapshot code (it needs the app's snapshot runner); the app's `Log.app`
# is the core's `Log.pipeline` here. The spike never activates, so the window never takes focus from the owner.
for f in $ROOT/KotobaCore/Sources/KotobaCore/*.swift $ROOT/KotobaStorage/Sources/KotobaStorage/*.swift \
         $ROOT/KotobaProviders/Sources/KotobaProviders/*.swift \
         $ROOT/App/Settings/{SettingsWindow,UsagePane}.swift $ROOT/App/InstalledApp.swift; do
  sed -e '/^import KotobaCore$/d' -e '/^import KotobaStorage$/d' -e '/^import KotobaProviders$/d' \
    -e 's/KotobaCore\.Log/Log/g' -e 's/Log\.app\./Log.pipeline./g' -e '/NSApp.activate()/d' "$f" |
    awk '/^\/\/ MARK: - Snapshots/ { exit } { print }' > "build/src/${f:t}"
done
build() {
  local name=$1; shift
  local app="build/$name.app"
  mkdir -p "$app/Contents/MacOS"
  xcrun swiftc -O -swift-version 6 -target arm64-apple-macos26.0 -module-name Spike "$@" -o "$app/Contents/MacOS/$name"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>tech.teensy.kotoba.usagespike</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict></plist>
PLIST
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$app"
  echo "built $app"
}
build UsageBase main.swift
build UsageSpike -D WITH_USAGE main.swift build/src/*.swift
