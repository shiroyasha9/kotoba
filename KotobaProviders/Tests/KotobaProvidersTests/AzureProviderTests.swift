import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

/// MAI-Transcribe-2 direct from Azure, through the router with `route = .azureMAI`. Fixture shapes from the
/// Transcriptions - Transcribe REST reference (2025-10-15).
struct AzureProviderTests {
    @Test func requestGoesToTheEndpointWithDefinitionThenAudio() async throws {
        let stub = StubHost(reply: .fixture("azure-success"))
        stub.useAzure()

        _ = try await stub.provider().transcribe(stub.request(terms: ["DictationPipeline", "src/main.swift"]))

        let sent = try #require(stub.requests.only)
        #expect(sent.url?.host() == "speech.\(stub.host)")
        #expect(sent.url?.path() == "/speechtotext/transcriptions:transcribe")
        #expect(sent.url?.query() == "api-version=2025-10-15")
        #expect(sent.headers["Ocp-Apim-Subscription-Key"] == "sk-or-test")
        #expect(sent.headers["Authorization"] == nil)
        #expect(sent.headers["Content-Type"] == "multipart/form-data; boundary=test-boundary")
        #expect(sent.body == StubReply.fixtureData("request-azure", extension: "multipart"))
    }

    @Test func missingEndpointFailsWithoutARequest() async {
        let stub = StubHost(reply: .fixture("azure-success"))
        stub.settings.route = .azureMAI
        let provider = stub.provider()

        await #expect(throws: ProviderError.needsSetup(provider: "Azure", item: .endpoint)) {
            try await provider.transcribe(stub.request())
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func successReturnsTheCombinedPhraseAndDuration() async throws {
        let stub = StubHost(reply: .fixture("azure-success"))
        stub.useAzure()

        let transcript = try await stub.provider().transcribe(stub.request())

        #expect(
            transcript
                == Transcript(
                    text: "Run make check, then open DictationPipeline.swift.",
                    usage: .init(audio: .milliseconds(12_072), costUSD: nil), model: "azure-direct/mai-transcribe-2"))
    }

    @Test(arguments: [
        (StubReply.fixture("azure-empty"), ProviderError.emptyTranscript),
        (
            .fixture("azure-error-400", status: 400),
            .rejected(status: 400, message: "The format of input audio is not supported.")
        ),
        (.fixture("azure-error-401", status: 401), .auth(status: 401)),
        (.raw(status: 429, headers: ["Retry-After": "2"], body: ""), .rateLimited(retryAfter: .seconds(2))),
        (.raw(status: 503, body: ""), .server(status: 503)),
        (.failure(.timedOut), .offline),
    ])
    func failureMapsToProviderError(reply: StubReply, expected: ProviderError) async {
        let stub = StubHost(reply: reply)
        stub.useAzure()
        let provider = stub.provider()

        await #expect(throws: expected) {
            try await provider.transcribe(stub.request())
        }
    }
}
