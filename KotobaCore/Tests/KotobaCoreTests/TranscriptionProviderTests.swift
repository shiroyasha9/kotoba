import Testing

@testable import KotobaCore

struct TranscriptionProviderTests {
    @Test(arguments: [
        (ProviderError.offline, ProviderError.Recovery.transient),
        (.keyUnavailable, .transient),
        (.rateLimited(retryAfter: .seconds(5)), .transient),
        (.server(status: 503), .transient),
        (.auth(status: 401), .needsSetup),
        (.auth(status: nil), .needsSetup),
        (.needsSetup(provider: "Azure", item: .endpoint), .needsSetup),
        (.needsSetup(provider: "OpenRouter", item: .key), .needsSetup),
        (.rejected(status: 402, message: "Insufficient credits"), .permanent),
        (.emptyTranscript, .permanent),
    ])
    func eachErrorHasOneWayToRecover(error: ProviderError, recovery: ProviderError.Recovery) {
        #expect(error.recovery == recovery)
    }
}
