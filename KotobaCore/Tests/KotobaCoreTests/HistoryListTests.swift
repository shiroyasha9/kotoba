import Foundation
import Testing

@testable import KotobaCore

/// How the History pane's rows follow the store's changes.
struct HistoryListTests {
    func row(_ time: TimeInterval, _ status: DictationRecord.Status = .pasted) -> DictationRecord {
        DictationRecord(
            id: DictationID(), createdAt: Date(timeIntervalSince1970: time),
            audio: RecordedAudio(file: URL(filePath: "/tmp/\(time).flac"), duration: .seconds(1)),
            transcript: "words", status: status, latency: LatencyLog())
    }

    /// Three rows of a longer history: more pages follow.
    func firstPage() -> (HistoryList, [DictationRecord]) {
        let rows = [row(3_000), row(2_000), row(1_000, .failed)]
        var list = HistoryList()
        list.replace(with: rows, limit: 3)
        return (list, rows)
    }

    @Test func aChangedRowStaysInItsPlaceEvenAsTheLastShown() {
        var (list, rows) = firstPage()
        var retried = rows[2]
        retried.status = .recovered

        list.update(retried.id, to: retried)

        #expect(list.rows.map(\.id) == rows.map(\.id))
        #expect(list.rows.last?.status == .recovered)
    }

    @Test func deletedAudioChangesOnlyItsRowsInPlace() {
        var (list, rows) = firstPage()

        list.markAudioDeleted([rows[0].id, DictationID()])

        #expect(list.rows.map(\.id) == rows.map(\.id))
        #expect(list.rows.map(\.isAudioDeleted) == [true, false, false])
    }

    @Test func aNewRowGoesToItsPlace() {
        var (list, rows) = firstPage()
        let newest = row(4_000)
        let between = row(2_500)

        list.update(newest.id, to: newest)
        list.update(between.id, to: between)

        #expect(list.rows.map(\.id) == [newest.id, rows[0].id, between.id, rows[1].id, rows[2].id])
    }

    @Test func aRowOlderThanTheLastShownWaitsForItsPageUnlessThereIsNone() {
        var (list, _) = firstPage()
        let older = row(500)
        list.update(older.id, to: older)
        #expect(!list.rows.contains(older))

        list.append([], limit: 3)
        #expect(list.isComplete)
        list.update(older.id, to: older)
        #expect(list.rows.last == older)
    }

    @Test func rowsWithTheSameTimeFollowTheStoresOrder() {
        var list = HistoryList()
        list.replace(with: [], limit: 1)
        let first = row(1_000)
        let second = row(1_000)
        list.update(first.id, to: first)
        list.update(second.id, to: second)

        let byText = [first, second].sorted { $0.id.rawValue.uuidString > $1.id.rawValue.uuidString }
        #expect(list.rows.map(\.id) == byText.map(\.id))
    }

    @Test func aRowThatNoLongerMatchesTheSearchLeaves() {
        var (list, rows) = firstPage()

        list.update(rows[1].id, to: nil)

        #expect(list.rows.map(\.id) == [rows[0].id, rows[2].id])
    }

    @Test func aDeletedRowNeverComesBack() {
        var (list, rows) = firstPage()

        list.remove([rows[0].id])
        // A read that started before the delete, then a change for it.
        list.replace(with: rows, limit: 3)
        list.update(rows[0].id, to: rows[0])

        #expect(list.rows.map(\.id) == [rows[1].id, rows[2].id])
    }
}
