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

    private let connection: ProviderConnection
    private let baseURL: URL

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

    func transcribe(_ request: TranscriptionRequest, _ options: TranscriptionSettings.RouteOptions) async throws
        -> Transcript
    {
        let label = options.route.rawValue
        let rest = try ProviderHTTP.encode(Self.fields(request, options: options))
        let (data, response) = try await connection.send(
            baseURL.appending(path: "audio/transcriptions"), contentType: "application/json", label: label,
            body: .streamed { writer in
                // `input_audio` first, its base64 streamed from the FLAC, then the other fields from `rest`.
                try writer.write(#"{"input_audio":{"format":"flac","data":""#)
                try writer.write(contentsOf: request.audio, base64: true)
                try writer.write(#""},"#)
                try writer.write(rest.dropFirst())  // `rest` is a non-empty object: drop its "{".
            })
        let body = try ProviderHTTP.decode(SuccessBody.self, from: data, response: response, label: label)
        let usage = TranscriptionUsage(audio: .seconds(body.usage?.seconds ?? 0), costUSD: body.usage?.cost)
        return Transcript(text: try ProviderHTTP.nonEmpty(body.text, label: label), usage: usage, model: label)
    }

    /// Every body field except `input_audio`. The dictionary terms come within the route limits
    /// (`PersonalDictionary.keyterms`).
    private static func fields(_ request: TranscriptionRequest, options: TranscriptionSettings.RouteOptions)
        -> RequestFields
    {
        let route = options.route
        let terms = request.dictionaryTerms
        let language = request.language.languageCode?.identifier
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
private struct RequestFields: Encodable {
    struct Provider: Encodable {
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
private struct ProviderOptions: Encodable {
    struct Azure: Encodable {
        var phraseList: PhraseList
    }

    var azure: Azure?
    var xai: XAIOptions?
}

/// xAI documents `format` and `filler_words` as "true" / "false" form fields. The live check on 2026-10-15 showed
/// OpenRouter forwards `filler_words` as a JSON boolean (fillers kept); `format` is not yet confirmed.
private struct XAIOptions: Encodable {
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

private struct SuccessBody: Decodable {
    struct Usage: Decodable {
        var seconds: Double?
        var cost: Decimal?
    }

    var text: String?
    var usage: Usage?
}
