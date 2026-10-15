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
        ("", nil),
    ])
    func azureEndpointMustBeAnHTTPSURL(text: String, expected: String?) {
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
        #expect(TranscriptionRoute.xaiGrok.note == "Untested live")
        #expect(TranscriptionRoute.azureMAI.note == "Untested live")
        #expect(TranscriptionRoute.openRouterGrok.note == "No zero-data-retention route")
        #expect(TranscriptionRoute.openRouterMAI.note == nil)
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
        stub.settings.azureEndpoint = stub.url("").absoluteString

        let transcript = try await stub.provider().transcribe(stub.request())

        #expect(try #require(stub.requests.only).url?.path() == path)
        #expect(transcript.model == route.rawValue)
    }

    @Test func theRouterAndThePaneShareOneEndpointRule() {
        #expect(TranscriptionSettings.azureEndpointURL("https://a.cognitiveservices.azure.com") != nil)
        #expect(TranscriptionSettings.azureEndpointURL("http://a.cognitiveservices.azure.com") == nil)
        #expect(TranscriptionSettings.azureEndpointURL("https://") == nil)
    }

    @Test func eachChangeIsAnnouncedWithWhatChanged() async {
        let settings = TranscriptionSettings.inMemory()
        let changes = Mutex<[TranscriptionSettings.Change]>([])
        let observer = NotificationCenter.default.addObserver(
            forName: TranscriptionSettings.didChange, object: nil, queue: nil
        ) { note in
            if let change = note.object as? TranscriptionSettings.Change { changes.withLock { $0.append(change) } }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        settings.azureEndpoint = "https://a.cognitiveservices.azure.com"
        settings.route = .azureMAI
        settings.isGrokFormatOn = true
        settings.cleanupModel = .claudeHaiku

        // Other tests running in parallel post too; only these four are checked, in order.
        #expect(
            changes.withLock { $0 }.filter { [.azureEndpoint, .route, .grokOptions, .cleanupModel].contains($0) }
                .suffix(4) == [.azureEndpoint, .route, .grokOptions, .cleanupModel])
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
}
