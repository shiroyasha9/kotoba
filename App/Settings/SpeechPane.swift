import KotobaProviders
import Observation
import SwiftUI

extension Pane {
    static func speech(_ model: SpeechSettingsModel) -> Self {
        Pane(id: .speech) {
            AnyView(SpeechPane(model: model))
        }
    }
}

/// The speech model, its keys and its options, as the Speech pane edits them. The settings are read from and written
/// to `TranscriptionSettings` directly, so the pane and the menu always show the same values; keys go through
/// `KeyChecks` (save through the `KeyVault`, then the provider's free key check).
@MainActor
@Observable
final class SpeechSettingsModel {
    var route: TranscriptionRoute {
        get { read(settings.route) }
        set { write { settings.route = newValue } }
    }
    var isGrokFormatOn: Bool {
        get { read(settings.isGrokFormatOn) }
        set { write { settings.isGrokFormatOn = newValue } }
    }
    var keepsGrokFillerWords: Bool {
        get { read(settings.keepsGrokFillerWords) }
        set { write { settings.keepsGrokFillerWords = newValue } }
    }
    /// The stored endpoint. The pane writes it only through `commitAzureEndpoint`.
    var azureEndpoint: String { read(settings.azureEndpoint) }
    let keyChecks: KeyChecks
    /// Bumped on every settings change, from the pane or the menu, so the views that read a setting redraw.
    private var revision = 0

    @ObservationIgnored private let settings: TranscriptionSettings
    @ObservationIgnored private var changes: (any NSObjectProtocol)?

    /// Keys are saved through `vault`, which the router reads and which announces each save for the retry of the
    /// dictations that waited for a key. `checkKey` is `TranscriptionRouter.checkKey(_:for:)`.
    convenience init(
        settings: TranscriptionSettings,
        vault: KeyVault,
        checkKey: (@MainActor (String, ProviderAccount) async -> KeyCheck)? = nil
    ) {
        self.init(settings: settings, keyChecks: KeyChecks(vault: vault, checkKey: checkKey))
    }

    /// Fixed values with no UserDefaults or Keychain behind them, so `make snapshots` gives the same image each run.
    static func sample(
        route: TranscriptionRoute,
        azureEndpoint: String,
        savedKeys: Set<ProviderAccount> = [.openRouter],
        keyStatus: [ProviderAccount: KeyStatus] = [:]
    ) -> SpeechSettingsModel {
        let settings = TranscriptionSettings.inMemory(notifications: NotificationCenter())
        settings.route = route
        settings.isGrokFormatOn = true
        settings.azureEndpoint = azureEndpoint
        return SpeechSettingsModel(settings: settings, keyChecks: .sample(keyStatus, savedKeys: savedKeys))
    }

    private init(settings: TranscriptionSettings, keyChecks: KeyChecks) {
        self.settings = settings
        self.keyChecks = keyChecks
        changes = NotificationCenter.default.addObserver(
            forName: TranscriptionSettings.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision += 1 }
        }
    }

    isolated deinit {
        if let changes {
            NotificationCenter.default.removeObserver(changes)
        }
    }

    /// Writes `text` when it is empty or an Azure Speech endpoint the router accepts; returns false (and keeps the
    /// stored value) otherwise. Called on Return or when the field loses focus, never per keystroke, so a
    /// half-typed host never receives the key or the waiting audio.
    @discardableResult
    func commitAzureEndpoint(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard text.isEmpty || TranscriptionSettings.azureEndpointURL(text) != nil else { return false }
        guard text != settings.azureEndpoint else { return true }
        write { settings.azureEndpoint = text }
        return true
    }

    /// `value`, read so that a settings change redraws the view that asked for it.
    private func read<Value>(_ value: @autoclosure () -> Value) -> Value {
        _ = revision
        return value()
    }

    private func write(_ change: () -> Void) {
        change()
        revision += 1
    }
}

private struct SpeechPane: View {
    @Bindable var model: SpeechSettingsModel

    private var account: ProviderAccount { model.route.account }
    private var otherSavedKeys: [ProviderAccount] {
        ProviderAccount.allCases.filter { $0 != account && model.keyChecks.isSaved($0) }
    }

