import Foundation
import SQLite3

public struct SQLiteError: Error, Sendable, Equatable {
    public var code: Int32
    public var message: String
}

/// One system SQLite connection, closed on deinit. It has no lock of its own: its owner (an actor, or one function
/// call) is its only user.
final class SQLiteDatabase {
    enum Value: Equatable, Sendable {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)

        /// `.text`, or `.null` for nil.
        static func nullable(_ text: String?) -> Self {
            text.map(Self.text) ?? .null
        }

        /// The text of a `.text` value; nil for any other.
        var string: String? {
            if case .text(let text) = self { text } else { nil }
        }
    }

    /// SQLITE_TRANSIENT: SQLite copies bound text before the call returns.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let handle: OpaquePointer

    init(url: URL, flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) throws(SQLiteError) {
        var handle: OpaquePointer?
        let code = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard code == SQLITE_OK, let handle else {
            sqlite3_close_v2(handle)
            throw SQLiteError(code: code, message: "open \(url.path)")
        }
        self.handle = handle
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one or more statements that take no values.
    func execute(_ sql: String) throws(SQLiteError) {
        var message: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &message)
        guard code == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(message)
            throw SQLiteError(code: code, message: text)
        }
    }

    func run(_ sql: String, _ values: [Value] = []) throws(SQLiteError) {
        _ = try query(sql, values)
    }

    func query(_ sql: String, _ values: [Value] = []) throws(SQLiteError) -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            Self.bind(value, at: Int32(index + 1), in: statement)
        }
        var rows: [[Value]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return rows }
            guard step == SQLITE_ROW else { throw lastError() }
            rows.append((0..<sqlite3_column_count(statement)).map { Self.column($0, of: statement) })
        }
    }

    /// Runs `body` in one write transaction; an error rolls it back.
    func transaction(_ body: () throws(SQLiteError) -> Void) throws(SQLiteError) {
        try execute("BEGIN IMMEDIATE;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")  // The original error is the one to report.
            throw error
        }
    }

    private static func bind(_ value: Value, at position: Int32, in statement: OpaquePointer) {
        switch value {
        case .null: sqlite3_bind_null(statement, position)
        case .integer(let number): sqlite3_bind_int64(statement, position, number)
        case .real(let number): sqlite3_bind_double(statement, position, number)
        case .text(let text): sqlite3_bind_text(statement, position, text, -1, transient)
        }
    }

    private static func column(_ column: Int32, of statement: OpaquePointer) -> Value {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER: .integer(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT: .real(sqlite3_column_double(statement, column))
        case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(statement, column)))
        default: .null
        }
    }

    private func lastError() -> SQLiteError {
        SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
    }
}
