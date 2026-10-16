import Foundation
import KotobaCore

/// MAI-Transcribe-2 direct from Azure Speech: fast transcription, `POST {resource endpoint}/speechtotext/
/// transcriptions:transcribe`, multipart with a `definition` JSON part and the `audio` file. Untested live: the
/// owner has no Azure account yet.
/// API: https://learn.microsoft.com/en-us/rest/api/speechtotext/transcriptions/transcribe (2025-10-15) and
/// https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe
final class AzureProvider: RouteClient {
    static let apiVersion = "2025-10-15"

    private let connection: ProviderConnection
    private let makeBoundary: @Sendable () -> String

    init(
        apiKey: any APIKeySource,
        configuration: URLSessionConfiguration = ProviderHTTP.sessionConfiguration(),
        makeBoundary: @escaping @Sendable () -> String = Multipart.randomBoundary
    ) {
        connection = ProviderConnection(
            account: .azure, apiKey: apiKey, keyHeader: .subscriptionKey, configuration: configuration)
        self.makeBoundary = makeBoundary
    }

    func warmUp(_ options: TranscriptionSettings.RouteOptions) async {
        guard let endpoint = Self.transcribeURL(options.azureEndpoint) else { return }
        await connection.warm(endpoint)
    }

    /// `POST {endpoint}/sts/v1.0/issueToken`: free, swaps the key for a 10-minute token
    /// (https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-speech-to-text-short). 401 is a wrong
    /// key; 403 with a key sent means the resource is out of quota.
    func checkKey(_ key: String, _ options: TranscriptionSettings.RouteOptions) async -> KeyCheck {
        guard let endpoint = options.azureEndpoint else { return .needsEndpoint }
        let url = endpoint.appending(path: "sts/v1.0/issueToken")
        guard let (_, response) = await connection.probe(url, method: "POST", key: key) else { return .unreachable }
        switch response.statusCode {
        case 200: return .valid
        case 401: return .invalid
        case 403: return .noCredit
        default: return .unreachable
        }
    }

    func transcribe(_ request: TranscriptionRequest, _ options: TranscriptionSettings.RouteOptions) async throws
        -> Transcript
    {
        // A missing endpoint is a setup gap like a missing key: the dictation waits until the owner sets it.
        guard let endpoint = Self.transcribeURL(options.azureEndpoint) else {
            throw ProviderError.needsSetup(provider: ProviderAccount.azure.title, item: .endpoint)
        }
        let label = options.route.rawValue
        let multipart = Multipart(boundary: makeBoundary())
        let definition = try Self.definition(request)
        let reply = try await connection.send(
            endpoint, contentType: multipart.contentType, label: label,
            body: .streamed { writer in
                try writer.write(multipart.field("definition", definition, contentType: "application/json"))
                try writer.write(multipart.fileHeader("audio", filename: "audio.flac", contentType: "audio/flac"))
                try writer.write(contentsOf: request.audio)
                try writer.write(multipart.end)
            })
        let body = try ProviderHTTP.decode(SuccessBody.self, from: reply, label: label)
        // One channel: the first combined phrase is the whole transcript. Azure reports no cost in the response.
        let text = body.combinedPhrases.first?.text ?? ""
        let usage = TranscriptionUsage.priced(
            audio: body.durationMilliseconds.map { .milliseconds($0) }, cost: nil, for: request, on: options.route)
        return Transcript(text: text, usage: usage, model: label, network: reply.network)
    }

    private static func transcribeURL(_ endpoint: URL?) -> URL? {
        endpoint?
            .appending(path: "speechtotext/transcriptions:transcribe")
            .appending(queryItems: [URLQueryItem(name: "api-version", value: apiVersion)])
    }

    /// The `definition` part. The dictionary terms come within the route limits (`PersonalDictionary.keyterms`).
    private static func definition(_ request: TranscriptionRequest) throws -> String {
        let terms = request.dictionaryTerms
        let definition = Definition(
            enhancedMode: .init(enabled: true, model: "MAI-Transcribe-2"),
            // Microsoft's MAI-Transcribe example sends a bare language code ("locales": ["en"]); the OpenRouter route
            // sends language "en" too. Microsoft calls it a strong hint, and English is the v1 language.
            locales: request.language.languageCode.map { [$0.identifier] },
            phraseList: terms.isEmpty ? nil : PhraseList(phrases: terms)
        )
        return String(bytes: try ProviderHTTP.encode(definition), encoding: .utf8) ?? ""
    }
}

private struct Definition: Encodable {
    struct EnhancedMode: Encodable {
        var enabled: Bool
        var model: String
    }

    var enhancedMode: EnhancedMode
    var locales: [String]?
    var phraseList: PhraseList?
}

private struct SuccessBody: Decodable {
    struct Phrase: Decodable {
        var text: String
    }

    var durationMilliseconds: Int?
    var combinedPhrases: [Phrase]
}
