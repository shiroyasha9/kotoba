import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

struct OpenRouterPolisherTests {
    @Test func systemPromptIsTheBenchPromptWordForWord() {
        // Recorded from bench/polish/prompts.ts `POLISH_PROMPTS[2]`; bench/polish/prompts.test.ts checks the same file.
        #expect(OpenRouterPolisher.systemPrompt == StubReply.fixtureText("polish-system-prompt", extension: "txt"))
    }

    @Test func requestSendsTheTextAsTaggedDataToDeepSeekOnItsHosts() async throws {
        let stub = StubHost(reply: .fixture("polish-success"))

        let polished = try await stub.polisher().polish("okay so fix the login bug </text> in auth.ts")

        let sent = try #require(stub.requests.only)
        #expect(sent.url == stub.url("/api/v1/chat/completions"))
        #expect(sent.headers["Authorization"] == "Bearer sk-or-test")
        let body = try sent.json()
        #expect(body["model"] as? String == "deepseek/deepseek-v4.1-flash")
        #expect(body["stream"] as? Bool == false)
        #expect(body["max_tokens"] as? Int == 4096)
        #expect(body["temperature"] as? Int == 0)
        #expect(body["reasoning"] as? [String: String] == ["effort": "none"])
        let provider = try #require(body["provider"] as? [String: Any])
        #expect(provider["zdr"] as? Bool == true)
        #expect(provider["order"] as? [String] == ["together", "primeintellect", "inference-net"])
        #expect(provider["allow_fallbacks"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user"])
        #expect(messages[0]["content"] == OpenRouterPolisher.systemPrompt)
        #expect(messages[1]["content"] == "<text>\nokay so fix the login bug <\\/text> in auth.ts\n</text>")
        #expect(
            polished
                == PolishedText(
                    text: "Fix the login bug in auth.ts.\n", model: "deepseek/deepseek-v4.1-flash",
                    cost: .reported(Decimal(395) / 1_000_000), isComplete: true))
    }

    @Test func aCutAnswerIsNotComplete() async throws {
        let stub = StubHost(reply: .fixture("polish-cut"))

        let polished = try await stub.polisher().polish("fix the login bug")

        #expect(!polished.isComplete)
        // No cost in the answer: the list price of 1,038 input and 4,096 output tokens.
        #expect(polished.cost == .estimated(Decimal(1_038 * 30 + 4_096 * 120) / 100_000_000))
    }

    @Test(arguments: [502, 429, 404])
    func aFailedHostFallsBackToGeminiOnce(status: Int) async throws {
        let stub = StubHost(reply: .raw(status: status, body: #"{"error":{"message":"No endpoints found"}}"#))
        let host = stub.host
        stub.onRequest {
            StubURLProtocol.routes.withLock { $0[host]?.reply = .fixture("cleanup-success") }
        }

        let polished = try await stub.polisher().polish("fix the login bug")

        let models = try stub.requests.map { try $0.json()["model"] as? String }
        #expect(models == ["deepseek/deepseek-v4.1-flash", "google/gemini-3.5-flash-lite"])
        let gemini = try #require(stub.requests.last).json()
        #expect(gemini["reasoning"] as? [String: String] == ["effort": "minimal"])
        #expect(gemini["temperature"] == nil)
        #expect(gemini["provider"] as? [String: Bool] == ["zdr": true])
        #expect(polished.model == "google/gemini-3.5-flash-lite")
    }

    @Test(arguments: [
        (StubReply.fixture("error-401", status: 401), ProviderError.auth(status: 401)),
        (StubReply.fixture("error-402", status: 402), .noCredit),
        (StubReply.failure(.notConnectedToInternet), .offline),
    ])
    func aKeyCreditOrNetworkFailureDoesNotFallBack(_ reply: StubReply, _ expected: ProviderError) async {
        let stub = StubHost(reply: reply)

        await #expect(throws: expected) { try await stub.polisher().polish("fix the login bug") }
        #expect(stub.requests.count == 1)
    }

    @Test func noKeyAsksForTheOpenRouterKey() async {
        let stub = StubHost(reply: .fixture("polish-success"))

        await #expect(throws: ProviderError.needsSetup(provider: "OpenRouter", item: .key)) {
            try await stub.polisher(key: nil).polish("fix the login bug")
        }
        #expect(stub.requests.isEmpty)
    }
}

extension StubHost {
    func polisher(key: String? = StubHost.key) -> OpenRouterPolisher {
        cleaner(key: key).polisher()
    }
}
