import KotobaCore
import SwiftUI

/// What kotoba is good at, in three rows (four when Wispr Flow is on this Mac), and both ways to dictate with their keys
/// drawn as keycaps, each with Change… (owner QA 1, Q1). When Wispr Flow is on this Mac, Welcome took its shortcuts as
/// it showed (owner QA 2, R1): a line under each row whose chord is Wispr Flow's says so, and a footnote asks to quit
/// Wispr Flow while it runs on the same keys.
struct WelcomeStep: View {
    let model: OnboardingModel
    /// The way to dictate whose Change… sheet is open.
    @State private var changing: ChordRole?

    var body: some View {
        let chords = model.chords
        let wisprRoles = model.wisprShortcutRoles
        Section {
            Point(
                "Fast", systemImage: "bolt", tint: .green,
                text: "Pastes your words a second after you stop.")
            Point(
                "Accurate", page: .dictionary,
                text: "Learns your names and technical terms.")
            Point(
                "Private", systemImage: "hand.raised", tint: .blue,
                text: "Needs no kotoba account and sends no analytics.")
            // A reason to switch for a Wispr Flow user: what comes along, the shortcuts (taken here) and the dictionary
            // (imported on the last step).
            if let text = WisprFlowPoint.text(
                hasImportedShortcuts: !wisprRoles.isEmpty, offersDictionary: model.offersWisprImport)
            {
                Point(WisprFlowPoint.title, systemImage: "square.and.arrow.down", tint: .indigo, text: text)
            }
        } header: {
            StepHeading(
                title: "Welcome to kotoba",
                text: Text("Speak anywhere you can type."), isCentred: true
            ) {
                AppIconView(icon: NSApp.applicationIconImage, side: PageMetrics.welcomeIconSide)
            }
        }
        Section {
            shortcutRow(
                .handsFree, subtitle: StatusText.shortcutHelp(.handsFree), chord: chords.handsFree,
                isFromWispr: wisprRoles.contains(.handsFree))
            shortcutRow(
                .pushToTalk, subtitle: StatusText.pushToTalkHelp(chords), chord: chords.pushToTalk,
                isFromWispr: wisprRoles.contains(.pushToTalk))
        } footer: {
            // kotoba does not quit Wispr Flow: while it runs on a chord kotoba took, one press starts both apps.
            if model.isWisprRunning, !wisprRoles.isEmpty {
                Text(WisprFlowPoint.runningText)
            }
        }
        .sheet(isPresented: Binding(get: { changing != nil }, set: { if !$0 { changing = nil } })) {
            if let changing {
                ShortcutSheet(chords: chords, role: changing)
            }
        }
    }

    /// A way to dictate: its keycaps and Change… with the Shortcuts page's recorder, and under its subtitle the line
    /// that says its chord came from Wispr Flow.
    private func shortcutRow(_ role: ChordRole, subtitle: String, chord: Chord, isFromWispr: Bool) -> some View {
        PageRow(title: StatusText.shortcutTitle(role), subtitle: subtitle) {
            HStack {
                NamedKeycaps(keys: chord.keycaps)
                Button("Change…") { changing = role }
                    .accessibilityLabel("Change \(StatusText.shortcutTitle(role)) Shortcut")
            }
        } extra: {
            if isFromWispr {
                WisprFlowPoint.ImportedLine()
            }
        }
    }

    /// One selling point: a tile, a short title and one sentence, as a "What’s New" sheet shows a feature.
    private struct Point: View {
        let title: String
        let systemImage: String
        let tint: Color
        let text: String

        init(_ title: String, systemImage: String, tint: Color, text: String) {
            self.title = title
            self.systemImage = systemImage
            self.tint = tint
            self.text = text
        }

        /// A point about a page shows that page's sidebar tile.
        init(_ title: String, page: PaneID, text: String) {
            self.init(title, systemImage: page.systemImage, tint: page.tint, text: text)
        }

        var body: some View {
            PageRow(title: title, subtitle: text) {
                SymbolTile(systemImage: systemImage, tint: tint, side: PageMetrics.rowTileSide)
            } trailing: {
                EmptyView()
            }
        }
    }
}
