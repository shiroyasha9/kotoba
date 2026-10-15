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
        await client(for: options.route).warmUp(options)
    }

    public func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        let options = settings.routeOptions
        return try await client(for: options.route).transcribe(request, options)
    }

    private func client(for route: TranscriptionRoute) -> any RouteClient {
        switch route {
        case .openRouterMAI, .openRouterGrok: openRouter
        case .xaiGrok: xai
        case .azureMAI: azure
        }
    }
}

/// One provider's HTTP client. The router passes the route options in, so the request body and the returned
/// `Transcript.model` always agree.
protocol RouteClient: Sendable {
    func warmUp(_ options: TranscriptionSettings.RouteOptions) async
    func transcribe(
        _ request: TranscriptionRequest,
        _ options: TranscriptionSettings.RouteOptions
    ) async throws -> Transcript
}
