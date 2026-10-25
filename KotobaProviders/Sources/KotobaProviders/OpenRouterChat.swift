import Foundation
import KotobaCore

/// OpenRouter's `POST /chat/completions` as cleanup (`OpenRouterCleaner`) and Polish (`OpenRouterPolisher`) send it:
/// one rewrite of a dictated text, not streamed, so only the total time counts.
/// API: https://openrouter.ai/docs/api/reference/chat-completion
struct ChatRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    enum CodingKeys: String, CodingKey {
        case model
        case stream
        case maxTokens = "max_tokens"
        case messages
        case reasoning
        case temperature
        case provider
    }

    var model: String
    var stream = false
    var maxTokens: Int
    var messages: [Message]
    var reasoning: ChatReasoning?
    var temperature: Double?
    var provider = ChatRouting()

    /// The system prompt, then the text in the user message. `floor` is the limit the bench measured for short texts
    /// (cleanup 2,048, Polish 4,096).
    init(model: String, system: String, user: String, rewriting text: String, floor: Int) {
        self.model = model
        maxTokens = Self.maxTokens(rewriting: text, floor: floor)
        messages = [.init(role: "system", content: system), .init(role: "user", content: user)]
    }

    /// The output limit for a rewrite of `text`: room for the whole text twice (a cleanup or a polish is no longer than
    /// its input) and 1,024 tokens of reasoning, at least `floor` and at most 16,384 (about 4,000 words, half an hour
    /// of speech). Tokens are counted as UTF-8 bytes / 3, more than English text uses (about 4 bytes a token), so paths
    /// and identifiers fit too. An answer that still reaches the limit comes back cut (`ChatAnswer.isComplete`) and is
    /// never pasted.
    static func maxTokens(rewriting text: String, floor: Int) -> Int {
        let tokens = (text.utf8.count + 2) / 3
        return min(max(2 * tokens + 1_024, floor), 16_384)
    }
}

/// `{"effort": ...}` or `{"enabled": false}`.
enum ChatReasoning: Encodable {
    case effort(String)
    case off

    private enum CodingKeys: String, CodingKey {
        case effort
        case enabled
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .effort(let effort): try container.encode(effort, forKey: .effort)
        case .off: try container.encode(false, forKey: .enabled)
        }
    }
}

/// OpenRouter provider routing (https://openrouter.ai/docs/guides/routing/provider-selection): zero data retention
/// always (every cleanup and Polish model has such an endpoint, `GET /api/v1/endpoints/zdr` on 2026-10-15 and
/// 2026-10-17), and for some models the hosts to use, with no other host after them.
struct ChatRouting: Encodable {
    enum Hosts {
        /// OpenRouter picks.
        case any
        /// One host (`only`).
        case only(String)
        /// Several hosts, tried in order (`order`).
        case order([String])
    }

    private enum CodingKeys: String, CodingKey {
        case zdr
        case only
        case order
        case allowFallbacks = "allow_fallbacks"
    }

    var hosts = Hosts.any

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(true, forKey: .zdr)
        switch hosts {
        case .any: return
        case .only(let host): try container.encode([host], forKey: .only)
        case .order(let hosts): try container.encode(hosts, forKey: .order)
        }
        try container.encode(false, forKey: .allowFallbacks)
    }
}

/// The answer to a `ChatRequest`.
struct ChatAnswer: Decodable {
    var choices: [ChatChoice]
    var usage: OpenRouterUsage?

    /// The first choice's text; empty when there is none.
    var text: String { choices.first?.message.content ?? "" }

    /// The model ended the text itself: OpenRouter's normalized `finish_reason` is "stop". "length" (the token limit)
    /// or "content_filter" cut it, so the text is partial.
    var isComplete: Bool { choices.first?.finishReason == "stop" }

    /// Sends `request` on `connection` and decodes the answer; an answer that did not end on its own is logged under
    /// `label`.
    static func send(_ request: ChatRequest, on connection: ProviderConnection, at baseURL: URL, label: String)
        async throws -> Self
    {
        // A few KB of JSON: sent from memory, no temp file.
        let reply = try await connection.send(
            baseURL.appending(path: "chat/completions"), contentType: "application/json", label: label,
            body: .data(try ProviderHTTP.encode(request)))
        let answer = try ProviderHTTP.decode(Self.self, from: reply, label: label)
        if !answer.isComplete {
            let reason = answer.choices.first?.finishReason ?? "no reason"
            ProviderHTTP.log.error("\(label, privacy: .public) ended with \(reason, privacy: .public)")
        }
        return answer
    }
}

/// A cleanup or Polish model, with the model to try when its hosts fail.
protocol ChatModel: RawRepresentable where RawValue == String {
    var fallback: Self? { get }
}

/// The second model of cleanup and Polish. A model on a few pinned hosts has no other host after them, so when
/// they fail its step sends once more to another model. OpenRouter's own `models` list cannot do it: the fallback
/// gets the first model's hosts and switches, and Gemini runs on none of DeepSeek's hosts.
enum ChatFallback {
    /// `model` first; when its route cannot serve now (a 5xx, a rate limit, or a 404: no host could take it), its
    /// fallback once. Everything else fails at once, as the other model would fail the same way or pay again: a
    /// missing key, no credit, no network, a timeout (slow, not down; a live cleanup has pasted by then), another 4xx
    /// (a bad request) or a billed answer that does not parse (lead, 2026-10-25).
    static func send<Model: ChatModel, Answer>(
        _ model: Model, step: String, _ attempt: (Model) async throws -> Answer
    ) async throws -> Answer {
        do {
            return try await attempt(model)
        } catch let error as ProviderError where isFallbackCase(error) {
            guard let fallback = model.fallback else { throw error }
            try Task.checkCancellation()
            ProviderHTTP.log.notice("\(step, privacy: .public) falls back to \(fallback.rawValue, privacy: .public)")
            return try await attempt(fallback)
        }
    }

    private static func isFallbackCase(_ error: ProviderError) -> Bool {
        switch error {
        case .server(let status): status >= 500
        case .rejected(let status, _): status == 404
        case .rateLimited: true
        case .timedOut, .unreadableAnswer, .offline, .connectionBlocked, .hostNotFound, .auth, .needsSetup,
            .keyUnavailable, .noCredit, .emptyTranscript, .noAudio, .audioMissing, .tooLong:
            false
        }
    }
}

struct ChatChoice: Decodable {
    struct Message: Decodable {
        var content: String?
    }

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }

    var message: Message
    var finishReason: String?
}
