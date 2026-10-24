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

        /// The number of an `.integer` value; nil for any other.
        var integer: Int64? {
            if case .integer(let number) = self { number } else { nil }
        }

        /// The time of a `.real` value in seconds since 1970; nil for any other.
        var date: Date? {
            if case .real(let seconds) = self { Date(timeIntervalSince1970: seconds) } else { nil }
        }
    }

    /// SQLITE_TRANSIENT: SQLite copies bound text before the call returns.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// What one finished statement cost SQLite (`sqlite3_stmt_status`): counts of work that load on the machine does
    /// not change, so a test can check that a read on a large history uses its index instead of timing it.
    struct StatementCost: Equatable, Sendable {
        var sql: String
        /// Steps through a whole table or index with no index constraint (SQLITE_STMTSTATUS_FULLSCAN_STEP): one per row
        /// a scan visits, until a LIMIT stops it.
        var scanSteps: Int
        /// Sorts SQLite did because no index gave the order (SQLITE_STMTSTATUS_SORT).
        var sorts: Int
        /// Steps of SQLite's virtual machine (SQLITE_STMTSTATUS_VM_STEP): all the statement's work, a constant number for
        /// each row it visits, whether a scan or an index found the row.
        var steps: Int

        init(_ statement: OpaquePointer) {
            sql = sqlite3_sql(statement).map { String(cString: $0) } ?? ""
            scanSteps = Int(sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_FULLSCAN_STEP, 0))
            sorts = Int(sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_SORT, 0))
            steps = Int(sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_VM_STEP, 0))
        }
    }

    /// The costs kept between `startCounting` and `stopCounting`; the trace callback reaches it through its context.
    private final class CostLog {
        var costs: [StatementCost] = []
    }

    private let handle: OpaquePointer
    private var costLog: CostLog?

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

    /// Keeps the cost of each statement that finishes on this connection until `stopCounting()`, for tests. Off
    /// otherwise: the app never sets the trace, so a statement pays nothing for it.
    func startCounting() {
        precondition(costLog == nil, "startCounting while counting: stopCounting first")
        let log = CostLog()
        costLog = log
        sqlite3_trace_v2(
            handle, UInt32(SQLITE_TRACE_PROFILE),
            { _, context, statement, _ in
                guard let context, let statement else { return 0 }
                let log = Unmanaged<CostLog>.fromOpaque(context).takeUnretainedValue()
                log.costs.append(StatementCost(OpaquePointer(statement)))
                return 0
            }, Unmanaged.passUnretained(log).toOpaque())
    }

    /// The cost of each statement since `startCounting()`, in order; the trace is off again.
    func stopCounting() -> [StatementCost] {
        sqlite3_trace_v2(handle, 0, nil, nil)
        defer { costLog = nil }
        return costLog?.costs ?? []
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

/// The store's side of `SQLiteDatabase.startCounting`, for tests that check what a read on a large history costs.
extension HistoryStore {
    func startCounting() {
        database.startCounting()
    }

    func stopCounting() -> [SQLiteDatabase.StatementCost] {
        database.stopCounting()
    }
}
