import Foundation
import KotobaCore

/// MAI-Transcribe-2 or Grok STT through OpenRouter's `POST /audio/transcriptions`: JSON with base64 audio, and the
/// dictionary terms passed through as the upstream provider's own option (`provider.options.<tag>`).
/// API: https://openrouter.ai/docs/guides/overview/multimodal/stt. Errors: https://openrouter.ai/docs/api/reference/errors-and-debugging
final class OpenRouterProvider: RouteClient {
    static let defaultBaseURL: URL = {
        guard let url = URL(string: "https://openrouter.ai/api/v1") else { preconditionFailure("constant URL") }
        return url
    }()

    let connection: ProviderConnection
    let baseURL: URL
    /// The primers' request bodies (`OpenRouterPrimer.swift`).
    let primerBodies = PrimerBodies()

    init(
        apiKey: any APIKeySource,
        baseURL: URL = defaultBaseURL,
        configuration: URLSessionConfiguration = ProviderHTTP.sessionConfiguration()
    ) {
        connection = ProviderConnection(account: .openRouter, apiKey: apiKey, configuration: configuration)
        self.baseURL = baseURL
    }

    func warmUp(_ options: TranscriptionSettings.RouteOptions) async {
        await connection.warm(baseURL.appending(path: "models/\(options.route.rawValue)/endpoints"))
    }

    /// `GET /key`: free, returns the key's credit limit (https://openrouter.ai/docs/api/reference/limits). An
    /// account with no credit at all is not visible here: the account balance (`GET /credits`) needs a management
    /// key, not the API key kotoba holds (checked 2026-10-15). The first dictation reports it (402).
    func checkKey(_ key: String, _ options: TranscriptionSettings.RouteOptions) async -> KeyCheck {
        guard let (data, response) = await connection.probe(baseURL.appending(path: "key"), method: "GET", key: key)
        else { return .unreachable }
        guard response.statusCode == 200 else { return ProviderHTTP.keyCheck(status: response.statusCode) }
        // A body of another shape (a proxy page) proves nothing about the key.
        guard let info = try? JSONDecoder().decode(KeyInfo.self, from: data) else { return .unreachable }
        if let remaining = info.data.limitRemaining, remaining <= 0 { return .noCredit }
        return .valid
    }

    func transcribe(_ request: TranscriptionRequest, _ options: TranscriptionSettings.RouteOptions) async throws
        -> Transcript
    {
        let label = options.route.rawValue
        let fields = Self.fields(terms: request.dictionaryTerms, language: request.language, options: options)
        let rest = try ProviderHTTP.encode(fields)
        let reply = try await connection.send(
            baseURL.appending(path: "audio/transcriptions"), contentType: "application/json", label: label,
            body: .streamed { writer in
                // `input_audio` first, its base64 streamed from the FLAC, then the other fields from `rest`.
                try writer.write(#"{"input_audio":{"format":"flac","data":""#)
                try writer.write(contentsOf: request.audio, base64: true)
                try writer.write(#""},"#)
                try writer.write(rest.dropFirst())  // `rest` is a non-empty object: drop its "{".
            })
        let answer = try ProviderHTTP.decode(OpenRouterAnswer.self, from: reply, label: label)
        let usage = TranscriptionUsage.priced(
            audio: answer.usage?.seconds.map { .seconds($0) }, cost: answer.usage?.charged, recorded: request.duration,
            on: options.route)
        return Transcript(text: answer.text ?? "", usage: usage, model: label, network: reply.network)
    }

    /// Every body field except `input_audio`. The dictionary terms come within the route limits
    /// (`PersonalDictionary.keyterms`).
    static func fields(
        terms: [String], language: Locale.Language, options: TranscriptionSettings.RouteOptions
    ) -> RequestFields {
        let route = options.route
        let language = language.languageCode?.identifier
        let upstream: ProviderOptions? =
            if route.isGrok {
                .init(
                    xai: .init(
                        keyterm: terms.isEmpty ? nil : terms,
                        format: options.isGrokFormatOn,
                        fillerWords: options.keepsGrokFillerWords,
                        // xAI applies `format` only when its own `language` is set.
                        language: options.isGrokFormatOn ? language : nil
                    )
                )
            } else {
                terms.isEmpty ? nil : .init(azure: .init(phraseList: PhraseList(phrases: terms)))
            }
        return RequestFields(
            model: route.rawValue,
            language: language,
            provider: .init(zdr: route.hasZeroDataRetention, options: upstream)
        )
    }
}

/// Every body field except `input_audio`, which the body writer streams in before them.
struct RequestFields: Encodable, Equatable {
    struct Provider: Encodable, Equatable {
        /// `TranscriptionRoute.hasZeroDataRetention`.
        var zdr: Bool
        var options: ProviderOptions?
    }

    var model: String
    var language: String?
    var provider: Provider
}

/// Upstream fields keyed by OpenRouter's provider tag, sent under the provider's own field names. OpenRouter documents
/// the `options` passthrough; kotoba-bench-v1 showed `phraseList` and `keyterm` reach the model (MAI term recall
/// 58.7% -> 73.2%). xAI fields: https://docs.x.ai/developers/rest-api-reference/inference/speech-to-text
struct ProviderOptions: Encodable, Equatable {
    struct Azure: Encodable, Equatable {
        var phraseList: PhraseList
    }

    var azure: Azure?
    var xai: XAIOptions?
}

/// xAI documents `format` and `filler_words` as "true" / "false" form fields. The live check on 2026-10-15 showed
/// OpenRouter forwards `filler_words` as a JSON boolean (fillers kept); `format` is not yet confirmed.
struct XAIOptions: Encodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case keyterm
        case format
        case fillerWords = "filler_words"
        case language
    }

