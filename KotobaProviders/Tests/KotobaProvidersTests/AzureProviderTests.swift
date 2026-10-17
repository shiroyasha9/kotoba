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
        #expect(sent.url?.host() == "\(stub.host).cognitiveservices.azure.com")
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
                    // 13 s billed (whole seconds) at $0.10 per hour: Azure reports no cost.
                    usage: .init(audio: .milliseconds(12_072), cost: .estimated(Decimal(130_000) / 360_000_000)),
                    model: "azure-direct/mai-transcribe-2"))
    }

    /// No phrases: the pipeline decides it heard no speech; the provider keeps the 2 s Azure bills.
    @Test func anEmptyAnswerKeepsItsUsage() async throws {
        let stub = StubHost(reply: .fixture("azure-empty"))
        stub.useAzure()

        let transcript = try await stub.provider().transcribe(stub.request())

        #expect(transcript.text.isEmpty)
        #expect(transcript.usage == .init(audio: .seconds(2), cost: .estimated(Decimal(20_000) / 360_000_000)))
    }

    @Test(arguments: [
        (
            StubReply.fixture("azure-error-400", status: 400),
            ProviderError.rejected(status: 400, message: "The format of input audio is not supported.")
        ),
        (.fixture("azure-error-401", status: 401), .auth(status: 401)),
        (.raw(status: 429, headers: ["Retry-After": "2"], body: ""), .rateLimited(retryAfter: .seconds(2))),
        (.raw(status: 503, body: ""), .server(status: 503)),
        (.raw(status: 503, headers: ["Retry-After": "5"], body: ""), .rateLimited(retryAfter: .seconds(5))),
        (.failure(.timedOut), .timedOut),
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
