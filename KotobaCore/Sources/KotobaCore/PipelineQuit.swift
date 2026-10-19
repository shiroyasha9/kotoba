import Foundation

// MARK: - Quit

extension DictationPipeline {
    /// Quit: a live recording is saved `.pending` (transcribed at the next launch, into Recovered),
    /// and a recording in its Undo window is saved `.cancelled`. Nothing is lost. A dictation being sent gets up to
    /// `quitWait` for its answer, so its billed text is saved and the next launch does not send it again; one that
    /// takes longer stays `.pending`; a retry send, Polish, Transcribe Again and every billed answer on its way (a
    /// primer, unused segments, a late cleanup: `PendingWork.bill`) get the same wait, so their cost reaches the usage
    /// ledger, and a paste that went out gets its restore. All share one bound.
    /// From the start nothing new is sent (a send now could be billed now and again at the next launch), recorded or
    /// pasted: the paste of an answer that comes during the wait would return before its restore.
    public func shutdown() async {
        live.beginQuit()
        retryTimer?.cancel()
        retryTimer = nil
        // A paste waiting for a chord release saves its text instead.
        releaseWaiters.resumeAll()
        let deadline = ports.clock.now + Self.quitWait
        // After a capture start or an Undo's resume on its way, so quit keeps that recording; one that does not end
        // within the bound (a stuck mic) is left, as quit must not hang.
        let isKept = await inTurn(by: deadline) {
            // A recording whose Undo window just ended keeps its row.
            while cancelSaves > 0 {
                await withCheckedContinuation { cancelSaveWaiters.add($0) }
            }
            if let current = paused {
                current.timer.cancel()
                await cancel(current.item)
            }
            if let current = recording {
                let latency = endRecording(current)
                await keep(current, audio: await endCapture(of: current), latency: latency, as: .pending)
            }
        }
        if !isKept {
            Log.pipeline.error("Quit: a capture start or resume did not end in time; its recording is not kept")
        }
        if !live.areSendsEnded {
            let bound = work.schedule(at: deadline) { await self.endQuitWait() }
            await withCheckedContinuation { live.wait(until: .sendsEnded, $0) }
            bound.cancel()
        }
        // Billed answers on their way beside the sends (primers, unused segments, late cleanups) reach the ledger.
        await work.billsEnded(by: deadline)
        // A paste that went out before quit began gets its restore, so the owner's clipboard comes back.
        await paste.waitUntilRestored(by: deadline)
    }

    /// Most dictations get their answer in about a second; quit must not hang on a slow route.
    static let quitWait = Duration.seconds(3)

    private func endQuitWait() {
        live.release(.sendsEnded)
    }
}
