import Testing

@testable import KotobaProviders

/// The masked key a saved key field shows: the provider's prefix and the last four characters, never more. The keys
/// here use characters that `make privacy` does not take for a real key.
struct KeyMaskTests {
    @Test func anOpenRouterKeyKeepsItsPrefixAndLastFour() {
        #expect(KeyMask.text(of: "sk-or-v1-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxa1b2") == "sk-or-v1-…a1b2")
    }

    @Test func anXAIKeyKeepsItsPrefix() {
        #expect(KeyMask.text(of: "xai-test.test.test.test.test.0123") == "xai-…0123")
    }

    /// Azure keys are 32 hex characters with no prefix.
    @Test func aKeyWithoutAPrefixShowsOnlyItsLastFour() {
        #expect(KeyMask.text(of: "0123456789abcdef0123456789abcdef") == "…cdef")
    }

    /// A short key would show most of itself: only the prefix shows.
    @Test func aShortKeyHidesItsEnd() {
        #expect(KeyMask.text(of: "sk-or-test") == "sk-or-…")
        #expect(KeyMask.text(of: "abc") == "…")
    }

    @Test func spaceAroundTheKeyDoesNotCount() {
        #expect(KeyMask.text(of: "  sk-or-v1-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxa1b2\n") == "sk-or-v1-…a1b2")
    }
}
