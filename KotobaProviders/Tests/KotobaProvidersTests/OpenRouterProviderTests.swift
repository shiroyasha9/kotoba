import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

/// Requests go to a `StubURLProtocol` host owned by one test; replies come from `Fixtures/` (shapes from
/// OpenRouter's STT and error docs). No test reaches the network.
struct OpenRouterProviderTests {
    // MARK: Request building

    @Test func maiRequestSendsThePhraseListAndTheCleanStyle() async throws {
        let stub = StubHost(reply: .fixture("success"))
        let provider = stub.provider()

        _ = try await provider.transcribe(stub.request(terms: ["DictationPipeline", "swiftlint"]))

        let sent = try #require(stub.requests.only)
        #expect(sent.url == stub.baseURL.appending(path: "audio/transcriptions"))
        #expect(sent.method == "POST")
        #expect(sent.headers["Authorization"] == "Bearer sk-or-test")
        #expect(sent.headers["Content-Type"] == "application/json")
        let body = try sent.json()
        #expect(body["model"] as? String == "microsoft/mai-transcribe-2")
        #expect(body["language"] as? String == "en")
        let options = try #require((body["provider"] as? [String: Any])?["options"] as? [String: Any])
        #expect(options.keys.sorted() == ["azure"])
        let azure = try #require(options["azure"] as? [String: Any])
        #expect((azure["phraseList"] as? [String: Any])?["phrases"] as? [String] == ["DictationPipeline", "swiftlint"])
        let enhancedMode = try #require(azure["enhancedMode"] as? [String: Any])
        #expect(enhancedMode["enabled"] as? Bool == true)
        #expect(enhancedMode["model"] as? String == "MAI-Transcribe-2")
        #expect(enhancedMode["modelOptions"] as? [String: String] == ["transcribeStyle": "clean"])
    }

    /// The clean style does not depend on the dictionary: with no terms it still goes, with no phrase list.
    @Test func maiRequestWithoutTermsStillSendsTheCleanStyle() async throws {
        let stub = StubHost(reply: .fixture("success"))

        _ = try await stub.provider().transcribe(stub.request(terms: []))

        #expect(try #require(stub.requests.only).json().azureOptions.keys.sorted() == ["enhancedMode"])
    }

    @Test func requestBodyMatchesTheRecordedBytes() async throws {
        let stub = StubHost(reply: .fixture("success"))

        _ = try await stub.provider().transcribe(stub.request(terms: ["DictationPipeline", "src/main.swift"]))

        let body = try #require(stub.requests.only).body
        let expected = StubReply.fixtureText("request-mai").trimmingCharacters(in: .newlines)
        #expect(String(bytes: body, encoding: .utf8) == expected)
    }

    @Test(arguments: [0, BodyWriter.chunk - 1, BodyWriter.chunk, BodyWriter.chunk + 1, BodyWriter.chunk + 2, 150_001])
    func audioIsEncodedWholeAcrossChunkBoundaries(byteCount: Int) async throws {
        let stub = StubHost(reply: .fixture("success"))
        // Grok sends the FLAC as it is.
        stub.settings.route = .openRouterGrok
        let audio = Data((0..<byteCount).map { UInt8(truncatingIfNeeded: $0 &* 31) })

        _ = try await stub.provider().transcribe(stub.request(audio: audio))

        let sent = try #require(stub.requests.only).json()
        #expect((sent["input_audio"] as? [String: String])?["data"] == audio.base64EncodedString())
    }

    @Test func grokRequestSendsKeytermsAndDefaultOptions() async throws {
        let stub = StubHost(reply: .fixture("success"))
        stub.settings.route = .openRouterGrok

        _ = try await stub.provider().transcribe(stub.request(terms: ["kotoba"]))

        let body = try #require(stub.requests.only).json()
        #expect(body["model"] as? String == "x-ai/grok-stt-1.0")
        #expect(body["language"] as? String == "en")
        let options = try #require((body["provider"] as? [String: Any])?["options"] as? [String: Any])
        #expect(options.keys.sorted() == ["xai"])
        let xai = try #require(options["xai"] as? [String: Any])
        #expect(xai.keys.sorted() == ["filler_words", "format", "keyterm"])
        #expect(xai["keyterm"] as? [String] == ["kotoba"])
        #expect(xai["format"] as? Bool == false)
        #expect(xai["filler_words"] as? Bool == false)
    }

