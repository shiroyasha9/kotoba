import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

/// Grok direct from xAI, through the router with `route = .xaiGrok`. Fixture shapes from the xAI STT reference.
struct XAIProviderTests {
    @Test func requestIsMultipartWithOptionsBeforeTheFile() async throws {
        let stub = StubHost(reply: .fixture("xai-success"))
        stub.settings.route = .xaiGrok

        _ = try await stub.provider().transcribe(stub.request(terms: ["DictationPipeline", "src/main.swift"]))

        let sent = try #require(stub.requests.only)
        #expect(sent.url == stub.url("/v1/stt"))
        #expect(sent.method == "POST")
        #expect(sent.headers["Authorization"] == "Bearer sk-or-test")
        #expect(sent.headers["Content-Type"] == "multipart/form-data; boundary=test-boundary")
        #expect(sent.body == StubReply.fixtureData("request-xai", extension: "multipart"))
    }

    @Test func grokOptionsAreSentAsTrueFalseFields() async throws {
        let stub = StubHost(reply: .fixture("xai-success"))
        stub.settings.route = .xaiGrok
        stub.settings.isGrokFormatOn = true
        stub.settings.keepsGrokFillerWords = true

        _ = try await stub.provider().transcribe(stub.request())

        let body = String(bytes: try #require(stub.requests.only).body, encoding: .utf8) ?? ""
        #expect(body.contains("name=\"format\"\r\n\r\ntrue\r\n"))
        #expect(body.contains("name=\"filler_words\"\r\n\r\ntrue\r\n"))
        #expect(!body.contains("name=\"keyterm\""))
    }

    @Test func successReturnsTheTextDurationAndRoute() async throws {
        let stub = StubHost(reply: .fixture("xai-success"))
        stub.settings.route = .xaiGrok

        let transcript = try await stub.provider().transcribe(stub.request())

        #expect(
            transcript
                == Transcript(
                    // 8.4 s at $0.10 per hour: xAI reports no cost, and Grok bills the exact length.
                    text: " The balance is $167,983.15. ",
                    usage: .init(audio: .seconds(8.4), cost: .estimated(Decimal(84_000) / 360_000_000)),
                    model: "xai-direct/grok-stt"))
    }

    /// The pipeline decides it heard no speech; the provider keeps the cost of the 1 s xAI counted.
    @Test func aRequestThatNamesARouteGoesThereWhateverTheChoice() async throws {
        let stub = StubHost(reply: .fixture("xai-success"))
        stub.settings.route = .openRouterMAI
        var request = try stub.request()
        request.model = TranscriptionRoute.xaiGrok.rawValue

        let transcript = try await stub.provider().transcribe(request)

        #expect(try #require(stub.requests.only).url == stub.url("/v1/stt"))
        #expect(transcript.model == "xai-direct/grok-stt")
        #expect(stub.settings.route == .openRouterMAI)
    }

    @Test func anEmptyAnswerKeepsItsUsage() async throws {
        let stub = StubHost(reply: .raw(status: 200, body: #"{"text":"  ","language":"en","duration":1.0}"#))
        stub.settings.route = .xaiGrok

        let transcript = try await stub.provider().transcribe(stub.request())

        #expect(transcript.text == "  ")
        #expect(transcript.usage == .init(audio: .seconds(1), cost: .estimated(Decimal(10_000) / 360_000_000)))
    }

    /// A `duration` of another type loses only the count: the text stays, and the recording's length counts.
    @Test func aDurationThatDoesNotParseKeepsTheText() async throws {
        let stub = StubHost(reply: .raw(status: 200, body: #"{"text":"hello","duration":"1.0"}"#))
        stub.settings.route = .xaiGrok

        let transcript = try await stub.provider().transcribe(stub.request(duration: .seconds(2)))

        #expect(transcript.text == "hello")
        #expect(transcript.usage.audio == .seconds(2))
    }

    @Test func missingXAIKeyNamesTheProviderToSetUp() async {
        let stub = StubHost(reply: .fixture("xai-success"))
        stub.settings.route = .xaiGrok
        let provider = stub.provider(key: nil)

        await #expect(throws: ProviderError.needsSetup(provider: "xAI", item: .key)) {
            try await provider.transcribe(stub.request())
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func warmUpSendsAHeadRequestToTheEndpoint() async throws {
        let stub = StubHost(reply: .status(405))
        stub.settings.route = .xaiGrok

        await stub.provider().warmUp()

        let sent = try #require(stub.requests.only)
        #expect(sent.method == "HEAD")
        #expect(sent.url == stub.url("/v1/stt"))
    }

    @Test(arguments: [
        (
            StubReply.fixture("xai-error-400", status: 400),
            ProviderError.rejected(status: 400, message: "format requires language")
        ),
        (.raw(status: 401, body: #"{"error":"Incorrect API key provided"}"#), .auth(status: 401)),
        (.raw(status: 429, headers: ["Retry-After": "3"], body: ""), .rateLimited(retryAfter: .seconds(3))),
        (.raw(status: 500, body: ""), .server(status: 500)),
        (.failure(.notConnectedToInternet), .offline),
    ])
    func failureMapsToProviderError(reply: StubReply, expected: ProviderError) async {
        let stub = StubHost(reply: reply)
        stub.settings.route = .xaiGrok
        let provider = stub.provider()

        await #expect(throws: expected) {
            try await provider.transcribe(stub.request())
        }
    }
}
