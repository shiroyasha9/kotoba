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
    /// The route's model identifier this request used, stored with the dictation so the latency report can split
    /// by model. It comes from the provider's answer, so a model switch during the request cannot mislabel it.
    public var model: String

    public init(text: String, usage: TranscriptionUsage, model: String) {
        self.text = text
        self.usage = usage
        self.model = model
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

/// Why a transcription failed, in the cases the pipeline acts on. The audio is kept in every case;
/// `recovery` says what can make the same request succeed later.
public enum ProviderError: Error, Sendable, Equatable {
    /// No network, a timeout or a lost connection.
    case offline
    /// The route rejected the key (401, 403).
    case auth(status: Int?)
    /// Something the owner must set in Settings before the route can work: `provider` is its display name.
    case needsSetup(provider: String, item: SetupItem)
    /// The key store failed for a reason other than "no key" (a locked keychain); a later try can read it.
    case keyUnavailable
    /// 429. `retryAfter` comes from the `Retry-After` header when the route sends one.
    case rateLimited(retryAfter: Duration?)
    /// 408, 5xx, or a success status with a body that does not parse.
    case server(status: Int)
    /// Any other 4xx (bad request, no credits). Retrying the same request gives the same answer.
    case rejected(status: Int, message: String)
    /// The route answered but heard no speech.
    case emptyTranscript

    public enum Recovery: Sendable, Equatable {
        /// Network, server or rate limit: a later retry can succeed.
        case transient
        /// The route needs a key or an endpoint: retry once the owner sets it, not before.
        case needsSetup
        /// The same request gets the same answer.
        case permanent
    }

    /// What the owner must set, for a `.needsSetup` error.
    public var setupItem: SetupItem? {
        switch self {
        case .auth: .key
        case .needsSetup(_, let item): item
        default: nil
        }
    }

    public var recovery: Recovery {
        switch self {
        case .offline, .keyUnavailable, .rateLimited, .server: .transient
        case .auth, .needsSetup: .needsSetup
        case .rejected, .emptyTranscript: .permanent
        }
    }
}

/// What `ProviderError.needsSetup` asks the owner to set.
public enum SetupItem: String, Sendable {
    case key
    /// The Azure Speech resource endpoint.
    case endpoint
}