    @Test func grokFormatSendsXAILanguage() async throws {
        let stub = StubHost(reply: .fixture("success"))
        stub.settings.route = .openRouterGrok
        stub.settings.isGrokFormatOn = true

        _ = try await stub.provider().transcribe(stub.request())

        let xai = try #require(stub.requests.only).json().xaiOptions
        #expect(xai.keys.sorted() == ["filler_words", "format", "language"])
        #expect(xai["format"] as? Bool == true)
        #expect(xai["language"] as? String == "en")
    }

    @Test func grokFillerWordsAreKeptWhenOn() async throws {
        let stub = StubHost(reply: .fixture("success"))
        stub.settings.route = .openRouterGrok
        stub.settings.keepsFillerWords = true

        _ = try await stub.provider().transcribe(stub.request())

        let xai = try #require(stub.requests.only).json().xaiOptions
        #expect(xai["filler_words"] as? Bool == true)
        #expect(xai["format"] as? Bool == false)
    }

    @Test func modeSwitchAppliesToTheNextRequest() async throws {
        let stub = StubHost(reply: .fixture("success"))
        let provider = stub.provider()

        _ = try await provider.transcribe(stub.request())
        stub.settings.route = .openRouterGrok
        _ = try await provider.transcribe(stub.request())

        #expect(
            try stub.requests.map { try $0.json()["model"] as? String } == [
                "microsoft/mai-transcribe-2", "x-ai/grok-stt-1.0",
            ])
    }

    @Test func transcriptReportsTheModelItWasSentWithWhenTheSettingChangesMidRequest() async throws {
        let stub = StubHost(reply: .fixture("success"))
        let settings = stub.settings
        stub.onRequest { settings.route = .openRouterGrok }

        let transcript = try await stub.provider().transcribe(stub.request())

        #expect(transcript.model == "microsoft/mai-transcribe-2")
        #expect(try #require(stub.requests.only).json()["model"] as? String == "microsoft/mai-transcribe-2")
        #expect(settings.route == .openRouterGrok)
    }

    @Test(arguments: [
        (TranscriptionRoute.openRouterMAI, true),
        (.openRouterGrok, false),
    ])
    func zeroDataRetentionIsSentPerRoute(route: TranscriptionRoute, zdr: Bool) async throws {
        let stub = StubHost(reply: .fixture("success"))
        stub.settings.route = route

        _ = try await stub.provider().transcribe(stub.request())

        let body = try #require(stub.requests.only).json()
        let provider = try #require(body["provider"] as? [String: Any])
        #expect(provider["zdr"] as? Bool == zdr)
    }

    @Test func maiFillerWordsAreKeptWhenOn() async throws {
        let stub = StubHost(reply: .fixture("success"))
        stub.settings.keepsFillerWords = true

        _ = try await stub.provider().transcribe(stub.request(terms: ["kotoba"]))

        let azure = try #require(stub.requests.only).json().azureOptions
        let enhancedMode = try #require(azure["enhancedMode"] as? [String: Any])
        #expect(enhancedMode["modelOptions"] as? [String: String] == ["transcribeStyle": "verbatim"])
    }

    @Test func settingsDefaultToMAIWithSpeechOptionsOff() {
        let settings = StubHost(reply: .status(200)).settings

        #expect(settings.route == .openRouterMAI)
        #expect(!settings.isGrokFormatOn)
        #expect(!settings.keepsFillerWords)
    }

    @Test func missingKeyNeedsSetupWithoutARequest() async {
        let stub = StubHost(reply: .fixture("success"))
        let provider = stub.provider(key: nil)

        await #expect(throws: ProviderError.needsSetup(provider: "OpenRouter", item: .key)) {
            try await provider.transcribe(stub.request())
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func keyStoreFailureOtherThanMissingIsRetryable() async {
        let stub = StubHost(reply: .fixture("success"))
        let provider = stub.provider(isKeyLocked: true)

        await #expect(throws: ProviderError.keyUnavailable) {
            try await provider.transcribe(stub.request())
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func warmUpSendsAHeadRequestToTheSameHost() async throws {
        let stub = StubHost(reply: .status(200))

        await stub.provider().warmUp()

        let sent = try #require(stub.requests.only)
        #expect(sent.method == "HEAD")
        #expect(sent.url == stub.baseURL.appending(path: "models/microsoft/mai-transcribe-2/endpoints"))
        #expect(sent.headers["Authorization"] == nil)
    }

    @Test func failedWarmUpIsSilent() async {
        let stub = StubHost(reply: .failure(.notConnectedToInternet))

        await stub.provider(key: nil).warmUp()

        #expect(stub.requests.count == 1)
    }

    // MARK: Response parsing

    /// The text as sent: the pipeline trims it.
    @Test func successReturnsTheTextAndUsage() async throws {
        let stub = StubHost(reply: .fixture("success"))

        let transcript = try await stub.provider().transcribe(stub.request())

        #expect(transcript.text == " Run make check, then open DictationPipeline.swift. ")
        #expect(transcript.usage.audio == .seconds(12.4))
        #expect(transcript.usage.cost == .reported(try #require(Decimal(string: "0.000344"))))
    }

    /// With the owner's own provider key (BYOK), `cost` is only OpenRouter's fee and
    /// `cost_details.upstream_inference_cost` is what the provider charged
    /// (https://openrouter.ai/docs/use-cases/usage-accounting); the fixture follows that page's fields. Without BYOK the
    /// upstream cost is the same money as `cost` (kotoba-bench-v1 rows had both equal), so it is not added.
    @Test func aBYOKAnswerCostsTheFeeAndTheProviderCharge() async throws {
        let stub = StubHost(reply: .fixture("success-byok"))

        let transcript = try await stub.provider().transcribe(stub.request())

        #expect(transcript.usage.cost == .reported(try #require(Decimal(string: "0.0001166"))))
    }

    /// BYOK without the provider's charge: the fee alone would look reported and far too low, so the list price.
    @Test func aBYOKAnswerWithoutTheProviderChargeIsEstimated() async throws {
        let stub = StubHost(
            reply: .raw(status: 200, body: #"{"text":"hi","usage":{"seconds":2,"is_byok":true,"cost":0.0000056}}"#))

        let transcript = try await stub.provider().transcribe(stub.request())

        #expect(transcript.usage.cost == .estimated(Decimal(20_000) / 360_000_000))
    }

    @Test func aNonBYOKAnswerCostsItsCost() async throws {
        let stub = StubHost(reply: .fixture("success-not-byok"))

        let transcript = try await stub.provider().transcribe(stub.request())

        #expect(transcript.usage.cost == .reported(try #require(Decimal(string: "0.0000556"))))
    }

    /// No `usage`: the recording's length, at the list price.
    @Test func successWithoutUsageEstimatesTheCost() async throws {
        let stub = StubHost(reply: .fixture("success-no-usage"))

        let transcript = try await stub.provider().transcribe(stub.request(duration: .milliseconds(9_200)))

        // 10 s billed (whole seconds) at $0.10 per hour.
        let usage = TranscriptionUsage(audio: .milliseconds(9_200), cost: .estimated(Decimal(100_000) / 360_000_000))
        #expect(transcript == Transcript(text: "hello", usage: usage, model: "microsoft/mai-transcribe-2"))
    }

    /// A usage field of another type (a cost sent as a string) loses only the reported cost: the text stays, and the
    /// recording's length is priced at the list price.
    @Test func aUsageBlockThatDoesNotParseKeepsTheText() async throws {
        let body = #"{"text": "hello", "usage": {"seconds": 9.2, "cost": "0.0003"}}"#
        let stub = StubHost(reply: .raw(status: 200, body: body))

        let transcript = try await stub.provider().transcribe(stub.request(duration: .milliseconds(9_200)))

        let usage = TranscriptionUsage(audio: .milliseconds(9_200), cost: .estimated(Decimal(100_000) / 360_000_000))
        #expect(transcript == Transcript(text: "hello", usage: usage, model: "microsoft/mai-transcribe-2"))
    }

    /// Recorded in kotoba-bench-v1 (Grok, a 19.9 s clip): OpenRouter bills an answer with no words. The pipeline
    /// decides it heard no speech; the provider keeps the cost.
    @Test func anEmptyAnswerKeepsItsUsage() async throws {
        let stub = StubHost(reply: .fixture("empty-text-billed"))
        stub.settings.route = .openRouterGrok

        let transcript = try await stub.provider().transcribe(stub.request())

        let cost = try #require(Decimal(string: "0.0005540000000004432"))
        #expect(
            transcript
                == Transcript(
                    text: "", usage: .init(audio: .seconds(19.944), cost: .reported(cost)),
                    model: "x-ai/grok-stt-1.0"))
    }

    /// The pipeline bounds a transcription by its audio's length; the connection's own limit must not cut it first.
    @Test func theConnectionOutlastsThePipelinesLongestBound() {
        let configuration = ProviderHTTP.sessionConfiguration(
            resourceTimeout: ProviderHTTP.transcriptionResourceTimeout)
        let longest = DictationPipeline.Settings.longestTranscription / .seconds(1)
        #expect(configuration.timeoutIntervalForResource > longest)
        #expect(ProviderHTTP.sessionConfiguration().timeoutIntervalForResource == 75)
    }

    /// The route sends nothing while it transcribes a long recording: the request's idle limit is the pipeline's
    /// bound for its audio, not the session's 30 s.
    @Test(arguments: [TranscriptionRoute.openRouterMAI, .xaiGrok])
    func aTranscriptionMayStayIdleAsLongAsItsBound(route: TranscriptionRoute) async throws {
        let stub = StubHost(reply: .fixture("success"))
        stub.settings.route = route

        _ = try await stub.provider().transcribe(stub.request(duration: .seconds(20 * 60)))

        #expect(try #require(stub.requests.only).timeout == 675)
    }

    @Test(arguments: [
        (StubReply.raw(status: 200, body: "<html>"), ProviderError.unreadableAnswer(status: 200)),
        (.fixture("error-401", status: 401), .auth(status: 401)),
        (.raw(status: 403, body: ""), .auth(status: 403)),
        (.fixture("error-429", status: 429, headers: ["Retry-After": "7"]), .rateLimited(retryAfter: .seconds(7))),
        (.fixture("error-429", status: 429), .rateLimited(retryAfter: nil)),
        (.raw(status: 408, body: ""), .server(status: 408)),
        (.fixture("error-502", status: 502), .server(status: 502)),
        (.raw(status: 503, body: ""), .server(status: 503)),
        (.fixture("error-400", status: 400), .rejected(status: 400, message: "Unsupported audio format")),
        (.fixture("error-402", status: 402), .noCredit),
        (.raw(status: 413, body: "Payload Too Large"), .rejected(status: 413, message: "Payload Too Large")),
        (.failure(.notConnectedToInternet), .offline),
        (.failure(.timedOut), .timedOut),
        (.failure(.networkConnectionLost), .offline),
        // A captive portal or a filtering proxy: the network is up, but the secure connection is refused.
        (.failure(.secureConnectionFailed), .connectionBlocked),
        (.failure(.serverCertificateUntrusted), .connectionBlocked),
    ])
    func failureMapsToProviderError(reply: StubReply, expected: ProviderError) async {
        let stub = StubHost(reply: reply)
        let provider = stub.provider()

        await #expect(throws: expected) {
            try await provider.transcribe(stub.request())
        }
    }

    /// The kept audio file was deleted outside kotoba: nothing is sent, and the same send fails the same way.
    @Test func aMissingAudioFileSendsNothing() async throws {
        let stub = StubHost(reply: .fixture("success"))
        let provider = stub.provider()
        var request = try stub.request()
        request.audio = request.audio.deletingLastPathComponent().appending(path: "gone-\(UUID().uuidString).flac")

        await #expect(throws: ProviderError.audioMissing) {
            try await provider.transcribe(request)
        }
        #expect(stub.requests.isEmpty)
    }
}
