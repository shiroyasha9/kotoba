/// A recording that Esc cancelled, waiting for Undo, and the chord press (if any) during the
/// window. Only a clean tap resumes: a hold, or a press that became a shortcut, does not.
struct UndoWindow<Item> {
    let item: Item
    /// Ends the window when it fires; cancelled on resume.
    let timer: Task<Void, Never>
    private var pressStartedAt: ContinuousClock.Instant?
    private var isPressInterrupted = false

    init(item: Item, timer: Task<Void, Never>) {
        self.item = item
        self.timer = timer
    }

    var isPressing: Bool { pressStartedAt != nil }

    mutating func pressBegan(at instant: ContinuousClock.Instant) {
        pressStartedAt = instant
        isPressInterrupted = false
    }

    mutating func pressInterrupted() {
        isPressInterrupted = true
    }

    /// True when the press that ends here was a tap under `threshold` with no other key.
    mutating func pressEnded(at instant: ContinuousClock.Instant, threshold: Duration) -> Bool {
        defer { pressStartedAt = nil }
        guard let start = pressStartedAt else { return false }
        return !isPressInterrupted && instant - start < threshold
    }
}
