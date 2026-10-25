import Foundation
import KotobaCore
import Synchronization

/// The app's one `TranscriptionProvider`: it reads the settings once per request and sends the request down the
/// chosen route, so a route switched in the menu applies to the next dictation. Each provider keeps its own
/// long-lived URLSession and Keychain key.
public final class TranscriptionRouter: TranscriptionProvider {
    private let settings: TranscriptionSettings
    private let openRouter: OpenRouterProvider
    private let xai: XAIProvider
    private let azure: AzureProvider
    /// Which accounts are out of credit, as this router's requests and its cleaner's found.
    public let credit = AccountCredit()

    /// `keys` gives the key source for each provider account; the app passes its `KeyVault`'s sources. It is called
    /// once per account here, so each source keeps its cache. `copies` makes the Ogg Opus upload copy of a recording
    /// that has none (`OpenRouterProvider`).
    public convenience init(
        settings: TranscriptionSettings, keys: (ProviderAccount) -> any APIKeySource, copies: any UploadCopyEncoder
    ) {
        self.init(
            settings: settings,
            openRouter: OpenRouterProvider(apiKey: keys(.openRouter), copies: copies),
            xai: XAIProvider(apiKey: keys(.xai)),
            azure: AzureProvider(apiKey: keys(.azure))
        )
    }

    init(settings: TranscriptionSettings, openRouter: OpenRouterProvider, xai: XAIProvider, azure: AzureProvider) {
        self.settings = settings
        self.openRouter = openRouter
        self.xai = xai
        self.azure = azure
    }

    /// Warms only the current route: its connection and its key.
    public func warmUp() async {
        let options = settings.routeOptions
        await client(for: options.route.account).warmUp(options)
    }

    public var sendsUploadCopy: Bool { settings.route.takesOggOpus }

    public var hasPrimer: Bool {
        let route = settings.route
        return client(for: route.account).hasPrimer(route)
    }

    public func prime(language: Locale.Language, size: PrimerSize) async -> Transcript? {
        let options = settings.routeOptions
        let client = client(for: options.route.account)
        guard client.hasPrimer(options.route) else { return nil }
        return await client.prime(options, language: language, size: size)
    }

    /// How many primer bodies the OpenRouter client built, for the tests: each is built once and kept.
    var primerBodyBuilds: Int { openRouter.primerBodies.builds }  // Silent bodies only.
    /// The bytes of primer bodies the OpenRouter client keeps, for the tests.
    var keptPrimerBytes: Int { openRouter.primerBodies.keptBytes }

    /// A request that names a route's model (History's "Transcribe Again With") goes down that route once; the
    /// owner's choice stays.
    public func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        var options = settings.routeOptions
        if let route = request.model.flatMap(TranscriptionRoute.init(rawValue:)) {
            options.route = route
        }
        let account = options.route.account
        return try await credit.tracking(account) { try await client(for: account).transcribe(request, options) }
    }

    /// Checks `key` for `account` with one free request on that provider's connection (no audio, no cost). Used
    /// when a key is saved (onboarding, the Speech pane); the dictation path never calls it.
    /// A check that finds no credit marks the account (`credit`); a valid one leaves the mark, as OpenRouter's check
    /// reads the key's own limit, not the account's balance.
    public func checkKey(_ key: String, for account: ProviderAccount) async -> KeyCheck {
        let result = await client(for: account).checkKey(key, settings.routeOptions)
        if result == .noCredit { credit.ranOut(account) }
        return result
    }

    /// Cleanup and Polish on OpenRouter with `apiKey`, on this router's settings: their answers mark OpenRouter's credit
    /// in `credit`, as a transcript does.
    public func cleaner(apiKey: any APIKeySource) -> OpenRouterCleaner {
        OpenRouterCleaner(apiKey: apiKey, settings: settings, credit: credit)
    }

    /// The one place that maps a provider to its client; a route reaches it through `TranscriptionRoute.account`.
    private func client(for account: ProviderAccount) -> any RouteClient {
        switch account {
        case .openRouter: openRouter
        case .xai: xai
        case .azure: azure
        }
    }
}

