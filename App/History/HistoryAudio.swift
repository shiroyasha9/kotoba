import AVFAudio
import AppKit
import KotobaCore
import Observation

/// Plays one dictation's saved audio for the History pane. The player is made at Play and dropped when the audio ends
/// or stops, so nothing is held between plays. Capture loads AVFAudio at launch, so playback loads no framework.
@MainActor
@Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    /// The dictation whose audio plays; nil when none does.
    private(set) var playing: DictationID?
    @ObservationIgnored private var player: AVAudioPlayer?

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

    /// For snapshots: `id` shows as playing, with no player.
    func showAsPlaying(_ id: DictationID) {
        playing = id
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            // A Play of another row since then made a new player, which keeps playing.
            guard let current = self.player, ObjectIdentifier(current) == finished else { return }
            self.stop()
        }
    }
}

extension HistoryModel {
    /// One row whose audio is kept, while no dictation records or is sent: the speakers would reach the mic.
    func canPlay(_ records: [DictationRecord]) -> Bool {
        activity.isQuiet && records.count == 1 && records.first.map(Self.hasAudio) == true
    }

    /// The audio file is kept: the dictation has audio and retention did not delete it.
    static func hasAudio(_ record: DictationRecord) -> Bool {
        record.audio.hasAudio && !record.isAudioDeleted
    }

    func isPlaying(_ records: [DictationRecord]) -> Bool {
        records.count == 1 && records.first?.id == playback.playing
    }

    /// Plays the row's audio, or stops it when it plays.
    func togglePlay(_ records: [DictationRecord]) {
        if isPlaying(records) {
            playback.stop()
        } else if canPlay(records), let record = records.first {
            playback.play(record)
        }
    }

    /// The audio file selected in a Finder window.
    func showInFinder(_ records: [DictationRecord]) {
        guard records.count == 1, let record = records.first, Self.hasAudio(record) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([record.audio.file])
    }
}
