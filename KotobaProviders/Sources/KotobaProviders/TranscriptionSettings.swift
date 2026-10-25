import Foundation
import KotobaCore
import Synchronization

/// One provider's API key in the Keychain. The raw value is the Keychain account, so saved items stay valid.
public enum ProviderAccount: String, CaseIterable, Sendable {
    case openRouter = "openrouter"
    case xai
    case azure

    /// The provider's name in the menu, Settings and "Add your … key".
    public var title: String {
        switch self {
        case .openRouter: "OpenRouter"
        case .xai: "xAI"
        case .azure: "Azure"
        }
    }

    /// Where the owner creates a key ("Get a Key…").
    public var keysPage: URL {
        switch self {
        case .openRouter: Self.url("https://openrouter.ai/settings/keys")
        case .xai: Self.url("https://console.x.ai")
        case .azure: Self.url("https://portal.azure.com/#create/Microsoft.CognitiveServicesSpeechServices")
        }
    }

    /// Where the owner adds credit ("Add Credit…").
    public var creditsPage: URL {
        switch self {
        case .openRouter: Self.url("https://openrouter.ai/settings/credits")
        case .xai: Self.url("https://console.x.ai")
        case .azure: Self.url("https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview")
        }
    }

    /// The public price page for the provider's speech models, next to "a few cents per hour". All three answered
    /// a plain GET on 2026-10-15 (OpenRouter's model page shows the per-hour price).
    public var pricingPage: URL {
        switch self {
        case .openRouter: Self.url("https://openrouter.ai/microsoft/mai-transcribe-2")
        case .xai: Self.url("https://docs.x.ai/developers/models")
        case .azure: Self.url("https://azure.microsoft.com/en-us/pricing/details/speech/")
        }
    }

    private static func url(_ text: String) -> URL {
        guard let url = URL(string: text) else { preconditionFailure("constant URL \(text)") }
        return url
    }
}

/// One way to reach a speech model: the provider host plus the model. The menu and Settings list these.
public enum TranscriptionRoute: String, CaseIterable, Sendable {
    // The OpenRouter routes keep their OpenRouter slugs as raw values: stored `dictations.model` values and the
    // old "openrouter.model" setting stay valid.
    /// Default: best WER and term recall in kotoba-bench-v1 (docs/spec.md, "Further Notes").
    case openRouterMAI = "microsoft/mai-transcribe-2"
    case openRouterGrok = "x-ai/grok-stt-1.0"
    case xaiGrok = "xai-direct/grok-stt"
    case azureMAI = "azure-direct/mai-transcribe-2"

    /// The speech model's name wherever it shows (the Speech page, History's Transcribe Again With, Activity's spend).
    /// The recommendation is the Speech page's subtitle, not part of the name.
    public var title: String {
        switch self {
        case .openRouterMAI: "MAI-Transcribe-2 via OpenRouter"
        case .openRouterGrok: "Grok via OpenRouter"
        case .xaiGrok: "Grok via xAI"
        case .azureMAI: "MAI-Transcribe-2 via Azure"
        }
    }

    /// The direct routes: shown under "Advanced". They are built from the docs and not yet tested live.
    public var isAdvanced: Bool { self == .xaiGrok || self == .azureMAI }

    /// The provider account whose key this route uses. One key per provider.
    public var account: ProviderAccount {
        switch self {
        case .openRouterMAI, .openRouterGrok: .openRouter
        case .xaiGrok: .xai
        case .azureMAI: .azure
        }
    }

    public var isGrok: Bool { self == .openRouterGrok || self == .xaiGrok }

    /// OpenRouter routes only: sent as `provider.zdr`, so OpenRouter uses only endpoints that keep no data (spec
    /// story 40). Grok has no such endpoint there.
    var hasZeroDataRetention: Bool { self == .openRouterMAI }

