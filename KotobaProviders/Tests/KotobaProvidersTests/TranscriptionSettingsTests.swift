import Foundation
import KotobaCore
import Synchronization
import Testing

@testable import KotobaProviders

struct TranscriptionSettingsTests {
    @Test func defaultsAreMAIViaOpenRouterNoAzureEndpointAndGemini() {
        let settings = TranscriptionSettings.inMemory()

        #expect(settings.route == .openRouterMAI)
        #expect(settings.azureEndpoint == "")
        #expect(settings.routeOptions.azureEndpoint == nil)
        #expect(settings.cleanupModel == .geminiFlashLite)
    }

    @Test func phaseOneModelSettingStillSelectsItsRoute() {
        let storage = MemorySettingsStorage()
        storage.set("x-ai/grok-stt-1.0", forKey: "openrouter.model")

        #expect(TranscriptionSettings(storage: storage).route == .openRouterGrok)
    }

    @Test(arguments: [
        ("https://kotoba-speech.cognitiveservices.azure.com/", "https://kotoba-speech.cognitiveservices.azure.com/"),
        (" https://kotoba-speech.cognitiveservices.azure.com ", "https://kotoba-speech.cognitiveservices.azure.com"),
        ("http://kotoba-speech.cognitiveservices.azure.com", nil),
        ("kotoba-speech.cognitiveservices.azure.com", nil),
        ("https://eastus.api.cognitive.microsoft.com/", "https://eastus.api.cognitive.microsoft.com/"),
        // Prefixes met while typing, and hosts that only look like Azure: the key must never go there.
        ("https://my", nil),
        ("https://myres.co", nil),
        ("https://myres.cognitiveservices.azure.com.example.com", nil),
        ("https://cognitiveservices.azure.com", nil),
        ("https://example.com", nil),
        ("", nil),
    ])
    func azureEndpointMustBeAnHTTPSAzureSpeechHost(text: String, expected: String?) {
        let settings = TranscriptionSettings.inMemory()
        settings.azureEndpoint = text

        #expect(settings.routeOptions.azureEndpoint?.absoluteString == expected)
    }

    @Test func providerAccountsKeepTheKeychainNamesAndHaveOneTitleEach() {
        #expect(ProviderAccount.allCases.map(\.rawValue) == ["openrouter", "xai", "azure"])
        #expect(ProviderAccount.allCases.map(\.title) == ["OpenRouter", "xAI", "Azure"])
    }

    @Test func eachProviderHasOneKeyAndDirectRoutesAreMarkedUntested() {
        #expect(TranscriptionRoute.allCases.map(\.account) == [.openRouter, .openRouter, .xai, .azure])
        #expect(TranscriptionRoute.openRouterGrok.note == "OpenRouter may keep audio")
        #expect(TranscriptionRoute.allCases.filter { $0.note != nil } == [.openRouterGrok])
        #expect(TranscriptionRoute.allCases.filter(\.isAdvanced) == [.xaiGrok, .azureMAI])
    }

    @Test(arguments: [
        (TranscriptionRoute.openRouterMAI, "/api/v1/audio/transcriptions"),
        (.openRouterGrok, "/api/v1/audio/transcriptions"),
        (.xaiGrok, "/v1/stt"),
        (.azureMAI, "/speechtotext/transcriptions:transcribe"),
    ])
    func routerSendsEachRouteToItsProvider(route: TranscriptionRoute, path: String) async throws {
        let reply: StubReply =
            switch route {
            case .openRouterMAI, .openRouterGrok: .fixture("success")
            case .xaiGrok: .fixture("xai-success")
            case .azureMAI: .fixture("azure-success")
            }
        let stub = StubHost(reply: reply)
        stub.settings.route = route
        stub.settings.azureEndpoint = stub.azureEndpoint

        let transcript = try await stub.provider().transcribe(stub.request())

        #expect(try #require(stub.requests.only).url?.path() == path)
        #expect(transcript.model == route.rawValue)
    }

    @Test func theRouterAndThePaneShareOneEndpointRule() {
        #expect(TranscriptionSettings.azureEndpointURL("https://a.cognitiveservices.azure.com") != nil)
        #expect(TranscriptionSettings.azureEndpointURL("https://a.example.com") == nil)
        #expect(TranscriptionSettings.azureEndpointURL("http://a.cognitiveservices.azure.com") == nil)
        #expect(TranscriptionSettings.azureEndpointURL("https://") == nil)
    }

    @Test func eachChangeIsAnnouncedWithWhatChanged() async {
        // A center of this test's own: tests running in parallel cannot post into it.
        let center = NotificationCenter()
        let settings = TranscriptionSettings.inMemory(notifications: center)
        let changes = Mutex<[TranscriptionSettings.Change]>([])
        let observer = center.addObserver(forName: TranscriptionSettings.didChange, object: nil, queue: nil) { note in
            if let change = note.object as? TranscriptionSettings.Change { changes.withLock { $0.append(change) } }
        }
        defer { center.removeObserver(observer) }

        settings.azureEndpoint = "https://a.cognitiveservices.azure.com"
        settings.route = .azureMAI
        settings.isGrokFormatOn = true
        settings.cleanupModel = .claudeHaiku

        #expect(changes.withLock { $0 } == [.azureEndpoint, .route, .grokOptions, .cleanupModel])
    }

    @Test func missingSetupNamesTheKeyFirstThenTheAzureEndpoint() {
        let settings = TranscriptionSettings.inMemory()
        settings.route = .azureMAI

        #expect(settings.missingSetup { _ in false } == .key)
        #expect(settings.missingSetup { $0 == .azure } == .endpoint)
        settings.azureEndpoint = "https://kotoba.cognitiveservices.azure.com/"
        #expect(settings.missingSetup { $0 == .azure } == nil)
        settings.route = .openRouterMAI
        #expect(settings.missingSetup { $0 == .azure } == .key)
        #expect(settings.missingSetup { $0 == .openRouter } == nil)
    }

    @Test func routeTitlesAreThePlainSpeechModelNames() {
        #expect(
            TranscriptionRoute.allCases.map(\.title) == [
                "MAI-Transcribe-2 via OpenRouter (Recommended)", "Grok via OpenRouter", "Grok via xAI",
                "MAI-Transcribe-2 via Azure",
            ])
    }

    @Test func menuTitlesDropTheRecommendation() {
        #expect(
            TranscriptionRoute.allCases.map(\.menuTitle) == [
                "MAI-Transcribe-2 via OpenRouter", "Grok via OpenRouter", "Grok via xAI", "MAI-Transcribe-2 via Azure",
            ])
    }

    @Test func eachAccountLinksToItsKeyAndCreditPages() {
        #expect(ProviderAccount.openRouter.keysPage.absoluteString == "https://openrouter.ai/settings/keys")
        #expect(ProviderAccount.openRouter.creditsPage.absoluteString == "https://openrouter.ai/settings/credits")
        #expect(
            ProviderAccount.openRouter.pricingPage.absoluteString == "https://openrouter.ai/microsoft/mai-transcribe-2")
        #expect(
            ProviderAccount.allCases.allSatisfy {
                [$0.keysPage, $0.creditsPage, $0.pricingPage].allSatisfy { $0.scheme == "https" }
            })
    }
}
