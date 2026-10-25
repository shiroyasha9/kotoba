import KotobaCore
import SwiftUI

/// kotoba's hello (owner QA 3, S2): the icon, the welcome and what kotoba is good at, in three rows (four when Wispr
/// Flow is on this Mac), centred in the window as Apple's first-run screens. The ways to dictate and their keys are on
/// Try It, where the owner uses them; Welcome still takes Wispr Flow's shortcuts as it shows (owner QA 2, R1).
struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
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
                hasImportedShortcuts: !model.wisprShortcutRoles.isEmpty, offersDictionary: model.offersWisprImport)
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
