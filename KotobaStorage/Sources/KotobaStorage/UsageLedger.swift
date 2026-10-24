import Foundation
import KotobaCore

/// What kotoba cost and how much it was used between two dates, for the Activity page: summed from the usage ledger in
/// SQLite when the pane asks, never at idle. An answer counts in the period of its entry's time (a cleanup's is its
/// transcript's).
public struct UsageSummary: Sendable, Equatable {
    public struct AppWords: Sendable, Equatable {
        /// With the app's name at its newest answer.
        public var app: DictationApp
        public var words: Int

        public init(app: DictationApp, words: Int) {
            self.app = app
            self.words = words
        }
    }

    /// Dictations with a speech answer that had words.
    public var dictations: Int
    /// Words of the delivered texts (after cleanup when it ran), as History counts them.
    public var words: Int
    /// Audio sent to the speech models, retries included.
    public var audio: Duration
    /// Speech and cleanup, in US dollars.
    public var cost: Decimal
    /// Part of `cost` comes from list prices.
    public var isCostEstimated: Bool
    /// Answers with no known cost: `cost` leaves them out.
    public var unpricedAnswers: Int
    /// Most spend first.
    public var models: [ModelSpend]
    /// Most words first.
    public var apps: [AppWords]

    public init(
        dictations: Int = 0, words: Int = 0, audio: Duration = .zero, cost: Decimal = 0, isCostEstimated: Bool = false,
        unpricedAnswers: Int = 0, models: [ModelSpend] = [], apps: [AppWords] = []
    ) {
        self.dictations = dictations
        self.words = words
        self.audio = audio
        self.cost = cost
        self.isCostEstimated = isCostEstimated
        self.unpricedAnswers = unpricedAnswers
        self.models = models
        self.apps = apps
    }
}

/// One model's share of the spend.
public struct ModelSpend: Sendable, Equatable, Identifiable {
    public var kind: UsageEntry.Kind
    /// The stored model identifier: a `TranscriptionRoute` or `CleanupModel` raw value.
    public var model: String
    public var cost: Decimal
    /// Part of `cost` comes from the list price.
    public var isEstimated: Bool
    /// Answers of this model with no known cost: `cost` leaves them out.
    public var unpricedAnswers: Int

    public var id: String { "\(kind.rawValue) \(model)" }

    public init(
        _ kind: UsageEntry.Kind, model: String, cost: Decimal, isEstimated: Bool = false, unpricedAnswers: Int = 0
    ) {
        self.kind = kind
        self.model = model
        self.cost = cost
        self.isEstimated = isEstimated
        self.unpricedAnswers = unpricedAnswers
    }
}

extension HistoryStore {
    /// The answers that came at or after `start` and before `end`; `apps` caps the app list. Three range reads on the
    /// ledger's `time` index.
    public func usage(from start: Date, to end: Date, apps: Int = 5) throws -> UsageSummary {
        let range: [Value] = [.real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)]
        let inRange = "time >= ?1 AND time < ?2"
        let speech = "kind = '\(UsageEntry.Kind.speech.rawValue)'"
        let totals = try database.query(
            """
            SELECT count(DISTINCT CASE WHEN \(speech) AND spoken_words > 0 THEN dictation_id END),
                coalesce(sum(words), 0),
                coalesce(sum(CASE WHEN \(speech) THEN audio_ms END), 0),
                coalesce(sum(cost_nano_usd), 0), coalesce(max(cost_estimated), 0), count(*) - count(cost_nano_usd)
            FROM usage_ledger WHERE \(inRange);
            """, range)
        let models = try database.query(
            """
            SELECT kind, model, coalesce(sum(cost_nano_usd), 0), coalesce(max(cost_estimated), 0),
                count(*) - count(cost_nano_usd)
            FROM usage_ledger WHERE \(inRange) GROUP BY kind, model ORDER BY 3 DESC, 1 DESC, 2;
            """, range)
        let topApps = try topApps(from: start, to: end, limit: apps)
        guard let row = totals.first?.map({ Int($0.integer ?? 0) }) else { return UsageSummary() }
        return UsageSummary(
            dictations: row[0], words: row[1], audio: .milliseconds(row[2]), cost: Self.usd(nano: row[3]),
            isCostEstimated: row[4] == 1, unpricedAnswers: row[5],
            models: models.compactMap { row in
                guard let kind = row[0].string.flatMap(UsageEntry.Kind.init), let model = row[1].string else {
                    return nil
                }
                return ModelSpend(
                    kind, model: model, cost: Self.usd(nano: Int(row[2].integer ?? 0)),
                    isEstimated: row[3].integer == 1, unpricedAnswers: Int(row[4].integer ?? 0))
            },
            apps: topApps)
    }

    /// The apps that got words at or after `start`, most words first, at most `limit`: the Modes pane's Add menu. One
    /// range read on the ledger's `time` index, the same one `usage` runs for its app list.
    public func recentApps(since start: Date, limit: Int) throws -> [DictationApp] {
        try topApps(from: start, to: nil, limit: limit).map(\.app)
    }

    /// A nil bound is left out of the query: with no bound at all it scans the table, which costs less than a range
    /// over the whole `time` index (one row lookup per entry).
    func topApps(from start: Date?, to end: Date?, limit: Int) throws -> [UsageSummary.AppWords] {
        let bounds = [start.map { ("time >= ", $0) }, end.map { ("time < ", $0) }].compactMap(\.self)
        let range = bounds.indices.map { "\(bounds[$0].0)?\($0 + 2) AND " }.joined()
        // With one max() in the query, the bare `app_name` comes from the newest answer of each app.
        return try database.query(
            """
            SELECT app_bundle_id, app_name, sum(words) AS words, max(time) FROM usage_ledger
            WHERE \(range)app_bundle_id IS NOT NULL
            GROUP BY app_bundle_id ORDER BY words DESC, app_bundle_id LIMIT ?1;
            """,
            [.integer(Int64(limit))] + bounds.map { .real($0.1.timeIntervalSince1970) }
        ).compactMap { row in
            row[0].string.map {
                .init(app: DictationApp(bundleID: $0, name: row[1].string), words: Int(row[2].integer ?? 0))
            }
        }
    }
}