    var keyterm: [String]?
    /// Inverse text normalization (spoken numbers and units to digits).
    var format: Bool
    /// False removes "um" and "uh" (the xAI default).
    var fillerWords: Bool
    var language: String?
}

/// A transcription answer. A `usage` block that does not parse (a field of another type) is left out, so its cost is
/// estimated from the list price: the text is what was billed, and it is never dropped for it.
struct OpenRouterAnswer: Decodable {
    private enum CodingKeys: String, CodingKey {
        case text
        case usage
    }

    var text: String?
    var usage: OpenRouterUsage?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        do {
            usage = try container.decodeIfPresent(OpenRouterUsage.self, forKey: .usage)
        } catch {
            ProviderHTTP.log.error("OpenRouter usage does not parse, the cost is estimated: \(error)")
            usage = nil
        }
    }
}

/// `GET /key`.
private struct KeyInfo: Decodable {
    var data: KeyLimit
}

/// `limit_remaining` is null for a key without a credit limit.
private struct KeyLimit: Decodable {
    enum CodingKeys: String, CodingKey {
        case limitRemaining = "limit_remaining"
    }

    var limitRemaining: Double?
}

/// The `usage` of an OpenRouter answer, transcription or chat (https://openrouter.ai/docs/use-cases/usage-accounting:
/// "always included automatically in every response").
struct OpenRouterUsage: Decodable {
    enum CodingKeys: String, CodingKey {
        case seconds
        case cost
        case isBYOK = "is_byok"
        case costDetails = "cost_details"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }

    /// Transcription: the audio the route counted.
    var seconds: Double?
    /// What OpenRouter charged the account; with the owner's own provider key (BYOK) only OpenRouter's fee.
    var cost: Decimal?
    var isBYOK: Bool
    private var costDetails: CostDetails?
    var promptTokens: Int?
    /// Includes reasoning tokens.
    var completionTokens: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try container.decodeIfPresent(Double.self, forKey: .seconds)
        cost = try container.decodeIfPresent(Decimal.self, forKey: .cost)
        isBYOK = try container.decodeIfPresent(Bool.self, forKey: .isBYOK) ?? false
        costDetails = try container.decodeIfPresent(CostDetails.self, forKey: .costDetails)
        promptTokens = try container.decodeIfPresent(Int.self, forKey: .promptTokens)
        completionTokens = try container.decodeIfPresent(Int.self, forKey: .completionTokens)
    }

    /// What the request cost the owner: with BYOK the provider's charge is billed apart, so it is added, and nil
    /// when it is missing (the caller estimates then). Without BYOK `upstream_inference_cost` is the same money as
    /// `cost` (kotoba-bench-v1 rows had both equal), so it is not added.
    var charged: Decimal? {
        guard isBYOK else { return cost }
        guard let upstream = costDetails?.upstreamInferenceCost else { return nil }
        return (cost ?? 0) + upstream
    }
}

private struct CostDetails: Decodable {
    enum CodingKeys: String, CodingKey {
        case upstreamInferenceCost = "upstream_inference_cost"
    }

    var upstreamInferenceCost: Decimal?
}
