import Foundation
import KotobaCore

/// The app's one `TranscriptionProvider`: it reads the settings once per request and sends the request down the
/// chosen route, so a route switched in the menu applies to the next dictation. Each provider keeps its own
/// long-lived URLSession and Keychain key.
public final class TranscriptionRouter: TranscriptionProvider {
    private let settings: TranscriptionSettings
    private let openRouter: OpenRouterProvider
    private let xai: XAIProvider
    private let azure: AzureProvider

    /// `keys` gives the key source for each provider account; the app passes its `KeyVault`'s sources. It is called
    /// once per account here, so each source keeps its cache.
    public convenience init(settings: TranscriptionSettings, keys: (ProviderAccount) -> any APIKeySource) {
        self.init(
            settings: settings,
            openRouter: OpenRouterProvider(apiKey: keys(.openRouter)),
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

    public var hasPrimer: Bool {
        client(for: settings.route.account).hasPrimer
    }

    public func prime(language: Locale.Language) async -> Transcript? {
        let options = settings.routeOptions
        return await client(for: options.route.account).prime(options, language: language)
    }

    /// A request that names a route's model (History's "Transcribe Again With") goes down that route once; the
    /// owner's choice stays.
    public func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        var options = settings.routeOptions
        if let route = request.model.flatMap(TranscriptionRoute.init(rawValue:)) {
            options.route = route
        }
        return try await client(for: options.route.account).transcribe(request, options)
    }

    /// Checks `key` for `account` with one free request on that provider's connection (no audio, no cost). Used
    /// when a key is saved (onboarding, the Speech pane); the dictation path never calls it.
    public func checkKey(_ key: String, for account: ProviderAccount) async -> KeyCheck {
        await client(for: account).checkKey(key, settings.routeOptions)
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
    /// `TranscriptionProvider.hasPrimer` for this provider's routes.
    var hasPrimer: Bool { get }
    /// `TranscriptionProvider.prime` on this route.
    func prime(_ options: TranscriptionSettings.RouteOptions, language: Locale.Language) async -> Transcript?
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
