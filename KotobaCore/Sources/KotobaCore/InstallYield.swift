/// A development build beside the release app (App/Install.swift). Both hear a modifier-only chord, because the
/// hotkey tap never swallows a modifier, so both would record, upload and paste the same speech. The development
/// build gives way: its hotkeys are off while any release instance runs, and on again when the last one quits. A
/// click on its recording pill still stops its own recording. The release never gives way.
public struct InstallYield: Sendable, Equatable {
    public let isRelease: Bool
    /// The process ids of the release instances now running.
    private var releaseProcesses: Set<Int32> = []

    public init(isRelease: Bool) {
        self.isRelease = isRelease
    }

    public var isYielding: Bool { !isRelease && !releaseProcesses.isEmpty }

    /// Whether the menu says the build gives way in `state`. A live dictation's own text comes first; an outcome (an
    /// error, Copied) is past, and the next chord goes to the release app.
    public func showsYield(in state: DictationState) -> Bool {
        guard isYielding else { return false }
        switch state {
        case .recording, .transcribing, .cleaning, .undoable, .polishing:
            return false
        case .idle, .failed, .timedOut, .needsSetup, .rejected, .cleanupFailed, .cleanupTooSlow, .returnSkipped, .copied,
            .recovered, .captureFailed, .nothingRecorded, .audioNotSaved, .audioCut, .clipboardNotKept, .polished,
            .polishFailed:
            return true
        }
    }

    /// Release instances quit and launched, in one change of the running apps. Returns true when `isYielding` changed,
    /// so a list that names a running instance again, or an unknown one as quit, changes nothing.
    public mutating func releaseChanged(launched: some Sequence<Int32>, quit: some Sequence<Int32>) -> Bool {
        let wasYielding = isYielding
        releaseProcesses.subtract(quit)
        releaseProcesses.formUnion(launched)
        return isYielding != wasYielding
    }
}
