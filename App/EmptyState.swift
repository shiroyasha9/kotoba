import KotobaCore
import SwiftUI

/// What a list or pane shows when it has nothing to show: `ContentUnavailableView`, centred in all the space its
/// container gives it, so empty states look and sit alike (owner, 2026-10-16: a state sized to its text sat left of its
/// box's centre). A card on a page with other cards (Home's last dictation, Activity's figures) is an `EmptyRow`
/// instead: the same title, symbol and words, in a row (qa1-review 8).
struct EmptyState<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: String
    @ViewBuilder let actions: Actions

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Actions == EmptyView {
    init(_ title: String, systemImage: String, description: String) {
        self.init(title: title, systemImage: systemImage, description: description) { EmptyView() }
    }
}

/// A card's empty state on a page with other cards: one row with `EmptyState`'s title (Title Case, as
/// `ContentUnavailableView`'s), its symbol in a grey tile and its description, and the action that fills it, if any.
/// Home and Activity show it in place of their dictations, where History shows the `EmptyState` across its list, so a
/// new install reads one way on all three (qa1-review 8).
struct EmptyRow<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: String
    @ViewBuilder let actions: Actions

    var body: some View {
        PageRow(title: title, subtitle: description) {
            SymbolTile(systemImage: systemImage, tint: .gray, side: PageMetrics.rowTileSide)
        } trailing: {
            actions
        }
    }
}

extension EmptyRow where Actions == EmptyView {
    init(_ title: String, systemImage: String, description: String) {
        self.init(title: title, systemImage: systemImage, description: description) { EmptyView() }
    }
}

extension StatusText {
    /// The empty state of every page that lists dictations (Home, History, Activity), in one place so they cannot drift.
    static let noDictationsTitle = "No Dictations Yet"
}
