import Foundation

/// One cloud speech-to-text route.
///
/// Each provider holds one long-lived connection, opened once and reused for every request.
public protocol TranscriptionProvider: Sendable {
    /// Opens or refreshes the connection. The pipeline calls it at key-down.
    func warmUp() async
    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript
}

public struct TranscriptionRequest: Sendable, Equatable {
    /// 16 kHz mono FLAC.
    public var audio: URL
    public var language: Locale.Language
    /// Dictionary terms, sent where the route supports them.
    public var dictionaryTerms: [String]

    public init(audio: URL, language: Locale.Language, dictionaryTerms: [String]) {
        self.audio = audio
        self.language = language
        self.dictionaryTerms = dictionaryTerms
    }
}

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var usage: TranscriptionUsage

    public init(text: String, usage: TranscriptionUsage) {
        self.text = text
        self.usage = usage
    }
}

public struct TranscriptionUsage: Sendable, Equatable {
    public var audio: Duration
    /// Nil when the route does not report cost.
    public var costUSD: Decimal?

    public init(audio: Duration, costUSD: Decimal?) {
        self.audio = audio
        self.costUSD = costUSD
    }
}