/// One provider's HTTP client. The router passes the route options in, so the request body and the returned
/// `Transcript.model` always agree.
protocol RouteClient: Sendable {
    func warmUp(_ options: TranscriptionSettings.RouteOptions) async
    /// Checks `key` with the provider's free key-info request; `options` carries the Azure endpoint.
    func checkKey(_ key: String, _ options: TranscriptionSettings.RouteOptions) async -> KeyCheck
    func transcribe(
        _ request: TranscriptionRequest,
        _ options: TranscriptionSettings.RouteOptions
    ) async throws -> Transcript
    /// `TranscriptionProvider.hasPrimer` for `route`, one of this provider's routes.
    func hasPrimer(_ route: TranscriptionRoute) -> Bool
    /// `TranscriptionProvider.prime` on this route.
    func prime(_ options: TranscriptionSettings.RouteOptions, language: Locale.Language, size: PrimerSize) async
        -> Transcript?
}

/// Which provider accounts are out of credit, as the requests found: a dictation, a cleanup, a Polish or a key check
/// refused for no credit marks its account, and the next answer from that account clears the mark. Only
/// KotobaProviders knows the account of a request, so the fact lives here, beside the router that sends it. Kept in
/// memory: launch's retry of the saved dictations finds it again, and a mark kept on disk would outlive credit added
/// while kotoba was closed. Requests that overlap (segments, a retry run, a cleanup) mark in the order their answers
/// come: a late answer to a request sent before a refusal clears the mark until the next request sets it again.
public final class AccountCredit: Sendable {
    private let marked = Mutex<(accounts: Set<ProviderAccount>, changes: Int)>(([], 0))
    private let continuation: AsyncStream<Void>.Continuation
    /// Each change of the marks, none for a request that leaves them as they were; only the newest is kept. One
    /// reader: `SetupFlow`, which reads Readiness again.
    public let changes: AsyncStream<Void>

    init() {
        (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// The last request to `account` found no credit, and none worked since.
    public func isOut(_ account: ProviderAccount) -> Bool {
        marked.withLock { $0.accounts.contains(account) }
    }

    /// Runs a billed request to `account` (a transcription, a cleanup, a Polish) and marks what its answer says: an
    /// answer means credit, a refusal for no credit means none, any other failure says nothing.
    func tracking<Answer>(_ account: ProviderAccount, _ request: () async throws -> Answer) async throws -> Answer {
        do {
            let answer = try await request()
            worked(account)
            return answer
        } catch ProviderError.noCredit {
            ranOut(account)
            throw ProviderError.noCredit
        }
    }

    /// A request to `account` was refused for no credit.
    func ranOut(_ account: ProviderAccount) {
        update { $0.insert(account).inserted }
    }

    /// `account` answered a billed request, so it has credit.
    func worked(_ account: ProviderAccount) {
        update { $0.remove(account) != nil }
    }

    /// Test seam: the changes announced so far.
    var changeCount: Int { marked.withLock(\.changes) }

    /// `change` returns whether it changed the marks; only then is it counted and announced.
    private func update(_ change: (inout Set<ProviderAccount>) -> Bool) {
        let isChanged = marked.withLock { marked in
            guard change(&marked.accounts) else { return false }
            marked.changes += 1
            return true
        }
        if isChanged { continuation.yield() }
    }
}

/// What a key check found.
public enum KeyCheck: Sendable, Equatable {
    /// The provider accepted the key.
    case valid
    /// The provider did not accept the key.
    case invalid
    /// The key works but has no credit left.
    case noCredit
    /// No answer: offline, or the provider failed. The key stays saved; the first dictation tells.
    case unreachable
    /// Azure only: the key cannot be checked before the endpoint is set.
    case needsEndpoint
}
