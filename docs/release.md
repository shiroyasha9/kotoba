# Cutting a release

kotoba updates itself with Sparkle 2. The app reads the feed in `SUFeedURL`
(`https://github.com/shiroyasha9/kotoba/releases/latest/download/appcast.xml`) once a day while "Check for updates
automatically" is on (Settings, General), and when you click "Check for Updates…" in the menu. Sparkle installs an
update only when its EdDSA signature matches `SUPublicEDKey` in `project.yml`.

## Once per machine

- Signing identity: "Developer ID Application: Mubin Ansari (7U6G55576W)" in the login Keychain.
- Notarization credentials: your notarytool keychain profile (`xcrun notarytool store-credentials`, team
  7U6G55576W). Pass its name on every release: `make dmg NOTARY_PROFILE=<name>`.
- Sparkle private key: in the login Keychain, account `kotoba` (item "Private key for signing Sparkle updates").
  `generate_keys --account kotoba -p` prints its public key; it must equal `SUPublicEDKey`. On a new Mac, import the
  backup (below) with `generate_keys --account kotoba -f <file>`.

The Sparkle tools are in `build/release/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/` after the first
`make release`.

## Back up the Sparkle private key

> **Warning:** if you lose this key, no installed copy of kotoba can update again. Every user must then download and
> install a new build by hand. A new key does not help: installed apps trust only the public key they shipped with.

1. `build/release/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account kotoba -x
   ~/kotoba-sparkle-key.txt`
2. Put the file in your password manager (as a secure note or attachment), then delete it from disk.
3. Never commit the key, paste it in chat or put it in a runbook folder.

## Steps

1. In `project.yml`, set `MARKETING_VERSION` (for example `0.2.0`) and raise `CURRENT_PROJECT_VERSION` by one.
   Sparkle compares `CFBundleVersion` (the build number), so it must always go up.
2. `make check`.
3. `make dmg NOTARY_PROFILE=<name>`: Release archive (universal), export with the Developer ID, `scripts/verify-release.sh`, notarize and
   staple the app, then build `build/release/kotoba-<version>.dmg` (with an Applications link), sign, notarize and
   staple it. Each notarization takes a few minutes. The `spctl` output at the end must contain `accepted` and
   `source=Notarized Developer ID`. If notarization fails, read Apple's reason with `xcrun notarytool log
   <submission id> --keychain-profile <name>`.
4. `make appcast NOTES=<notes.md>` (NOTES is optional): writes `build/release/appcast.xml` with one item for this
   DMG, signed with the Keychain key. macOS asks once for Keychain access; allow it.
5. Create the GitHub release with the tag `v<version>` and upload two files: `kotoba-<version>.dmg` and
   `appcast.xml`. The appcast's download URL points at that tag, so the tag and the version must match.
6. Check: open an older build, click "Check for Updates…", and install the update.

## Signing notes

- `make release` archives and exports; it does not use `xcodebuild build`. Only the export re-signs Sparkle's
  `Autoupdate`, `Updater.app` and XPC services with the Developer ID, hardened runtime and a secure timestamp;
  notarization rejects the upstream signatures. `scripts/verify-release.sh` checks each of them.
- kotoba is not sandboxed, so Sparkle's XPC services are not used. They stay in the framework, signed.
- kotoba has no Dock icon, so Sparkle's alert for a scheduled check opens behind other windows. As a gentle
  reminder, the menu bar icon shows a dot and the menu item reads "Install Update…" until the user looks at the
  alert (`App/Updater.swift`).
- Debug builds (`make build`) do not start the updater and hide "Check for Updates…" and the Updates section, so a
  development build is never replaced by a release (`Updater.forThisBuild()`).
