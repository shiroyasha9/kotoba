import Foundation

/// Audio files with no History row. A crash, a force quit or a power loss during a recording leaves
/// `<id>.flac` with no row (the row is first saved at the stop), and so does a failed save. At launch each orphan gets
/// the row a quit gives a live recording (`DictationPipeline.shutdown`): `.pending`, so the launch retry transcribes it
/// into Recovered and nothing is pasted. A file with no readable audio gets a `.cancelled` row with no text and no
/// Retry, so the owner sees it in History and can delete it. kotoba never deletes an orphan by itself. A recording the
/// owner discarded is not an orphan: when its file stayed, the store remembers it (`Store.markDiscarded`), and the
/// launch removes the file instead (`discardedFiles`).
public enum OrphanAudio {
    /// One file of the audio folder, as a folder listing gives it, with no file opened.
    public struct File: Sendable, Equatable {
        public var url: URL
        public var createdAt: Date

        public init(url: URL, createdAt: Date) {
            self.url = url
            self.createdAt = createdAt
        }
    }

    /// The dictation whose audio the file is: its name is exactly that dictation's `audioFileName`. Nil for any other
    /// file.
    public static func id(of file: URL) -> DictationID? {
        guard let uuid = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { return nil }
        let id = DictationID(rawValue: uuid)
        return id.audioFileName == file.lastPathComponent ? id : nil
    }

    /// The rows for the orphans among `files`, oldest first. A file is an orphan when its name gives a dictation id
    /// (`id(of:)`), no row has that id (`knownIDs`), the owner did not discard it (`discardedIDs`), and it was created
    /// before `launchedAt`, so a recording that started after launch is never taken. `length` gives a file's audio
    /// length and runs for orphans only; it returns nil or zero when the file has no audio.
    public static func records(
        files: [File],
        knownIDs: Set<DictationID>,
        discardedIDs: Set<DictationID>,
        launchedAt: Date,
        length: (URL) -> Duration?
    ) -> [DictationRecord] {
        files.lazy
            .filter { $0.createdAt < launchedAt }
            .compactMap { file in id(of: file.url).map { (id: $0, file: file) } }
            .filter { !knownIDs.contains($0.id) && !discardedIDs.contains($0.id) }
            .sorted { $0.file.createdAt < $1.file.createdAt }
            .map { orphan in
                let duration = length(orphan.file.url) ?? .zero
                return DictationRecord(
                    id: orphan.id, createdAt: orphan.file.createdAt,
                    audio: RecordedAudio(file: orphan.file.url, duration: duration), transcript: nil,
                    status: duration > .zero ? .pending : .cancelled, latency: LatencyLog())
            }
    }

    /// The files among `files` of the discarded recordings that stayed (`discardedIDs`), by id: the launch removes
    /// them, as the discard meant to. A discarded id with no file here is gone, so the store can forget it.
    public static func discardedFiles(files: [File], discardedIDs: Set<DictationID>) -> [DictationID: URL] {
        guard !discardedIDs.isEmpty else { return [:] }
        return Dictionary(
            files.compactMap { file in
                id(of: file.url).flatMap { discardedIDs.contains($0) ? ($0, file.url) : nil }
            },
            uniquingKeysWith: { first, _ in first })
    }
}

extension OrphanAudio {
    /// "fLaC" and the STREAMINFO block with its block header: the bytes a FLAC file starts with.
    public static let flacHeaderSize = 42

    /// AVAudioFile writes the STREAMINFO block only at close, so a recording that never closed (a crash, a force quit)
    /// starts with "fLaC" and 38 zero bytes; its frames follow as in a closed file (spike `spikes/flac-kill`).
    public static func isUnfinished(header: Data) -> Bool {
        header.count == flacHeaderSize && header.starts(with: Data("fLaC".utf8))
            && header.dropFirst(4).allSatisfy { $0 == 0 }
    }

    /// The STREAMINFO block, block header included, that makes an unfinished recording readable: what the capture format
    /// fixes, and 0 for the frame sizes, total samples and MD5, which RFC 9639 reads as unknown. The block header says
    /// type 0, not the last block (a VORBIS_COMMENT block follows) and 34 bytes; then 20 bits sample rate, 3 bits
    /// channels - 1, 5 bits bits per sample - 1 and 36 bits total samples.
    public static func streamInfo(sampleRate: Int, channels: Int, bitsPerSample: Int, blockSize: Int) -> Data {
        var data = Data([0x00, 0x00, 0x00, 0x22])
        for _ in 0..<2 {
            data += [UInt8(blockSize >> 8 & 0xFF), UInt8(blockSize & 0xFF)]
        }
        data += Data(count: 6)
        let packed = UInt64(sampleRate) << 44 | UInt64(channels - 1) << 41 | UInt64(bitsPerSample - 1) << 36
        data += (0..<8).map { UInt8(packed >> (56 - 8 * $0) & 0xFF) }
        return data + Data(count: 16)
    }
}

extension DictationID {
    /// The name of the dictation's audio file in the audio folder (`DictationPipeline.Settings.audioDirectory`).
    public var audioFileName: String { "\(rawValue.uuidString).flac" }
}
