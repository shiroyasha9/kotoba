import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

/// Audit #5: the output limit follows the text, and an answer cut at it is reported, never taken as whole.
struct OpenRouterChatTests {
    @Test(arguments: [
        (0, 2_048),
        // 6,000 bytes: 2,000 tokens, twice that plus 1,024 for reasoning.
        (6_000, 5_024),
        (30_000, 16_384),
    ])
    func theOutputLimitFollowsTheTextWithinBounds(bytes: Int, limit: Int) {
        #expect(ChatRequest.maxTokens(rewriting: String(repeating: "a", count: bytes), floor: 2_048) == limit)
    }

    @Test func aLongTranscriptGetsARoomierLimit() async throws {
        let stub = StubHost(reply: .fixture("cleanup-success"))
        let transcript = String(repeating: "run the migration on staging first ", count: 200)

        _ = try await stub.cleaner().clean(transcript, vocabulary: [], mode: .code)

        let body = try #require(stub.requests.only).json()
        #expect(body["max_tokens"] as? Int == ChatRequest.maxTokens(rewriting: transcript, floor: 2_048))
        #expect(body["max_tokens"] as? Int ?? 0 > 2_048)
    }

    @Test func aCutCleanupIsNotComplete() async throws {
        let stub = StubHost(reply: .fixture("cleanup-cut"))

        let cleaned = try await stub.cleaner().clean("can you open auth dot ts", vocabulary: [], mode: .code)

        #expect(!cleaned.isComplete)
        #expect(cleaned.cost == .reported(Decimal(52) / 10_000))
    }

    @Test func aWholeCleanupIsComplete() async throws {
        let stub = StubHost(reply: .fixture("cleanup-success"))

        #expect(try await stub.cleaner().clean("open auth dot ts", vocabulary: [], mode: .code).isComplete)
    }
}