    var body: some View {
        Form {
            Section {
                Picker("Speech model", selection: $model.route) {
                    ForEach(TranscriptionRoute.allCases.filter { !$0.isAdvanced }, id: \.self) { route in
                        Text(route.title).tag(route)
                    }
                    Section("Advanced") {
                        ForEach(TranscriptionRoute.allCases.filter(\.isAdvanced), id: \.self) { route in
                            Text(route.title).tag(route)
                        }
                    }
                }
                if model.route.isGrok {
                    Toggle("Format numbers and units", isOn: $model.isGrokFormatOn)
                    Toggle("Keep filler words", isOn: $model.keepsGrokFillerWords)
                }
            } footer: {
                if model.route == .openRouterGrok {
                    Text("OpenRouter may keep this audio. With MAI-Transcribe-2 it keeps none.")
                }
            }
            Section {
                // The section header names the provider, so the row says only "Key".
                KeyRow(account: account, label: "Key", model: model)
            } header: {
                Text("\(account.title) Key")
            } footer: {
                // The links sit with the price under the box, as "Learn More" links do in System Settings. Only the
                // recommended model has a known price; every model links to its price page.
                VStack(alignment: .leading) {
                    if let price = PriceLine.text(for: model.route) {
                        Text(price)
                    }
                    HStack(spacing: 16) {
                        Button("Get a Key…") { NSWorkspace.shared.open(account.keysPage) }
                        Button("See Pricing…") { NSWorkspace.shared.open(account.pricingPage) }
                    }
                    .buttonStyle(.link)
                }
            }
            if model.route == .azureMAI {
                Section {
                    EndpointField(model: model)
                } header: {
                    Text("Azure Speech")
                } footer: {
                    Text("Use a Speech resource in the region nearest to you.")
                }
            }
            if !otherSavedKeys.isEmpty {
                Section {
                    DisclosureGroup("Other Keys") {
                        ForEach(otherSavedKeys, id: \.self) { other in
                            KeyRow(account: other, label: other.title, model: model)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The Azure endpoint: edited in a draft and saved on Return or when the field loses focus.
private struct EndpointField: View {
    let model: SpeechSettingsModel
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(model: SpeechSettingsModel) {
        self.model = model
        _draft = State(initialValue: model.azureEndpoint)
    }

    private var isDraftValid: Bool {
        let text = draft.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || TranscriptionSettings.azureEndpointURL(text) != nil
    }

    var body: some View {
        TextField("Endpoint", text: $draft, prompt: Text(verbatim: "https://<resource>.cognitiveservices.azure.com/"))
            .focused($isFocused)
            .onSubmit { model.commitAzureEndpoint(draft) }
            .onChange(of: isFocused) { _, isFocused in
                if !isFocused { model.commitAzureEndpoint(draft) }
            }
        if !isDraftValid {
            Text("Use the https endpoint from the Azure portal (Keys and Endpoint).").foregroundStyle(.red)
        }
    }
}

/// One provider's key: the shared key field (the masked key once saved), and what the pane knows about the saved key.
private struct KeyRow: View {
    let account: ProviderAccount
    let label: String
    let model: SpeechSettingsModel

    var body: some View {
        LabeledContent {
            KeyField(account: account, keyChecks: model.keyChecks)
        } label: {
            // The status is the row's subtitle, as System Settings shows a row's state under its name.
            Text(label)
            Group {
                if let status = model.keyChecks.status[account] {
                    KeyCheckLine(status: status, account: account)
                } else if model.keyChecks.isSaved(account) {
                    StatusLabel("Saved", systemImage: "checkmark.circle.fill", color: .green)
                }
            }
            .font(.callout)
            .controlSize(.small)
        }
    }
}

@MainActor
extension Pane {
    static func speechSnapshots() -> [Snapshot] {
        [
            MainWindow.snapshot(
                of: .speech(
                    .sample(route: .openRouterMAI, azureEndpoint: "", keyStatus: [.openRouter: .checked(.valid)])),
                named: "settings-speech"),
            MainWindow.snapshot(
                of: .speech(
                    .sample(
                        route: .openRouterGrok, azureEndpoint: "", savedKeys: [.openRouter, .xai],
                        keyStatus: [.openRouter: .checked(.noCredit)])),
                named: "settings-speech-grok"),
            MainWindow.snapshot(
                of: .speech(.sample(route: .openRouterMAI, azureEndpoint: "", savedKeys: [])),
                named: "settings-speech-no-key"),
            MainWindow.snapshot(
                of: .speech(
                    .sample(
                        route: .azureMAI, azureEndpoint: "", savedKeys: [.azure],
                        keyStatus: [.azure: .checked(.invalid)])),
                named: "settings-speech-azure"),
        ]
    }
}

extension ProviderAccount {
    /// A made-up key in the provider's format, for snapshots.
    var sampleKey: String {
        switch self {
        case .openRouter: "sk-or-v1-" + String(repeating: "0", count: 60) + "a1b2"
        case .xai: "xai-" + String(repeating: "0", count: 76) + "7f3c"
        case .azure: String(repeating: "0", count: 28) + "9d0e"
        }
    }
}
