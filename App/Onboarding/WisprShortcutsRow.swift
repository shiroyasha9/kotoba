import AppKit
import KotobaCore
import KotobaStorage
import SwiftUI

/// Welcome's "Use Your Wispr Flow Shortcuts" row (owner QA 1, Q1): Wispr Flow's chords for the two ways to dictate as
/// keycaps, set with one click. A mode whose Wispr Flow chord kotoba cannot take keeps kotoba's own, which its row's
/// Change… sets. kotoba does not quit Wispr Flow: a line says so when it runs.
struct WisprShortcutsRow: View {
    let model: OnboardingModel
    let shortcuts: WisprShortcuts

    var body: some View {
        let isInUse = model.usesWisprShortcuts
        HStack {
            // The chords under the name, in the row's text column, as a header card's link sits.
            TileLabel(title: "Wispr Flow", subtitle: nil) {
                SymbolTile(systemImage: "keyboard", tint: .indigo, side: PageMetrics.rowTileSide)
            } extra: {
                mode(.handsFree, shortcuts.handsFree)
                mode(.pushToTalk, shortcuts.pushToTalk)
                if isInUse, model.wisprRunsWithSameKeys {
                    Text("Wispr Flow uses these keys too. Quit it, or both apps start dictating.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if isInUse {
                StatusLine("In use", .good)
            } else if !shortcuts.chords.isEmpty {
                Button("Use Your Wispr Flow Shortcuts", action: model.useWisprShortcuts)
            }
        }
    }

    /// One mode's Wispr Flow chord with the mode's name (a chord never shows alone), or why kotoba keeps its own.
    @ViewBuilder private func mode(_ role: ChordRole, _ found: WisprShortcuts.Found?) -> some View {
        switch found {
        case .usable(let chord):
            HStack {
                Text(StatusText.shortcutTitle(role))
                    .foregroundStyle(.secondary)
                Keycaps(keys: chord.keycaps)
            }
            .accessibilityElement(children: .combine)
        case .unusable:
            let mode = StatusText.shortcutTitle(role).lowercased()
            Text("kotoba can’t use your Wispr Flow \(mode) keys, so it keeps its own.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case nil:
            EmptyView()
        }
    }

    /// Wispr Flow's bundle id, as `NSRunningApplication` lists it.
    private static let wisprBundleID = "com.electron.wispr-flow"

    static var isWisprRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: wisprBundleID).isEmpty
    }

    /// `prefs.user.shortcuts` of Wispr Flow's `config.json`, next to the database the Ready step imports from
    /// (`WisprFlowImport.locate`): virtual key codes joined by "+", each mapped to an action. Only that key path is kept;
    /// the file is read on this Mac and goes nowhere. Nil when the file or the key path is missing.
    static func readKeys() async -> [String: String]? {
        await Task.detached(priority: .userInitiated) {
            guard
                let folder = WisprFlowImport.locate()?.deletingLastPathComponent(),
                let data = try? Data(contentsOf: folder.appending(path: "config.json")),
                let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let prefs = config["prefs"] as? [String: Any],
                let user = prefs["user"] as? [String: Any]
            else { return nil }
            return user["shortcuts"] as? [String: String]
        }.value
    }
}
