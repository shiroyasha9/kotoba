#!/bin/zsh
# Builds HistorySpike (real App/History model and view + KotobaCore + KotobaStorage sources, one module) and HistoryBase
# (no SwiftUI) into build/. Same signing as spikes/memory. Usage: ./build.sh
set -euo pipefail
cd "${0:A:h}"
ROOT=../..
IDENTITY="Developer ID Application: Mubin Ansari (7U6G55576W)"
rm -rf build; mkdir -p build/src
# One module: drop the package imports; the app's `Log.app` is the core's `Log.pipeline` here. The spike never
# activates, so the window never takes focus from the owner.
for f in $ROOT/KotobaCore/Sources/KotobaCore/*.swift $ROOT/KotobaStorage/Sources/KotobaStorage/*.swift \
         $ROOT/App/History/{HistoryModel,HistoryView}.swift $ROOT/App/InstalledApp.swift; do
  sed -e '/^import KotobaCore$/d' -e '/^import KotobaStorage$/d' -e 's/KotobaCore\.Log/Log/g' \
    -e 's/Log\.app\./Log.pipeline./g' "$f" > "build/src/${f:t}"
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
  <key>CFBundleIdentifier</key><string>tech.teensy.kotoba.historyspike</string>
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
build HistoryBase main.swift
build HistorySpike -D WITH_HISTORY main.swift build/src/*.swift
