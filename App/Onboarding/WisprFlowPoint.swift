import AppKit
import KotobaCore
import KotobaStorage
import SwiftUI

/// Welcome's one row for a Wispr Flow user (owner QA 1, Q1 and Q2): what comes along. The dictionary comes on the last
/// step; the shortcuts come here, Wispr Flow's chords for the two ways to dictate as keycaps, set with one click by
/// "Use Shortcuts". A mode whose Wispr Flow chord kotoba cannot take keeps kotoba's own, which its row's Change… sets.
/// kotoba does not quit Wispr Flow: a line says so when it runs. Laid out as the rows around it (qa1-review 10): the
/// tile beside the title and one line of text, the button on the title line, and under them one line with each way to
/// dictate in the shortcut rows' keycaps.
struct WisprFlowPoint: View {
    let model: OnboardingModel
    /// nil: Wispr Flow has no shortcut for either way to dictate, or its file could not be read.
    let shortcuts: WisprShortcuts?

    var body: some View {
        let hasShortcuts = !(shortcuts?.chords ?? []).isEmpty
        VStack(alignment: .leading) {
            PageRow(title: "From Wispr Flow", subtitle: text(hasShortcuts: hasShortcuts)) {
                SymbolTile(systemImage: "square.and.arrow.down", tint: .indigo, side: PageMetrics.rowTileSide)
            } trailing: {
                if hasShortcuts {
                    action
                }
            }
            if let shortcuts, hasShortcuts {
                HStack(alignment: .firstTextBaseline) {
                    mode(.handsFree, shortcuts.handsFree)
                    mode(.pushToTalk, shortcuts.pushToTalk)
                }
                .inRowTextColumn()
            }
        }
    }

    /// A way to dictate with Wispr Flow's chord after its name (a chord never shows alone), or the word that kotoba
    /// keeps its own when it cannot take Wispr Flow's.
    @ViewBuilder private func mode(_ role: ChordRole, _ found: WisprShortcuts.Found?) -> some View {
        switch found {
        case .usable(let chord):
            HStack(alignment: .firstTextBaseline) {
                Text(StatusText.shortcutTitle(role))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                NamedKeycaps(keys: chord.keycaps)
            }
            .accessibilityElement(children: .combine)
        case .unusable:
            Text("\(StatusText.shortcutTitle(role)) keeps kotoba’s keys")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder private var action: some View {
        if model.usesWisprShortcuts {
            StatusLine("In use", .good)
        } else {
            Button("Use Shortcuts", action: model.useWisprShortcuts)
                .accessibilityLabel("Use Your Wispr Flow Shortcuts")
        }
    }

    /// What comes along: the dictionary when the last step can import it (the shortcuts show under it), and the line
    /// when Wispr Flow runs on the same keys.
    private func text(hasShortcuts: Bool) -> String {
        let text =
            switch (model.offersWisprImport, hasShortcuts) {
            case (true, true): "Import your dictionary on the last step."
            case (true, false): "Import your Wispr Flow dictionary on the last step."
            case (false, _): "Use the shortcuts you know from Wispr Flow."
            }
        guard hasShortcuts, model.usesWisprShortcuts, model.wisprRunsWithSameKeys else { return text }
        return text + " Wispr Flow uses these keys too. Quit it, or both apps start dictating."
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
