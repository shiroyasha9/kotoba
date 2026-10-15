import Foundation
import KotobaCore

/// Grok STT direct from xAI: `POST https://api.x.ai/v1/stt`, multipart form, Bearer key. Options go before the
/// file part, which must be last. Untested live: the owner has no xAI account yet.
/// API: https://docs.x.ai/developers/rest-api-reference/inference/speech-to-text
final class XAIProvider: RouteClient {
    static let defaultEndpoint: URL = {
        guard let url = URL(string: "https://api.x.ai/v1/stt") else { preconditionFailure("constant URL") }
        return url
    }()

    private let connection: ProviderConnection
    private let endpoint: URL
    private let makeBoundary: @Sendable () -> String

    init(
        apiKey: any APIKeySource,
        endpoint: URL = defaultEndpoint,
        configuration: URLSessionConfiguration = ProviderHTTP.sessionConfiguration(),
        makeBoundary: @escaping @Sendable () -> String = Multipart.randomBoundary
    ) {
        connection = ProviderConnection(account: .xai, apiKey: apiKey, configuration: configuration)
        self.endpoint = endpoint
        self.makeBoundary = makeBoundary
    }

    func warmUp(_ options: TranscriptionSettings.RouteOptions) async {
        await connection.warm(endpoint)
    }

    func transcribe(_ request: TranscriptionRequest, _ options: TranscriptionSettings.RouteOptions) async throws
        -> Transcript
    {
        let label = options.route.rawValue
        let multipart = Multipart(boundary: makeBoundary())
        let (data, response) = try await connection.send(
            endpoint, contentType: multipart.contentType, label: label,
            body: .streamed { writer in try Self.write(request, options: options, multipart: multipart, to: writer) })
        let body = try ProviderHTTP.decode(SuccessBody.self, from: data, response: response, label: label)
        // xAI reports no cost in the response.
        let usage = TranscriptionUsage(audio: .seconds(body.duration ?? 0), costUSD: nil)
        return Transcript(text: try ProviderHTTP.nonEmpty(body.text, label: label), usage: usage, model: label)
    }

    /// Form fields in xAI's documented names and "true" / "false" values, then the FLAC as the last part. The
    /// dictionary terms come within xAI's limits (`PersonalDictionary.keyterms`: 100 terms of 50 characters).
    private static func write(
        _ request: TranscriptionRequest,
        options: TranscriptionSettings.RouteOptions,
        multipart: Multipart,
        to writer: BodyWriter
    ) throws {
        // `format` works only with `language` set; English is the v1 language, so it is always sent.
        if let language = request.language.languageCode?.identifier {
            try writer.write(multipart.field("language", language))
        }
        try writer.write(multipart.field("format", String(options.isGrokFormatOn)))
        try writer.write(multipart.field("filler_words", String(options.keepsGrokFillerWords)))
        for term in request.dictionaryTerms {
            try writer.write(multipart.field("keyterm", term))
        }
        try writer.write(multipart.fileHeader("file", filename: "audio.flac", contentType: "audio/flac"))
        try writer.write(contentsOf: request.audio)
        try writer.write(multipart.end)
    }
}

private struct SuccessBody: Decodable {
    var text: String?
    /// Audio seconds, rounded to two decimals.
    var duration: Double?
}
