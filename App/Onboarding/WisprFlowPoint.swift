import AppKit
import KotobaStorage
import SwiftUI

/// Welcome's words for a Wispr Flow user (owner QA 2, R1), in one place for a copy pass, and what kotoba reads of
/// Wispr Flow. Welcome took Wispr Flow's shortcuts as it showed, so its "Coming from Wispr Flow" row has no keycaps and
/// no button: the shortcut rows show the keys, and a line under each says which came from Wispr Flow. The dictionary
/// comes on the last step.
enum WisprFlowPoint {
    static let title = "Coming from Wispr Flow"

    /// What comes along: the shortcuts kotoba took (`hasImportedShortcuts`: a way to dictate has Wispr Flow's chord),
    /// and the dictionary when the last step can import it. Nil when neither: Welcome shows no row.
    static func text(hasImportedShortcuts: Bool, offersDictionary: Bool) -> String? {
        switch (hasImportedShortcuts, offersDictionary) {
        case (true, true): "Your shortcuts are set. Import your dictionary on the last step."
        case (true, false): "Your shortcuts are set."
        case (false, true): "Import your dictionary on the last step."
        case (false, false): nil
        }
    }

    /// The footnote under the shortcut rows while Wispr Flow runs: kotoba does not quit it.
    static let runningText = "Quit Wispr Flow, or both apps start when you press these keys."

    /// Under the subtitle of a shortcut row whose chord is Wispr Flow's, also when it equals kotoba's own. The symbol
    /// inline, a space from its words, as a label in a form row puts it in the row's icon column.
    struct ImportedLine: View {
        var body: some View {
            Text("\(Image(systemName: "sparkles")) Imported from Wispr Flow")
                .font(.caption)
                .foregroundStyle(.secondary)
                // Not "Sparkles, Imported…".
                .accessibilityLabel("Imported from Wispr Flow")
        }
    }

    /// Wispr Flow's bundle id, as `NSRunningApplication` lists it.
    static let bundleID = "com.electron.wispr-flow"

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
