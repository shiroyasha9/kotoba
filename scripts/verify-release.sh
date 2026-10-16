#!/bin/zsh
# Checks an exported release app before it goes to notarization (docs/release.md): what notarization or Sparkle
# would reject, checked on the app itself. Usage: scripts/verify-release.sh build/release/export/kotoba.app
set -euo pipefail

app=${1:?usage: verify-release.sh <kotoba.app>}
project=${0:A:h:h}/project.yml
sparkle=$app/Contents/Frameworks/Sparkle.framework/Versions/B
failed=0
ok() { print -r -- "  ok   $1" }
bad() { print -r -- "  FAIL $1"; failed=1 }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist" 2>/dev/null || true }
declared() { awk -v key="$1:" '$1 == key { gsub(/"/, "", $2); print $2; exit }' "$project" }
team=$(declared DEVELOPMENT_TEAM)

print -r -- "Verifying $app"

if codesign --verify --deep --strict "$app" 2>/dev/null; then ok "signature valid (deep, strict)"; else bad "signature invalid"; fi

# Each piece of nested code: our Developer ID, hardened runtime, secure timestamp. `xcodebuild build` leaves
# Sparkle's helpers with upstream signatures; only the archive export re-signs them, and notarization rejects the rest.
for code in "$app" "$app/Contents/Frameworks/Sparkle.framework" "$sparkle/Autoupdate" "$sparkle/Updater.app" \
  "$sparkle/XPCServices/Installer.xpc" "$sparkle/XPCServices/Downloader.xpc"; do
  name=${code#${app:h}/}
  info=$(codesign -dvv "$code" 2>&1) || { bad "$name: missing or unsigned"; continue }
  [[ $info == *"Authority=Developer ID Application: "*"($team)"* ]] || { bad "$name: not signed with our Developer ID"; continue }
  [[ $info == *"flags="*"(runtime)"* ]] || { bad "$name: no hardened runtime"; continue }
  [[ $info == *"Timestamp="* ]] || { bad "$name: no secure timestamp"; continue }
  ok "$name: Developer ID ($team), hardened runtime, timestamp"
done

if codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q get-task-allow; then
  bad "get-task-allow entitlement present (a debug signature)"
else
  ok "no get-task-allow entitlement"
fi

archs=$(lipo -archs "$app/Contents/MacOS/kotoba" 2>/dev/null) || archs=none
if [[ $archs == *arm64* && $archs == *x86_64* ]]; then ok "universal ($archs)"; else bad "not universal ($archs)"; fi

version=$(plist CFBundleShortVersionString) build=$(plist CFBundleVersion)
if [[ $version == "$(declared MARKETING_VERSION)" && $build == "$(declared CURRENT_PROJECT_VERSION)" ]]; then
  ok "version $version ($build) matches project.yml"
else
  bad "version $version ($build) does not match project.yml"
fi

# The release identity never changes: Sparkle, TCC grants, UserDefaults and the Keychain item hang on it. Debug
# builds use their own (scripts/check-dev-install.sh).
release=tech.teensy.kotoba
id=$(plist CFBundleIdentifier) name=$(plist CFBundleDisplayName)
if [[ $id == "$release" && $name == kotoba && $(plist CFBundleName) == kotoba ]]; then
  ok "release identity: $name ($id)"
else
  bad "identity $name ($id) is not the release's: kotoba ($release)"
fi

[[ -n $(plist SUPublicEDKey) && -n $(plist SUFeedURL) ]] && ok "Sparkle feed and public key set" ||
  bad "SUFeedURL or SUPublicEDKey missing"

(( failed == 0 )) || { print -r -- "Verification failed."; exit 1 }
print -r -- "All checks passed."
