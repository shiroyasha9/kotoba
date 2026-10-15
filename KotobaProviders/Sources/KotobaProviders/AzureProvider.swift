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
        let (data, response) = try await connection.send(
            endpoint, contentType: multipart.contentType, label: label,
            body: .streamed { writer in
                try writer.write(multipart.field("definition", definition, contentType: "application/json"))
                try writer.write(multipart.fileHeader("audio", filename: "audio.flac", contentType: "audio/flac"))
                try writer.write(contentsOf: request.audio)
                try writer.write(multipart.end)
            })
        let body = try ProviderHTTP.decode(SuccessBody.self, from: data, response: response, label: label)
        // One channel: the first combined phrase is the whole transcript. Azure reports no cost in the response.
        let text = try ProviderHTTP.nonEmpty(body.combinedPhrases.first?.text, label: label)
        let usage = TranscriptionUsage(audio: .milliseconds(body.durationMilliseconds ?? 0), costUSD: nil)
        return Transcript(text: text, usage: usage, model: label)
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
