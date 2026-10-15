import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

/// The free key check per provider (onboarding step 4, Speech pane S5). The two error fixtures were recorded from
/// free requests with fake keys on 2026-10-15 (`openrouter-error-user-not-found`, `xai-error-incorrect-key`).
struct KeyCheckTests {
    @Test func openRouterChecksTheKeyInfoEndpointWithTheGivenKey() async throws {
        let stub = StubHost(reply: .fixture("openrouter-key"))

        let result = await stub.provider(key: nil).checkKey("sk-or-new", for: .openRouter)

        #expect(result == .valid)
        let sent = try #require(stub.requests.only)
        #expect(sent.method == "GET")
        #expect(sent.url == stub.url("/api/v1/key"))
        #expect(sent.headers["Authorization"] == "Bearer sk-or-new")
    }

    @Test(arguments: [
        (StubReply.fixture("openrouter-key-spent"), KeyCheck.noCredit),
        (.fixture("openrouter-error-user-not-found", status: 401), .invalid),
        (.raw(status: 403, body: ""), .invalid),
        (.raw(status: 402, body: ""), .noCredit),
        (.raw(status: 503, body: ""), .unreachable),
        (.failure(.notConnectedToInternet), .unreachable),
        (.raw(status: 200, body: "<html>"), .unreachable),
    ])
    func openRouterAnswers(reply: StubReply, expected: KeyCheck) async {
        let stub = StubHost(reply: reply)

        #expect(await stub.provider().checkKey("sk-or-new", for: .openRouter) == expected)
    }

    @Test func xaiChecksItsApiKeyEndpoint() async throws {
        let stub = StubHost(reply: .fixture("xai-api-key"))

        let result = await stub.provider().checkKey("xai-new", for: .xai)

        #expect(result == .valid)
        let sent = try #require(stub.requests.only)
        #expect(sent.method == "GET")
        #expect(sent.url == stub.url("/v1/api-key"))
        #expect(sent.headers["Authorization"] == "Bearer xai-new")
    }

    @Test(arguments: [
        (StubReply.fixture("xai-error-incorrect-key", status: 400), KeyCheck.invalid),
        (.fixture("xai-api-key-team-blocked"), .noCredit),
        (.raw(status: 200, body: #"{"api_key_blocked":true,"api_key_disabled":false,"team_blocked":false}"#), .invalid),
        (.raw(status: 200, body: #"{"api_key_blocked":false,"api_key_disabled":true,"team_blocked":false}"#), .invalid),
        (.raw(status: 401, body: ""), .invalid),
        (.failure(.timedOut), .unreachable),
    ])
    func xaiAnswers(reply: StubReply, expected: KeyCheck) async {
        let stub = StubHost(reply: reply)

        #expect(await stub.provider().checkKey("xai-new", for: .xai) == expected)
    }

    @Test func azureAsksForATokenAtTheEndpoint() async throws {
        let stub = StubHost(reply: .raw(status: 200, body: "eyJhbGciOi.token"))
        stub.useAzure()

        let result = await stub.provider().checkKey("azure-new", for: .azure)

        #expect(result == .valid)
        let sent = try #require(stub.requests.only)
        #expect(sent.method == "POST")
        #expect(sent.url == URL(string: "\(stub.azureEndpoint)sts/v1.0/issueToken"))
        #expect(sent.headers["Ocp-Apim-Subscription-Key"] == "azure-new")
        #expect(sent.body.isEmpty)
    }

    @Test(arguments: [
        (StubReply.fixture("azure-error-401", status: 401), KeyCheck.invalid),
        (.raw(status: 403, body: ""), .noCredit),
        (.raw(status: 500, body: ""), .unreachable),
    ])
    func azureAnswers(reply: StubReply, expected: KeyCheck) async {
        let stub = StubHost(reply: reply)
        stub.useAzure()

        #expect(await stub.provider().checkKey("azure-new", for: .azure) == expected)
    }

    @Test func azureWithoutAnEndpointIsNotChecked() async {
        let stub = StubHost(reply: .raw(status: 200, body: "token"))

        #expect(await stub.provider().checkKey("azure-new", for: .azure) == .needsEndpoint)
        #expect(stub.requests.isEmpty)
    }
}
