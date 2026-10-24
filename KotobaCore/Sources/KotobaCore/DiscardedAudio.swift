import Foundation

// A capture's files after it: the upload copies, and the recordings discarded by Esc or a failed press. Out of
// AudioCapture.swift, which holds the capture's lifecycle.

extension AudioCapture {
    /// A capture's files: `file`, and its upload copy of the same name in the copies' folder.
    func files(for file: URL) -> CaptureFiles {
        CaptureFiles(
            recording: file, upload: uploads.appending(path: file.deletingPathExtension().lastPathComponent + ".ogg"))
    }

    /// Deletes an upload copy nothing sends any more; one that stays goes at the next launch.
    nonisolated static func removeUploadCopy(_ upload: URL?) {
        guard let upload else { return }
        do {
            try FileManager.default.removeItem(at: upload)
        } catch {
            Log.audio.error("Cannot delete an upload copy: \(error)")
        }
    }

    nonisolated static func removeUploadCopies(in folder: URL) {
        let copies = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for copy in copies { removeUploadCopy(copy) }
    }

    @discardableResult
    public func discardCapture() async -> Bool {
        guard let audio = await cancelCapture() else { return true }
        return await discard(audio)
    }

    @discardableResult
    public func discard(_ audio: RecordedAudio) async -> Bool {
        // The copy goes too; the result is the recording's own, as only the FLAC can be sent again.
        Self.removeUploadCopy(audio.upload)
        do {
            try FileManager.default.removeItem(at: audio.file)
            return true
        } catch {
            Log.audio.error("Cannot delete discarded audio: \(error)")
            return false
        }
    }
}
