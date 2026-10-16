import AVFAudio
import Foundation
import KotobaCore
import KotobaStorage
import os

/// The launch's recovery of audio files with no History row (`OrphanAudio`): one listing of the audio folder (names and
/// creation dates only), one query for the ids that have rows and one for the discarded ids, and an `AVAudioFile` read
/// of each orphan only. The rows are saved before the launch retry, which transcribes them into Recovered. The files of
/// discarded recordings are removed, never read.
enum OrphanAudioRecovery {
    /// Apple's FLAC encoder writes blocks of 4,608 samples (spike `spikes/flac-kill`).
    private static let blockSize: AVAudioFrameCount = 4_608
    /// The rewrite cannot start: the file stays as it is.
    private struct UnreadableAudio: Error {
        let reason: String
    }

    /// Off the main actor. The rows go to the store directly: at launch no window shows the history yet, and the menu
    /// reads its counts after the retry (`AppDelegate.refreshQueues`).
    @concurrent
    static func run(in folder: URL, store: HistoryStore, launchedAt: Date) async {
        let started = ContinuousClock.now
        let files: [OrphanAudio.File]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
            ).compactMap { url in
                // A file removed since the listing has no date: there is nothing to recover.
                (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate).map {
                    OrphanAudio.File(url: url, createdAt: $0)
                }
            }
        } catch CocoaError.fileReadNoSuchFile {
            // No dictation yet: the folder is made by the first recording.
            return
        } catch {
            Log.app.error("Cannot list the audio folder: \(error)")
            return
        }
        let known: Set<DictationID>
        let discarded: Set<DictationID>
        do {
            known = try await store.knownIDs(among: files.compactMap { OrphanAudio.id(of: $0.url) })
            discarded = try await store.discardedIDs()
        } catch {
            Log.app.error("Cannot read the dictation ids: \(error)")
            return
        }
        await removeDiscarded(files: files, discardedIDs: discarded, store: store)
        let orphans = OrphanAudio.records(
            files: files, knownIDs: known, discardedIDs: discarded, launchedAt: launchedAt, length: repairedLength(of:))
        for orphan in orphans {
            do {
                try await store.save(orphan)
            } catch {
                // The next launch finds the file again.
                Log.app.error(
                    "Cannot save orphan audio \(orphan.audio.file.lastPathComponent, privacy: .public): \(error)")
            }
        }
        let took = ContinuousClock.now - started
        Log.app.info("Orphan audio: \(orphans.count) of \(files.count) files, \(took, privacy: .public)")
    }

    /// Removes what the discards could not, and forgets each discard whose file is gone. A file that still cannot be
    /// removed stays remembered, so it is never taken for an orphan.
    private static func removeDiscarded(files: [OrphanAudio.File], discardedIDs: Set<DictationID>, store: HistoryStore)
        async
    {
        guard !discardedIDs.isEmpty else { return }
        let leftovers = OrphanAudio.discardedFiles(files: files, discardedIDs: discardedIDs)
        let gone = discardedIDs.filter { id in leftovers[id].map(HistoryStore.removeAudio(at:)) ?? true }
        do {
            try await store.forgetDiscarded(gone)
        } catch {
            // The next launch finds the ids again; their files are gone, so it only forgets them.
            Log.app.error("Cannot forget discarded audio: \(error)")
        }
    }

    /// An orphan's audio length, after it is made readable. A recording that never closed (a crash, a force quit) has
    /// its frames on disk but a zeroed STREAMINFO (`OrphanAudio.isUnfinished`): AVAudioFile, flac and ffmpeg refuse it,
    /// and so does the speech model. Its frames go to a closed FLAC that replaces it: the same samples, in the file a
    /// stop writes. Any other file reads as it is. Nil when it has no audio; the file then stays as it is.
    static func repairedLength(of file: URL) -> Duration? {
        do {
            if try OrphanAudio.isUnfinished(header: header(of: file)) {
                let frames = try rewrite(file)
                return frames > 0 ? CaptureWriter.duration(ofFrames: frames) : nil
            }
            let audio = try AVAudioFile(forReading: file)
            return audio.length > 0 ? .seconds(Double(audio.length) / audio.fileFormat.sampleRate) : nil
        } catch {
            Log.app.error("Cannot read orphan audio \(file.lastPathComponent, privacy: .public): \(error)")
            return nil
        }
    }

    private static func header(of file: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }  // Read only: a failed close loses nothing.
        return try handle.read(upToCount: OrphanAudio.flacHeaderSize) ?? Data()
    }

    /// Reads the frames through a copy with the STREAMINFO the capture format fixes, writes them to a new closed FLAC,
    /// and replaces the file with it. Returns the frame count. The work files are in a folder
    /// the system gives for a replacement on the same volume, never in the audio folder.
    private static func rewrite(_ file: URL) throws -> AVAudioFramePosition {
        let work = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: file, create: true)
        // The system clears its replacement folders too; a leftover holds only a copy.
        defer { try? FileManager.default.removeItem(at: work) }
        // A clone on APFS: the frames are not copied, and only the 38 STREAMINFO bytes are written.
        let patched = work.appending(path: "patched.flac")
        try FileManager.default.copyItem(at: file, to: patched)
        let handle = try FileHandle(forUpdating: patched)
        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: streamInfo)
        try handle.close()

        let source = try AVAudioFile(forReading: patched, commonFormat: .pcmFormatInt16, interleaved: true)
        let target = work.appending(path: file.lastPathComponent)
        let output = try CaptureWriter.makeFile(at: target)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4 * blockSize) else {
            throw UnreadableAudio(reason: "no buffer for \(source.processingFormat)")
        }
        var frames: AVAudioFramePosition = 0
        while true {
            do {
                try source.read(into: buffer)
            } catch {
                // A read past the last frame fails, with no error code to tell it from another failure. The decoder
                // skips a damaged frame and reads on, and drops a last frame the crash cut off (spike), so a failed
                // read is the end of the frames on disk.
                break
            }
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
            frames += AVAudioFramePosition(buffer.frameLength)
        }
        output.close()
        guard frames > 0 else { return 0 }
        _ = try FileManager.default.replaceItemAt(file, withItemAt: target)
        return frames
    }

    private static var streamInfo: Data {
        let format = CaptureWriter.outputFormat
        return OrphanAudio.streamInfo(
            sampleRate: Int(format.sampleRate), channels: Int(format.channelCount),
            bitsPerSample: Int(format.streamDescription.pointee.mBitsPerChannel), blockSize: Int(blockSize))
    }
}
