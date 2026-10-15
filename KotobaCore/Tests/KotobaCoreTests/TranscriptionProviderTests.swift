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
        (.rejected(status: 400, message: "Unsupported audio"), .permanent),
        (.noCredit, .needsSetup),
        (.emptyTranscript, .permanent),
    ])
    func eachErrorHasOneWayToRecover(error: ProviderError, recovery: ProviderError.Recovery) {
        #expect(error.recovery == recovery)
    }

    @Test(arguments: [
        (ProviderError.emptyTranscript, RejectReason?.some(.emptyTranscript)),
        (.noCredit, nil),
        (.rejected(status: 400, message: "Unsupported audio"), .other),
        (.offline, nil),
        (.auth(status: 401), nil),
    ])
    func onlyAPermanentErrorHasARejectReason(error: ProviderError, reason: RejectReason?) {
        #expect(error.rejectReason == reason)
    }
}
