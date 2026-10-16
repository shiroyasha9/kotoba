import Foundation

/// When a pane of the main window reads what it shows from the stores (`App/PaneReader.swift`): only while the pane is
/// shown, when it appears, after each write the pane's owner reports while it shows, and when the owner asks to try
/// again. A hidden pane reads nothing; it reads when it appears. A write during a read asks for one more read after
/// it, so a burst of writes costs at most two reads.
@MainActor
public final class PaneReads<Value> {
    private let read: @MainActor () async throws -> Value
    private let deliver: @MainActor (Result<Value, any Error>) -> Void
    private var reading: Task<Void, Never>?
    private var isReadDue = false
    private var isShown = false

    /// `deliver` gets the result of each read that `hide()` did not cancel.
    public init(
        read: @escaping @MainActor () async throws -> Value,
        deliver: @escaping @MainActor (Result<Value, any Error>) -> Void
    ) {
        self.read = read
        self.deliver = deliver
    }

    /// The pane appeared, or the owner asked to try again.
    public func show() {
        isShown = true
        reload()
    }

    public func hide() {
        isShown = false
        reading?.cancel()
        reading = nil
    }

    /// A store write, or the day changed: a shown pane reads again.
    public func changed() {
        guard isShown else { return }
        reload()
    }

    private func reload() {
        guard reading == nil else {
            isReadDue = true
            return
        }
        reading = Task {
            repeat {
                isReadDue = false
                let result: Result<Value, any Error>
                do {
                    result = .success(try await read())
                } catch {
                    result = .failure(error)
                }
                // `hide()` cancelled it; a newer read may already be running.
                guard !Task.isCancelled else { return }
                deliver(result)
            } while isReadDue && !Task.isCancelled
            // A cancelled read was already replaced by `hide()`, maybe by a newer one: leave that handle alone.
            if !Task.isCancelled { reading = nil }
        }
    }
}
