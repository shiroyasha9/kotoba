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
        (.noAudio, .permanent),
        (.unreadableAnswer(status: 200), .permanent),
    ])
    func eachErrorHasOneWayToRecover(error: ProviderError, recovery: ProviderError.Recovery) {
        #expect(error.recovery == recovery)
    }

    @Test(arguments: [
        (ProviderError.emptyTranscript, RejectReason?.some(.emptyTranscript)),
        (.noAudio, .emptyTranscript),
        (.noCredit, nil),
        (.rejected(status: 400, message: "Unsupported audio"), .other),
        (.offline, nil),
        (.auth(status: 401), nil),
        (.unreadableAnswer(status: 200), .other),
    ])
    func onlyAPermanentErrorHasARejectReason(error: ProviderError, reason: RejectReason?) {
        #expect(error.rejectReason == reason)
    }

    /// A send that reached the route may have been billed; one that found no connection or no key was not.
    @Test(arguments: [
        (ProviderError.server(status: 503), true),
        (.unreadableAnswer(status: 200), true),
        (.rejected(status: 400, message: "Unsupported audio"), true),
        (.offline, false),
        (.rateLimited(retryAfter: nil), false),
        (.auth(status: 401), false),
        (.needsSetup(provider: "OpenRouter", item: .key), false),
        (.keyUnavailable, false),
        (.noAudio, false),
    ])
    func onlyASendThatReachedTheRouteUsesAnAttempt(error: ProviderError, usesAttempt: Bool) {
        #expect(error.usesAttempt == usesAttempt)
    }
}