    /// The route takes the Ogg Opus copy of a recording (`TranscriptionRequest.upload`) at the WER of the FLAC: MAI
    /// through OpenRouter, measured on 80 bench clips (2026-10-19). WebM and MP4 come back 400 there. The other routes
    /// send the FLAC until a bench run checks them.
    var takesOggOpus: Bool { self == .openRouterMAI }
}

/// The transcription and cleanup choices the owner makes in the menu or Settings, kept in UserDefaults. Every read
/// goes to UserDefaults, so any instance over the same defaults sees a change at once.
public final class TranscriptionSettings: Sendable {
    private enum Key {
        static let route = "transcription.route"
        /// Phase 1 kept the OpenRouter model here; its values are `TranscriptionRoute` raw values.
        static let legacyModel = "openrouter.model"
        // Phase 1 names, kept so the owner's toggles survive: the format switch is Grok only, the filler words switch is
        // every route's.
        static let grokFormat = "openrouter.grok.format"
        static let fillerWords = "openrouter.grok.fillerWords"
        static let azureEndpoint = "azure.endpoint"
        static let cleanupModel = "cleanup.model"
    }

    private let storage: any SettingsStorage
    private let notifications: NotificationCenter

    /// The app's standard UserDefaults, announcing changes on `NotificationCenter.default`.
    public convenience init() {
        self.init(storage: StandardUserDefaults())
    }

    init(storage: any SettingsStorage, notifications: NotificationCenter = .default) {
        self.storage = storage
        self.notifications = notifications
    }

    /// Settings kept in memory only, for snapshots, previews and tests: nothing reads or writes UserDefaults. A test
    /// passes a center of its own, so changes from tests running in parallel do not reach it.
    public static func inMemory(notifications: NotificationCenter = .default) -> TranscriptionSettings {
        TranscriptionSettings(storage: MemorySettingsStorage(), notifications: notifications)
    }

    /// Posted after any setting changes, on the instance's center (`NotificationCenter.default` in the app); `object`
    /// is the `Change`. The Speech pane redraws on it, and the app retries dictations that waited for an endpoint.
    public static let didChange = Notification.Name("tech.teensy.kotoba.TranscriptionSettings.didChange")

    public enum Change: Sendable {
        case route
        case speechOptions
        case azureEndpoint
        case cleanupModel
    }

    /// The values one request uses, read together.
    struct RouteOptions {
        var route: TranscriptionRoute
        var isGrokFormatOn: Bool
        var keepsFillerWords: Bool
        /// Nil when the setting is not an https URL.
        var azureEndpoint: URL?
    }

    var routeOptions: RouteOptions {
        RouteOptions(
            route: route, isGrokFormatOn: isGrokFormatOn, keepsFillerWords: keepsFillerWords,
            azureEndpoint: Self.azureEndpointURL(azureEndpoint))
    }

    /// MAI-Transcribe-2 through OpenRouter until the owner picks another route.
    public var route: TranscriptionRoute {
        get {
            (storage.string(forKey: Key.route) ?? storage.string(forKey: Key.legacyModel))
                .flatMap(TranscriptionRoute.init) ?? .openRouterMAI
        }
        set {
            storage.set(newValue.rawValue, forKey: Key.route)
            post(.route)
        }
    }

    /// Grok only: written-form numbers and units (xAI `format`). Off by default.
    public var isGrokFormatOn: Bool {
        get { storage.bool(forKey: Key.grokFormat) }
        set {
            storage.set(newValue, forKey: Key.grokFormat)
            post(.speechOptions)
        }
    }

    /// Every route: keep "um" and "uh" as said (MAI's `verbatim` style, xAI `filler_words`). Off by default, so MAI
    /// sends its `clean` style and Grok drops them.
    public var keepsFillerWords: Bool {
        get { storage.bool(forKey: Key.fillerWords) }
        set {
            storage.set(newValue, forKey: Key.fillerWords)
            post(.speechOptions)
        }
    }

