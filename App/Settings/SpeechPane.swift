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
    /// Nil only in a snapshot sample, which has no Keychain behind it.
    @ObservationIgnored private let vault: KeyVault?
    @ObservationIgnored private let sampleSavedKeys: Set<ProviderAccount>
    @ObservationIgnored private var changes: (any NSObjectProtocol)?

    /// Keys are saved through `vault`, which the router reads and which announces each save for the retry of the
    /// dictations that waited for a key. `checkKey` is `TranscriptionRouter.checkKey(_:for:)`.
    convenience init(
        settings: TranscriptionSettings,
        vault: KeyVault,
        checkKey: (@MainActor (String, ProviderAccount) async -> KeyCheck)? = nil
    ) {
        self.init(
            settings: settings, vault: vault, keyChecks: KeyChecks(vault: vault, checkKey: checkKey),
            sampleSavedKeys: [])
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
        return SpeechSettingsModel(
            settings: settings, vault: nil, keyChecks: .sample(keyStatus), sampleSavedKeys: savedKeys)
    }

    private init(
        settings: TranscriptionSettings,
        vault: KeyVault?,
        keyChecks: KeyChecks,
        sampleSavedKeys: Set<ProviderAccount>
    ) {
        self.settings = settings
        self.vault = vault
        self.keyChecks = keyChecks
        self.sampleSavedKeys = sampleSavedKeys
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

    /// Whether `account` has a stored key. Read after each save or removal, which change `keyChecks.status`.
    func isSaved(_ account: ProviderAccount) -> Bool {
        _ = keyChecks.status
        return vault?.hasKey(for: account) ?? sampleSavedKeys.contains(account)
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

    func saveKey(_ key: String, for account: ProviderAccount) {
        Task { await keyChecks.save(key, for: account) }
    }

    func deleteKey(for account: ProviderAccount) {
        keyChecks.remove(account)
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
        ProviderAccount.allCases.filter { $0 != account && model.isSaved($0) }
    }

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .speech)
            }
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
                    Text("OpenRouter may keep this audio. MAI-Transcribe-2 keeps none.")
                }
            }
            Section {
                // The section header names the provider, so the row says only "Key".
                KeyRow(account: account, label: "Key", model: model)
                HStack(spacing: 16) {
                    Button("Get a Key…") { NSWorkspace.shared.open(account.keysPage) }
                    Button("See Pricing…") { NSWorkspace.shared.open(account.pricingPage) }
                }
                .buttonStyle(.link)
            } header: {
                Text("\(account.title) Key")
            } footer: {
                // Only the recommended model has a known price; every model links to its price page above.
                if let price = PriceLine.text(for: model.route) {
                    Text(price)
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

/// One provider's key: a secure field to replace it, Remove, and what the pane knows about the saved key. A stored
/// key is never shown.
private struct KeyRow: View {
    let account: ProviderAccount
    let label: String
    let model: SpeechSettingsModel
    @State private var draft = ""

    private var isSaved: Bool { model.isSaved(account) }

    var body: some View {
        LabeledContent(label) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    SecureField("Key", text: $draft, prompt: Text(isSaved ? "Paste a new key" : "Paste your key"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit(save)
                    Button("Save", action: save).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    // Always shown, so the fields line up; it works only when a key is stored.
                    Button("Remove", role: .destructive) { model.deleteKey(for: account) }
                        .disabled(!isSaved)
                }
                if let status = model.keyChecks.status[account] {
                    KeyCheckLine(status: status, account: account)
                } else if isSaved {
                    StatusLabel("Saved", systemImage: "checkmark.circle.fill", color: .green)
                }
            }
        }
    }

    private func save() {
        model.saveKey(draft, for: account)
        draft = ""
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
                of: .speech(
                    .sample(
                        route: .azureMAI, azureEndpoint: "", savedKeys: [.azure],
                        keyStatus: [.azure: .checked(.invalid)])),
                named: "settings-speech-azure"),
        ]
    }
}
