import AppKit
import KotobaCore
import KotobaStorage
import SwiftUI

/// Welcome's one row for a Wispr Flow user (owner QA 1, Q1 and Q2): what comes along. The dictionary comes on the last
/// step; the shortcuts come here, Wispr Flow's chords for the two ways to dictate as keycaps, set with one click by
/// "Use Your Wispr Flow Shortcuts". A mode whose Wispr Flow chord kotoba cannot take keeps kotoba's own, which its
/// row's Change… sets. kotoba does not quit Wispr Flow: a line says so when it runs.
struct WisprFlowPoint: View {
    let model: OnboardingModel
    /// nil: Wispr Flow has no shortcut for either way to dictate, or its file could not be read.
    let shortcuts: WisprShortcuts?

    var body: some View {
        let usable = shortcuts?.chords ?? []
        TileLabel(title: "From Wispr Flow", subtitle: text(hasShortcuts: !usable.isEmpty)) {
            SymbolTile(systemImage: "square.and.arrow.down", tint: .indigo, side: PageMetrics.rowTileSide)
        } extra: {
            if !usable.isEmpty {
                // The chords and their button on one line while they fit, so the row stays short; else the button
                // goes under the chords.
                ViewThatFits(in: .horizontal) {
                    HStack {
                        chords(usable)
                        Spacer()
                        action
                    }
                    VStack(alignment: .leading) {
                        HStack { chords(usable) }
                        action
                    }
                }
                if let note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Each chord after its mode's name: a chord never shows alone.
    private func chords(_ usable: [(ChordRole, Chord)]) -> some View {
        ForEach(usable, id: \.0) { role, chord in
            HStack {
                Text(StatusText.shortcutTitle(role))
                    .foregroundStyle(.secondary)
                Keycaps(keys: chord.keycaps)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var action: some View {
        if model.usesWisprShortcuts {
            StatusLine("In use", .good)
        } else {
            Button("Use Your Wispr Flow Shortcuts", action: model.useWisprShortcuts)
                .fixedSize()
        }
    }

    /// What comes along: the dictionary when the last step can import it, the shortcuts when kotoba can take one.
    private func text(hasShortcuts: Bool) -> String {
        switch (model.offersWisprImport, hasShortcuts) {
        case (true, true): "Import your dictionary on the last step, and use your shortcuts here."
        case (true, false): "Bring your Wispr Flow dictionary along. You can import it on the last step."
        case (false, _): "Use the shortcuts you know from Wispr Flow."
        }
    }

    /// Under the chords: Wispr Flow runs on the same keys, or a mode kotoba keeps its own chord for.
    private var note: String? {
        if model.usesWisprShortcuts, model.wisprRunsWithSameKeys {
            return "Wispr Flow uses these keys too. Quit it, or both apps start dictating."
        }
        let kept = [(ChordRole.handsFree, shortcuts?.handsFree), (.pushToTalk, shortcuts?.pushToTalk)]
            .filter { $0.1 == .unusable }
            .map { StatusText.shortcutTitle($0.0).lowercased() }
        guard let mode = kept.first else { return nil }
        return "kotoba can’t use your \(mode) keys, so it keeps its own."
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
