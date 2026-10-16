import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// History's "Transcribe Again" reads a row with text, latency marks included.
extension HistoryStoreTests {
    @Test func aTranscribedRecordComesBackWithItsLatencyAndOnlyWhileItHasText() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        var recovered = record(.recovered)
        recovered.transcript = "Run the migration."
        recovered.recoveredAt = Date(timeIntervalSince1970: 1_800_000_500)
        let failed = record(.failed)
        try await store.save(recovered)
        try await store.save(failed)

        #expect(try await store.transcribedRecord(recovered.id) == recovered)
        #expect(try await store.transcribedRecord(failed.id) == nil)
        #expect(try await store.transcribedRecord(DictationID()) == nil)
    }
}
