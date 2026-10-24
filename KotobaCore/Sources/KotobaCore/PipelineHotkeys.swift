import Foundation

// MARK: - Hotkey events

extension DictationPipeline {
    /// A press of any chord stops a running recording, whichever chord started it, so the owner is never stuck with the
    /// mic on. In the Undo window a press waits for its release (`UndoWindow`).
    func chordDown(_ gesture: ChordGesture, at now: Instant) async {
        isChordDown = true
        press += 1
        let tapEnd = droppedTapEnd
        droppedTapEnd = nil
        if paused != nil {
            paused?.pressBegan(at: now, gesture: gesture)
        } else if let recording {
            stop(recording, at: now)
        } else if gesture == .hold, let tapEnd, now - tapEnd <= settings.doubleTapGap {
            await start(.toggle, at: now)
        } else {
            await start(gesture, at: now)
        }
    }

    /// Counts only before the announcement, as `cleanupModifier` does: the press that starts a dictation decides how
    /// its release ends.
    func gestureChanged(_ gesture: ChordGesture) {
        paused?.pressChanged(to: gesture)
        guard let current = recording, current.isUndecided, !current.isAnnounced else { return }
        recording?.gesture = gesture
    }

    func chordUp(at now: Instant) async {
        isChordDown = false
        releaseWaiters.resumeAll()
        if paused?.isPressing == true {
            if paused?.pressEnded(at: now, threshold: settings.tapThreshold) == true {
                await resume(at: now)
            }
            return
        }
        guard let current = recording, current.isUndecided else { return }
        recording?.isUndecided = false
        let isTap = now - current.startedAt < settings.tapThreshold
        switch (current.gesture, isTap) {
        case (.tapOrHold, true), (.toggle, true):
            // A release handled after the threshold passed: announced as push to talk, it runs hands-free.
            if current.isAnnounced {
                recordingModeChanged()
            } else {
                await announce(current.id, at: now)
            }
        case (.toggle, false):
            // Announced at the threshold; it runs until the next press.
            break
        case (.tapOrHold, false), (.hold, false):
            stop(current, at: now)
        case (.hold, true) where current.isAnnounced:
            // A release handled after the threshold announced the press: the cue played and the pill showed, so the
            // release stops it as push to talk. It is no dropped tap and starts no double tap.
            stop(current, at: now)
        case (.hold, true):
            // Too short for push to talk: dropped as a shortcut press is, with no cue and nothing kept. A push-to-talk
            // press soon after it makes a double tap.
            droppedTapEnd = now
            await discard(current)
        }
    }

    /// Counts only before the announcement, so the press that starts a dictation decides its mode.
    func cleanupModifier() {
        guard let current = recording, !current.isAnnounced, !current.isCleanupSeen else { return }
        recording?.isCleanupSeen = true
        if !current.isCleanerWarm {
            recording?.isCleanerWarm = warmCleaner()
        }
    }

    func chordInterrupted() async {
        if paused?.isPressing == true {
            paused?.pressInterrupted()
            return
        }
        // Only the press that started this recording, before its cue, is a shortcut; a later key is typing.
        if let recording, recording.isUndecided, !recording.isAnnounced {
            await discard(recording)
        }
    }
}
