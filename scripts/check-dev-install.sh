#!/bin/zsh
# Fails when a development build would share the release's identity (App/Install.swift): its bundle id must differ
# from the release's, or it reads and writes the owner's UserDefaults, data folder, Keychain item and TCC grants.
# The release side is checked by scripts/verify-release.sh. Usage: scripts/check-dev-install.sh <Debug kotoba.app>
set -euo pipefail

app=${1:?usage: check-dev-install.sh <kotoba.app>}
release=tech.teensy.kotoba
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist" 2>/dev/null || true }

id=$(plist CFBundleIdentifier)
name=$(plist CFBundleDisplayName)
if [[ -z $id || -z $name || $id == "$release" || $name == kotoba ]]; then
  print -r -- "check-dev-install: $app is \"$name\" ($id): not a separate install. Debug builds need their own" \
    "bundle id and display name (project.yml, Kotoba target, configs: Debug)." >&2
  exit 1
fi
