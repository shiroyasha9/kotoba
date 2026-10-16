import Foundation

/// One cloud speech-to-text route.
///
/// Each provider holds one long-lived connection, opened once and reused for every request.
public protocol TranscriptionProvider: Sendable {
    /// Opens or refreshes the connection. The pipeline calls it at key-down.
    func warmUp() async
    /// Whether the current route has a primer. Read at each announcement and timer, so a route switched in the menu
    /// applies to the next one; without a primer the pipeline sends none and arms no primer timer.
    var hasPrimer: Bool { get }
    /// Sends the route's smallest billed request through its whole path, so the answer at the stop does not pay the
    /// route's cold start. The pipeline calls it when a dictation is announced, never for a dropped shortcut press, and
    /// never waits for it. Returns the primer's answer for its cost, or nil when the route has no primer or it failed.
    func prime(language: Locale.Language) async -> Transcript?
    /// Returns every answer, with its usage, even one with no words (it is billed); the pipeline decides that such
    /// an answer heard no speech.
    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript
}

public struct TranscriptionRequest: Sendable, Equatable {
    /// 16 kHz mono FLAC.
    public var audio: URL
    /// The recording's length: the audio count and the cost estimate for a route whose answer has neither.
    public var duration: Duration
    public var language: Locale.Language
    /// Dictionary terms, sent where the route supports them.
    public var dictionaryTerms: [String]
    /// A route's model (`Transcript.model`) to use in place of the owner's choice, for History's "Transcribe Again
    /// With"; nil uses the owner's choice.
    public var model: String?

    public init(
        audio: URL, duration: Duration, language: Locale.Language, dictionaryTerms: [String], model: String? = nil
    ) {
        self.audio = audio
        self.duration = duration
        self.language = language
        self.dictionaryTerms = dictionaryTerms
        self.model = model
    }
}

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var usage: TranscriptionUsage
    /// The route's model identifier this request used, stored with the dictation so the latency report can split
    /// by model. It comes from the provider's answer, so a model switch during the request cannot mislabel it.
    public var model: String
    /// When the request left and the answer started, from the system's network metrics; nil when they did not come
    /// before the answer, or lack those moments (a failed request, a test stub).
    public var network: NetworkTiming?

    public init(text: String, usage: TranscriptionUsage, model: String, network: NetworkTiming? = nil) {
        self.text = text
        self.usage = usage
        self.model = model
        self.network = network
    }
}

/// The moments of one upload on `ContinuousClock` (the clock `SystemClock` uses), so `make latency` can split the
/// network wait into upload and server time. The system measures them and hands them over after the answer; the pipeline records them as marks.
public struct NetworkTiming: Sendable, Equatable {
    /// The upload opened its own connection, which was ready (TLS done) here; nil when it reused the warmed one.
    public var connected: ContinuousClock.Instant?
    /// The last body byte went to the network stack (URLSession's `requestEndDate`). The kernel can still hold the
    /// tail of the body: a reused HTTP/2 connection took 300 KB in 13-16 ms, faster than the uplink, so this to
    /// `firstByte` includes some upload too.
    public var uploadSent: ContinuousClock.Instant
    /// The first byte of the answer arrived (`responseStartDate`).
    public var firstByte: ContinuousClock.Instant

    public init(
        connected: ContinuousClock.Instant? = nil, uploadSent: ContinuousClock.Instant,
        firstByte: ContinuousClock.Instant
    ) {
        self.connected = connected
        self.uploadSent = uploadSent
        self.firstByte = firstByte
    }
}

public struct TranscriptionUsage: Sendable, Equatable {
    /// The audio length the route counted, or the recording's length when its answer has none.
    public var audio: Duration
    /// The reported cost, else an estimate from the route's list price; nil when neither is known.
    public var cost: Cost?

    public init(audio: Duration, cost: Cost?) {
        self.audio = audio
        self.cost = cost
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
    /// The account has no credit left (402). The dictation waits until the owner adds credit.
    case noCredit
    /// Any other 4xx (bad request, payload too large). Retrying the same request gives the same answer.
    case rejected(status: Int, message: String)
    /// The route answered with no words: the pipeline throws it after it kept the answer's usage.
    case emptyTranscript
    /// The recording has no audio (`RecordedAudio.hasAudio`): the pipeline throws it before any request.
    case noAudio

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
        case .noCredit: .credit
        case .needsSetup(_, let item): item
        default: nil
        }
    }

    public var recovery: Recovery {
        switch self {
        case .offline, .keyUnavailable, .rateLimited, .server: .transient
        case .auth, .needsSetup, .noCredit: .needsSetup
        case .rejected, .emptyTranscript, .noAudio: .permanent
        }
    }

    /// Why the route refused, for a `.permanent` error; the indicator picks its text and button from it.
    public var rejectReason: RejectReason? {
        switch self {
        case .emptyTranscript, .noAudio: .emptyTranscript
        case .rejected: .other
        case .offline, .auth, .needsSetup, .noCredit, .keyUnavailable, .rateLimited, .server: nil
        }
    }
}

/// Why a dictation was rejected.
public enum RejectReason: String, Sendable {
    /// The route heard no speech, or the recording has no audio to send.
    case emptyTranscript
    case other
}

/// What `ProviderError.needsSetup` asks the owner to set.
public enum SetupItem: String, Sendable {
    case key
    /// The Azure Speech resource endpoint.
    case endpoint
    /// Credit on the provider account: a dictation refused for no credit waits for it (lead decision 6).
    case credit
}
