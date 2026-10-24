import Foundation
import KotobaCore

/// The History pane's reads: pages newest first, a search, and one changed row.
extension HistoryStore {
    /// One page of the History pane, newest first: the rows after `last` (the previous page's last row) whose texts
    /// (transcript, cleaned, polished) or app name contain `search` (case-insensitive for ASCII letters); an empty `search` matches every row.
    /// A search that matches nothing scans every row: about 3 ms on 10,000 rows (debug build, `make timing`), so
    /// the history needs no FTS index. A page is about 1 ms.
    public func page(matching search: String = "", after last: DictationRecord? = nil, limit: Int) throws
        -> [DictationRecord]
    {
        var conditions: [String] = []
        var values: [Value] = [.integer(Int64(limit))]
        if let match = Self.match(search, parameter: 2) {
            conditions.append(match.condition)
            values.append(match.pattern)
        }
        if let last {
            values += [.real(last.createdAt.timeIntervalSince1970), .text(last.id.rawValue.uuidString)]
            conditions.append("(created_at, id) < (?\(values.count - 1), ?\(values.count))")
        }
        let filter = conditions.isEmpty ? "1" : conditions.joined(separator: " AND ")
        return try records(
            where: "\(filter) ORDER BY created_at DESC, id DESC LIMIT ?1", values, withLatency: false)
    }

    /// One row, without latency marks, when it exists and matches `search` as in `page`: an open History pane reads
    /// the dictation a change names.
    public func record(_ id: DictationID, matching search: String = "") throws -> DictationRecord? {
        var condition = "id = ?1"
        var values: [Value] = [.text(id.rawValue.uuidString)]
        if let match = Self.match(search, parameter: 2) {
            condition += " AND " + match.condition
            values.append(match.pattern)
        }
        return try records(where: condition, values, withLatency: false).first
    }

    /// The condition that `search` is in the text or app name, with its LIKE pattern bound as `?parameter`; nil for an
    /// empty search.
    private static func match(_ search: String, parameter: Int) -> (condition: String, pattern: Value)? {
        guard !search.isEmpty else { return nil }
        let like = "LIKE ?\(parameter) ESCAPE '\\'"
        return (
            "(polished_text \(like) OR cleaned_text \(like) OR transcript \(like) OR app_name \(like))",
            .text("%" + escapedForLike(search) + "%")
        )
    }

    /// `\`, `%` and `_` match only themselves in a LIKE pattern with `ESCAPE '\'`.
    private static func escapedForLike(_ text: String) -> String {
        text.replacing("\\", with: "\\\\").replacing("%", with: "\\%").replacing("_", with: "\\_")
    }
}
