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

    /// `GET /v1/api-key`: free, describes the key. A wrong key answers 400 ("Incorrect API key provided", seen on
    /// 2026-10-15). `team_blocked` is read as no credit: xAI blocks a team that has no credit left or is over its
    /// spending limit (not stated in xAI's docs; check on the first live test).
    func checkKey(_ key: String, _ options: TranscriptionSettings.RouteOptions) async -> KeyCheck {
        let url = endpoint.deletingLastPathComponent().appending(path: "api-key")
        guard let (data, response) = await connection.probe(url, method: "GET", key: key) else { return .unreachable }
        switch response.statusCode {
        case 200: break
        case 400: return .invalid
        default: return ProviderHTTP.keyCheck(status: response.statusCode)
        }
        // A body of another shape (a proxy page) proves nothing about the key.
        guard let info = try? JSONDecoder().decode(KeyInfo.self, from: data) else { return .unreachable }
        if info.apiKeyBlocked || info.apiKeyDisabled { return .invalid }
        return info.teamBlocked ? .noCredit : .valid
    }

    /// No primer: this route's cold start is not measured (docs/research/latency-pass.md).
    func hasPrimer(_ route: TranscriptionRoute) -> Bool { false }

    /// Never called: `hasPrimer` is false.
    func prime(_ options: TranscriptionSettings.RouteOptions, language: Locale.Language, size: PrimerSize) async
        -> Transcript?
    { nil }

    func transcribe(_ request: TranscriptionRequest, _ options: TranscriptionSettings.RouteOptions) async throws
        -> Transcript
    {
        let label = options.route.rawValue
        let multipart = Multipart(boundary: makeBoundary())
        let reply = try await connection.send(
            endpoint, contentType: multipart.contentType, label: label,
            body: .streamed { writer in try Self.write(request, options: options, multipart: multipart, to: writer) })
        let body = try ProviderHTTP.decode(SuccessBody.self, from: reply, label: label)
        // xAI reports no cost in the response.
        let usage = TranscriptionUsage.priced(
            audio: body.duration.map { .seconds($0) }, cost: nil, recorded: request.duration, on: options.route)
        return Transcript(text: body.text ?? "", usage: usage, model: label, network: reply.network)
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

private struct KeyInfo: Decodable {
    enum CodingKeys: String, CodingKey {
        case apiKeyBlocked = "api_key_blocked"
        case apiKeyDisabled = "api_key_disabled"
        case teamBlocked = "team_blocked"
    }

    var apiKeyBlocked: Bool
    var apiKeyDisabled: Bool
    var teamBlocked: Bool
}
