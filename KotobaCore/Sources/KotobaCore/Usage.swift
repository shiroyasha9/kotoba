import Foundation

/// A request's price in US dollars.
public struct Cost: Sendable, Equatable {
    public var usd: Decimal
    /// True when it comes from a list price because the provider's answer reported no cost.
    public var isEstimated: Bool

    public init(usd: Decimal, isEstimated: Bool) {
        self.usd = usd
        self.isEstimated = isEstimated
    }

    /// The cost the provider's answer reported.
    public static func reported(_ usd: Decimal) -> Self {
        Self(usd: usd, isEstimated: false)
    }

    /// A cost from a list price.
    public static func estimated(_ usd: Decimal) -> Self {
        Self(usd: usd, isEstimated: true)
    }
}

/// One billed request: a speech answer, a cleanup answer or a Polish answer. The usage ledger keeps it apart from the history, so
/// deleting a dictation or its audio never removes what it cost. It holds no dictated text.
public struct UsageEntry: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case speech
        case cleanup
        /// Polish rewrote a dictation already counted: no words and no audio, so it is not a dictation.
        case polish
    }

    /// Makes a second write of the same answer a no-op.
    public var id: UUID
    /// When the speech answer came, also for its cleanup's entry (which comes seconds later, maybe after midnight): the
    /// entry counts in this time's period, so a dictation's words never split across two days.
    public var time: Date
    public var dictation: DictationID?
    public var kind: Kind
    /// The route or cleanup model identifier; `unknownModel` for a cleanup kept before kotoba recorded its model.
    public var model: String
    /// Speech: the audio the route counted (MAI-Transcribe-2 bills whole seconds). Cleanup, Polish and a route primer
    /// (`TranscriptionProvider.prime`): zero, so minutes stay what the owner dictated.
    public var audio: Duration
    /// The change this answer made to the words of the delivered text, so the entries of a dictation add up to the
    /// words it delivered (as History counts them): a speech answer's words, and for a used cleanup its words minus the
    /// transcript's (often negative). Zero for an answer with no words or a cleanup that was not used.
    public var deliveredWords: Int
    /// A speech answer's words, the words the owner said (for words per minute); zero for a cleanup.
    public var spokenWords: Int
    /// Nil when neither the answer nor a list price gives one.
    public var cost: Cost?
    /// The app the dictation went to.
    public var app: DictationApp?

    public static let unknownModel = "unknown"

    public init(
        id: UUID = UUID(), time: Date, dictation: DictationID?, kind: Kind, model: String, audio: Duration = .zero,
        deliveredWords: Int, spokenWords: Int = 0, cost: Cost?, app: DictationApp? = nil
    ) {
        self.id = id
        self.time = time
        self.dictation = dictation
        self.kind = kind
        self.model = model
        self.audio = audio
        self.deliveredWords = deliveredWords
        self.spokenWords = spokenWords
        self.cost = cost
        self.app = app
    }
}