    /// Azure direct only: the Speech resource's endpoint as the Azure portal shows it, e.g.
    /// "https://<resource>.cognitiveservices.azure.com/" (Microsoft's documented form for MAI-Transcribe). Empty
    /// until the owner sets it. A resource in Central India (Pune) had the lowest latency from the owner's network
    /// (docs/research/mai-routing.md).
    public var azureEndpoint: String {
        get { storage.string(forKey: Key.azureEndpoint) ?? "" }
        set {
            storage.set(newValue, forKey: Key.azureEndpoint)
            post(.azureEndpoint)
        }
    }

    /// The host endings of an Azure Speech endpoint: a resource's own domain, or the regional host. Checked on
    /// 2026-10-16: Microsoft's MAI-Transcribe and LLM Speech pages show only `<resource>.cognitiveservices.azure.com`
    /// (https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe,
    /// https://learn.microsoft.com/en-us/azure/ai-services/speech-service/llm-speech), and the Speech REST page adds
    /// `<region>.api.cognitive.microsoft.com` for resources without a custom domain
    /// (https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-speech-to-text-short). No Speech page
    /// shows `*.services.ai.azure.com` or `*.openai.azure.com`; add a form here only when a Speech doc shows it.
    static let azureSpeechDomains = [".cognitiveservices.azure.com", ".api.cognitive.microsoft.com"]

    /// `text` as an endpoint URL when it is https on an Azure Speech host, else nil. The key and the audio are sent
    /// there, so a half-typed host ("https://myres.co") or any other domain is refused. The router and the Speech
    /// pane both use this one rule.
    public static func azureEndpointURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.scheme == "https",
            let host = url.host()?.lowercased(),
            azureSpeechDomains.contains(where: { host.hasSuffix($0) && host.count > $0.count })
        else { return nil }
        return url
    }

    /// What the current route still needs before it can send, or nil when it is ready: its provider's key first,
    /// then (Azure direct only) the endpoint. `hasKey` answers for one provider account (the app's `KeyVault`).
    public func missingSetup(hasKey: (ProviderAccount) -> Bool) -> SetupItem? {
        missingSetup(for: route, hasKey: hasKey)
    }

    /// What `route` still needs before it can send, as `missingSetup(hasKey:)` says for the current route.
    public func missingSetup(for route: TranscriptionRoute, hasKey: (ProviderAccount) -> Bool) -> SetupItem? {
        if !hasKey(route.account) { return .key }
        if route == .azureMAI, Self.azureEndpointURL(azureEndpoint) == nil { return .endpoint }
        return nil
    }

    /// The model the cleanup hotkey uses.
    public var cleanupModel: CleanupModel {
        get { storage.string(forKey: Key.cleanupModel).flatMap(CleanupModel.init) ?? .recommended }
        set {
            storage.set(newValue.rawValue, forKey: Key.cleanupModel)
            post(.cleanupModel)
        }
    }

    private func post(_ change: Change) {
        notifications.post(name: Self.didChange, object: change)
    }
}

/// Where `TranscriptionSettings` keeps its values: UserDefaults in the app, a dictionary in tests (so test runs leave
/// no files in ~/Library/Preferences).
protocol SettingsStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    /// False when the key is not set.
    func bool(forKey key: String) -> Bool
    func set(_ value: Bool, forKey key: String)
}

/// Looks up `UserDefaults.standard` on each call, because `UserDefaults` is not `Sendable`.
private struct StandardUserDefaults: SettingsStorage {
    func string(forKey key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    func set(_ value: String, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
    func bool(forKey key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    func set(_ value: Bool, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
}

/// `SettingsStorage` in a dictionary: for `TranscriptionSettings.inMemory()` and the tests.
final class MemorySettingsStorage: SettingsStorage {
    private let strings = Mutex<[String: String]>([:])
    private let bools = Mutex<[String: Bool]>([:])

    func string(forKey key: String) -> String? { strings.withLock { $0[key] } }
    func set(_ value: String, forKey key: String) { strings.withLock { $0[key] = value } }
    func bool(forKey key: String) -> Bool { bools.withLock { $0[key] ?? false } }
    func set(_ value: Bool, forKey key: String) { bools.withLock { $0[key] = value } }
}
