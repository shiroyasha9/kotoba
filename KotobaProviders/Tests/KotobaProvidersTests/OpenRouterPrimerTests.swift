import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

/// The primer (`TranscriptionProvider.prime`): half a second of silence through the route's whole path, the same
/// model, language and data policy as a dictation, with no dictionary terms.
struct OpenRouterPrimerTests {
    @Test func maiPrimerSendsHalfASecondOfSilenceWithTheRoutesDataPolicy() async throws {
        let stub = StubHost(reply: .fixture("success"))

        _ = await stub.provider().prime(language: Locale.Language(identifier: "en"))

        let sent = try #require(stub.requests.only)
        #expect(sent.url == stub.baseURL.appending(path: "audio/transcriptions"))
        #expect(sent.method == "POST")
        #expect(sent.headers["Authorization"] == "Bearer sk-or-test")
        let body = try sent.json()
        #expect(body["model"] as? String == "microsoft/mai-transcribe-2")
        #expect(body["language"] as? String == "en")
        #expect(body["provider"] as? [String: Bool] == ["zdr": true])
        let audio = try #require(body["input_audio"] as? [String: String])
        #expect(audio["format"] == "flac")
        let flac = try #require(audio["data"].flatMap { Data(base64Encoded: $0) })
        #expect(audio["data"] == OpenRouterProvider.primerAudio)
        #expect(flac.prefix(4) == Data("fLaC".utf8))
    }

    @Test func thePrimerReturnsItsAnswerForItsCost() async throws {
        let stub = StubHost(reply: .fixture("success"))

        let primer = try #require(await stub.provider().prime(language: Locale.Language(identifier: "en")))

        #expect(primer.model == "microsoft/mai-transcribe-2")
        #expect(primer.usage.cost == .reported(try #require(Decimal(string: "0.000344"))))
    }

    @Test func aFailedPrimerIsNil() async {
        let stub = StubHost(reply: .raw(status: 502, body: #"{"error":{"message":"Provider returned 500"}}"#))

        #expect(await stub.provider().prime(language: Locale.Language(identifier: "en")) == nil)
    }

    @Test func directRoutesSendNoPrimer() async {
        let stub = StubHost(reply: .fixture("success"))
        stub.settings.route = .xaiGrok

        #expect(await stub.provider().prime(language: Locale.Language(identifier: "en")) == nil)
        stub.useAzure()
        #expect(await stub.provider().prime(language: Locale.Language(identifier: "en")) == nil)
        #expect(stub.requests.isEmpty)
    }
}
