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
    public func absenceBegan(_ absence: Absence) async {
        absences.insert(absence)
        // A paste waiting for a release that the lock may swallow ends its wait now and copies.
        releaseWaiters.resumeAll()
        let now = ports.clock.now
        // After a capture start or an Undo's resume on its way, so that recording stops too.
        await inTurn {
            // Quit keeps a live recording for the next launch, and sends nothing new.
            guard !isQuitting, let recording else { return }
            Log.pipeline.info("The owner is away: the recording stops and its text will wait on the clipboard")
            stop(recording, at: now)
        }
    }

    public func absenceEnded(_ absence: Absence) {
        absences.remove(absence)
    }

    /// No absence is open: a transcript may paste.
    var isPresent: Bool { absences.isEmpty }
}
