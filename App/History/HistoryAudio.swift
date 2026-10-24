import AVFAudio
import AppKit
import KotobaCore
import Observation

/// Plays one dictation's saved audio for the History page. The player is made at Play and dropped when the audio ends
/// or stops, so nothing is held between plays. Capture loads AVFAudio at launch, so playback loads no framework.
@MainActor
@Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    /// The dictation whose audio plays; nil when none does.
    private(set) var playing: DictationID?
    @ObservationIgnored private var player: AVAudioPlayer?

    /// `playing` is for snapshots: it shows as playing, with no player.
    init(playing: DictationID? = nil) {
        self.playing = playing
    }

    /// Plays `record`'s audio from the start, after stopping any other.
    func play(_ record: DictationRecord) {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: record.audio.file)
            player.delegate = self
            guard player.play() else { return }
            self.player = player
            playing = record.id
        } catch {
            Log.app.error("Cannot play the audio of \(record.id.rawValue): \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.ended() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in self.ended() }
    }

    /// A player ended. A late end of an earlier player finds the newer one still playing, and leaves it.
    private func ended() {
        guard player?.isPlaying == false else { return }
        stop()
    }
}

extension HistoryModel {
    /// The one selected row whose audio is kept; nil for none or several.
    func audioRecord(_ records: [DictationRecord]) -> DictationRecord? {
        guard records.count == 1, let record = records.first, record.isAudioKept else { return nil }
        return record
    }

    /// While no dictation records or is sent: the speakers would reach the mic.
    func canPlay(_ records: [DictationRecord]) -> Bool {
        activity.isQuiet && audioRecord(records) != nil
    }

    func isPlaying(_ records: [DictationRecord]) -> Bool {
        records.count == 1 && records.first?.id == playback.playing
    }

    /// Plays the row's audio, or stops it when it plays.
    func togglePlay(_ records: [DictationRecord]) {
        if isPlaying(records) {
            playback.stop()
        } else if canPlay(records), let record = audioRecord(records) {
            playback.play(record)
        }
    }

    /// The audio file selected in a Finder window.
    func showInFinder(_ records: [DictationRecord]) {
        guard let record = audioRecord(records) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([record.audio.file])
    }
}
