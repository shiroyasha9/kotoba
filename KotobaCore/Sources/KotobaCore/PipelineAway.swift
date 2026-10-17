import Foundation

/// Why the owner is away from the Mac, as the system reports it.
public enum Absence: Sendable, Hashable {
    case screenLocked
    case asleep
    /// Fast user switching: another user has the screen.
    case sessionInactive
}

// MARK: - The owner is away

extension DictationPipeline {
    /// The screen locked, the Mac is going to sleep, or another user took the session. A live recording stops as at
    /// a stop tap, so what it recorded is transcribed and kept, never lost (lead, 2026-10-17); a recording never stops
    /// on its own otherwise. Until every absence ends, no text pastes: Cmd-V would go to the lock screen, so the text
    /// waits on the clipboard ("Copied").
    public func absenceBegan(_ absence: Absence) {
        absences.insert(absence)
        guard let recording else { return }
        Log.pipeline.info("The owner is away: the recording stops and its text will wait on the clipboard")
        stop(recording, at: ports.clock.now)
    }

    public func absenceEnded(_ absence: Absence) {
        absences.remove(absence)
    }

    /// No absence is open: a transcript may paste.
    var isPresent: Bool { absences.isEmpty }
}
