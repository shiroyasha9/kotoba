import Foundation
import Testing

@testable import KotobaCore

/// Which dictations have text for Copy, Paste Again and Fix.
struct DictationRecordTextTests {
    func record(transcript: String?, cleaned: String? = nil) -> DictationRecord {
        var record = DictationRecord(
            id: DictationID(), createdAt: Date(timeIntervalSince1970: 0),
            audio: RecordedAudio(file: URL(filePath: "/tmp/a.flac"), duration: .seconds(1)), transcript: transcript,
            status: .pasted, latency: LatencyLog())
        record.cleanedText = cleaned
        return record
    }

    @Test func aDictationWithWordsHasText() {
        #expect(record(transcript: "Ship it.").hasText)
        #expect(record(transcript: "ship it", cleaned: "Ship it.").hasText)
    }

    @Test func aDictationWithNoTextOrAnEmptyOneHasNone() {
        #expect(!record(transcript: nil).hasText)
        #expect(!record(transcript: "").hasText)
        #expect(!record(transcript: "ship it", cleaned: "").hasText)
    }
}
