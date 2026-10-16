import Foundation
import Observation
import SwiftUI

/// What a pane of the main window shows from the stores, read only while the pane is shown: when it appears, after
/// each write the pane's owner reports while it shows, and when the owner asks to try again. A hidden pane reads
/// nothing; it reads when it appears. A write during a read asks for one more read after it, so a burst of writes
/// costs at most two reads. Home, Insights and Usage read through one each.
@MainActor
@Observable
final class PaneReader<Value: Equatable> {
    private(set) var value: Value?
    private(set) var isLoadFailed = false

    /// What the log names when a read fails ("insights").
    @ObservationIgnored private let name: String
    /// Nil for snapshots, which set the value themselves.
    @ObservationIgnored private let read: (@MainActor () async throws -> Value)?
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var isReadDue = false
    @ObservationIgnored private var isShown = false

    init(_ name: String, read: @escaping @MainActor () async throws -> Value) {
        self.name = name
        self.read = read
    }

    /// For snapshots: a fixed value and no store.
    init(value: Value) {
        name = ""
        read = nil
        self.value = value
    }

    /// The pane appeared, or the owner asked to try again.
    func show() {
        isShown = true
        reload()
    }

    func hide() {
        isShown = false
        reading?.cancel()
        reading = nil
    }

    /// A store write, or the day changed: a shown pane reads again.
    func changed() {
        guard isShown else { return }
        reload()
    }

    private func reload() {
        guard let read else { return }
        guard reading == nil else {
            isReadDue = true
            return
        }
        reading = Task {
            repeat {
                isReadDue = false
                do {
                    let loaded = try await read()
                    // `hide()` cancelled it; a newer read may already be running.
                    guard !Task.isCancelled else { return }
                    isLoadFailed = false
                    // Most writes change nothing the pane shows: no redraw then.
                    if loaded != value { value = loaded }
                } catch {
                    guard !Task.isCancelled else { return }
                    Log.app.error("Cannot read \(self.name, privacy: .public): \(error)")
                    isLoadFailed = true
                }
            } while isReadDue && !Task.isCancelled
            // A cancelled read was already replaced by `hide()`, maybe by a newer one: leave that handle alone.
            if !Task.isCancelled { reading = nil }
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