// MARK: - Ledger

extension HistoryStore {
    /// One row per billed answer. No foreign key to `dictations` and no text: deleting a dictation, pruning the
    /// history or removing audio never changes what kotoba cost. `words` is `UsageEntry.deliveredWords`.
    static let ledgerSchema = """
        CREATE TABLE IF NOT EXISTS usage_ledger (
            id TEXT PRIMARY KEY,
            time REAL NOT NULL,
            dictation_id TEXT,
            kind TEXT NOT NULL,
            model TEXT NOT NULL,
            audio_ms INTEGER NOT NULL,
            words INTEGER NOT NULL,
            spoken_words INTEGER NOT NULL DEFAULT 0,
            cost_nano_usd INTEGER,
            cost_estimated INTEGER,
            app_bundle_id TEXT,
            app_name TEXT
        );
        CREATE INDEX IF NOT EXISTS usage_ledger_time ON usage_ledger (time);
        """

    /// Billed answers with no row to write (`Store.addUsage`): a cleanup answer that came after its deadline.
    public func addUsage(_ entries: [UsageEntry]) throws {
        try database.transaction { () throws(SQLiteError) in try Self.addToLedger(entries, in: database) }
    }

    /// Each entry once: a record saved again with the same entries adds nothing. Costs are whole billionths of a
    /// dollar, so sums in SQLite are exact.
    static func addToLedger(_ entries: [UsageEntry], in database: SQLiteDatabase) throws(SQLiteError) {
        guard !entries.isEmpty else { return }
        let rows = Array(repeating: "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", count: entries.count)
            .joined(separator: ", ")
        try database.run(
            """
            INSERT OR IGNORE INTO usage_ledger (
                id, time, dictation_id, kind, model, audio_ms, words, spoken_words, cost_nano_usd, cost_estimated,
                app_bundle_id, app_name
            ) VALUES \(rows);
            """,
            entries.flatMap { entry -> [Value] in
                [
                    .text(entry.id.uuidString), .real(entry.time.timeIntervalSince1970),
                    .nullable(entry.dictation?.rawValue.uuidString), .text(entry.kind.rawValue), .text(entry.model),
                    .integer(Int64((entry.audio / .milliseconds(1)).rounded())), .integer(Int64(entry.deliveredWords)),
                    .integer(Int64(entry.spokenWords)),
                    entry.cost.map { .integer(nanoUSD($0.usd)) } ?? .null,
                    entry.cost.map { .integer($0.isEstimated ? 1 : 0) } ?? .null,
                    .nullable(entry.app?.bundleID), .nullable(entry.app?.name),
                ]
            })
    }

    /// Once per database (`user_version` 0 to 1), inside the migration's transaction: one ledger entry per kept
    /// answer of a history from before the ledger (v0.1.0 and later), dated when it came (the retry time of a
    /// recovered dictation, else its key-down). Those builds kept no costs, so the entries have none and the Activity page
    /// says so; a row with cleaned text also had a cleanup request, whose model was not kept.
    static func fillLedger(_ database: SQLiteDatabase) throws(SQLiteError) {
        guard try database.query("PRAGMA user_version;").first?.first?.integer == 0 else { return }
        let rows = try database.query(
            """
            SELECT id, coalesce(recovered_at, created_at), model, transcript, cleaned_text, app_bundle_id, app_name,
                audio_duration_ms
            FROM dictations WHERE model IS NOT NULL;
            """)
        let entries = rows.flatMap { row -> [UsageEntry] in
            guard let id = row[0].string.flatMap(UUID.init(uuidString:)), case .real(let time) = row[1],
                let model = row[2].string
            else { return [] }
            let dictation = DictationID(rawValue: id)
            let date = Date(timeIntervalSince1970: time)
            let app = row[5].string.map { DictationApp(bundleID: $0, name: row[6].string) }
            let spoken = row[3].string.map(DictationRecord.wordCount(of:)) ?? 0
            var entries = [
                UsageEntry(
                    time: date, dictation: dictation, kind: .speech, model: model,
                    audio: .milliseconds(row[7].integer ?? 0), deliveredWords: spoken, spokenWords: spoken, cost: nil,
                    app: app)
            ]
            if let cleaned = row[4].string.map(DictationRecord.wordCount(of:)) {
                entries.append(
                    UsageEntry(
                        time: date, dictation: dictation, kind: .cleanup, model: UsageEntry.unknownModel,
                        deliveredWords: cleaned - spoken, cost: nil, app: app))
            }
            return entries
        }
        // Batches stay under SQLite's limit of 32,766 bound values per statement.
        for start in stride(from: 0, to: entries.count, by: 1_000) {
            try addToLedger(Array(entries[start..<min(start + 1_000, entries.count)]), in: database)
        }
        try database.execute("PRAGMA user_version = 1;")
    }

    private static func nanoUSD(_ usd: Decimal) -> Int64 {
        var nano = usd * 1_000_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &nano, 0, .plain)
        // A whole Decimal's description is its digits in any locale; `NSDecimalNumber` is the only other way out.
        return Int64(rounded.description) ?? 0
    }

    static func usd(nano: Int) -> Decimal {
        Decimal(nano) / 1_000_000_000
    }
}
