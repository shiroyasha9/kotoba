import KotobaCore
import SwiftUI

/// What a list or pane shows when it has nothing to show: `ContentUnavailableView`, centred in all the space its
/// container gives it. Every empty state in kotoba's windows is one, so they look and sit alike (owner, 2026-10-16: a
/// state sized to its text sat left of its box's centre).
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

    /// History, and Home's newest dictations, before the first dictation.
    static func noDictations(chord: Chord) -> Self {
        EmptyState(
            "No Dictations Yet", systemImage: "waveform",
            description: "Tap \(chord.title) to dictate. Each dictation appears here.")
    }
}

extension EmptyState where Actions == Button<Text> {
    /// A pane whose read failed, with the button that reads again.
    static func loadFailed(retry: @escaping @MainActor () -> Void) -> Self {
        EmptyState(
            title: StatusText.historyReadFailedTitle, systemImage: "exclamationmark.triangle",
            description: StatusText.historyReadFailedMessage
        ) {
            Button("Try Again", action: retry)
        }
    }
}

/// A search with no results, centred like `EmptyState`.
struct NoSearchResults: View {
    let search: String

    var body: some View {
        ContentUnavailableView.search(text: search)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
