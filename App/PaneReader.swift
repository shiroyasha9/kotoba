import Foundation
import KotobaCore
import Observation
import SwiftUI

/// What a pane of the main window shows from the stores, read on the schedule of `PaneReads` (KotobaCore): only while
/// the pane is shown, and at most two reads for a burst of writes. Home, Insights and Usage read through one each.
@MainActor
@Observable
final class PaneReader<Value: Equatable> {
    private(set) var value: Value?
    private(set) var isLoadFailed = false

    /// Nil for snapshots, which set the value themselves.
    @ObservationIgnored private var reads: PaneReads<Value>?

    /// `name` is what the log names when a read fails ("insights").
    init(_ name: String, read: @escaping @MainActor () async throws -> Value) {
        reads = PaneReads(read: read) { [weak self] result in self?.take(result, name: name) }
    }

    /// For snapshots: a fixed value and no store.
    init(value: Value) {
        self.value = value
    }

    /// The pane appeared, or the owner asked to try again.
    func show() {
        reads?.show()
    }

    func hide() {
        reads?.hide()
    }

    /// A store write, or the day changed: a shown pane reads again.
    func changed() {
        reads?.changed()
    }

    private func take(_ result: Result<Value, any Error>, name: String) {
        switch result {
        case .success(let loaded):
            if isLoadFailed { isLoadFailed = false }
            // Most writes change nothing the pane shows: no redraw then.
            if loaded != value { value = loaded }
        case .failure(let error):
            Log.app.error("Cannot read \(name, privacy: .public): \(error)")
            isLoadFailed = true
        }
    }
}

extension View {
    /// The pane reads through `reader` while it is shown, and again when the day changes: today, streaks, months and
    /// charts move at midnight. The task ends when the pane goes.
    func reads<Value>(through reader: PaneReader<Value>) -> some View {
        onAppear(perform: reader.show)
            .onDisappear(perform: reader.hide)
            .task {
                for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                    reader.changed()
                }
            }
    }
}
