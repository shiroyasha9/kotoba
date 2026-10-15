import KotobaProviders
import Observation
import SwiftUI

extension SettingsPane {
    static func providers(_ model: ProvidersModel) -> Self {
        SettingsPane(id: .providers, title: "Providers", systemImage: "waveform") {
            AnyView(ProvidersPane(model: model))
        }
    }
}

/// The route, keys and provider options the Providers pane edits. The settings are read from and written to
/// `TranscriptionSettings` directly, so the pane and the menu always show the same values; the Keychain is reached
/// through the app's `KeyVault`.
@MainActor
@Observable
final class ProvidersModel {
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
    var azureEndpoint: String {
        get { read(settings.azureEndpoint) }
        set { write { settings.azureEndpoint = newValue } }
    }
    var cleanupModel: CleanupModel {
        get { read(settings.cleanupModel) }
        set { write { settings.cleanupModel = newValue } }
    }
    /// Accounts with a stored key.
    private(set) var savedKeys: Set<ProviderAccount>
    /// A Keychain write that failed, shown under the keys until the next write works.
    private(set) var keyError: String?
    /// Bumped on every settings change, from the pane or the menu, so the views that read a setting redraw.
    private var revision = 0

    @ObservationIgnored private let settings: TranscriptionSettings
    /// Nil only in a snapshot sample, which has no Keychain behind it.
    @ObservationIgnored private let vault: KeyVault?
    @ObservationIgnored private var changes: (any NSObjectProtocol)?

    /// Keys are saved through `vault`, which the router reads and which announces each save for the retry of the
    /// dictations that waited for a key.
    convenience init(settings: TranscriptionSettings, vault: KeyVault) {
        let saved = ProviderAccount.allCases.filter { vault.hasKey(for: $0) }
        self.init(settings: settings, vault: vault, savedKeys: Set(saved))
    }

    /// Fixed values with no UserDefaults or Keychain behind them, so `make snapshots` gives the same image each run.
    static func sample(route: TranscriptionRoute, azureEndpoint: String) -> ProvidersModel {
        let settings = TranscriptionSettings.inMemory()
        settings.route = route
        settings.isGrokFormatOn = true
        settings.azureEndpoint = azureEndpoint
        return ProvidersModel(settings: settings, vault: nil, savedKeys: [.openRouter])
    }

    private init(settings: TranscriptionSettings, vault: KeyVault?, savedKeys: Set<ProviderAccount>) {
        self.settings = settings
        self.vault = vault
        self.savedKeys = savedKeys
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

    /// Whether the endpoint text is usable: empty (not set yet) or what the router accepts.
    var isAzureEndpointValid: Bool {
        azureEndpoint.trimmingCharacters(in: .whitespaces).isEmpty
            || TranscriptionSettings.azureEndpointURL(azureEndpoint) != nil
    }

    func saveKey(_ key: String, for account: ProviderAccount) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        changeKey(account) { try $0.save(key, for: account) }
    }

    func deleteKey(for account: ProviderAccount) {
        changeKey(account) { try $0.delete(for: account) }
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

    private func changeKey(_ account: ProviderAccount, _ change: (KeyVault) throws -> Void) {
        guard let vault else { return }
        do {
            try change(vault)
            keyError = nil
        } catch {
            keyError = "The Keychain refused the change (\(error))."
        }
        if vault.hasKey(for: account) { savedKeys.insert(account) } else { savedKeys.remove(account) }
    }
}

private struct ProvidersPane: View {
    @Bindable var model: ProvidersModel

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Route", selection: $model.route) {
                    ForEach(TranscriptionRoute.allCases, id: \.self) { route in
                        if let note = route.note {
                            Text("\(route.title) - \(note)").tag(route)
                        } else {
                            Text(route.title).tag(route)
                        }
                    }
                }
                if model.route.isGrok {
                    Toggle("Format numbers and units", isOn: $model.isGrokFormatOn)
                    Toggle("Keep filler words", isOn: $model.keepsGrokFillerWords)
                }
            }
            Section {
                ForEach(ProviderAccount.allCases, id: \.self) { account in
                    KeyRow(account: account, model: model)
                }
                if let error = model.keyError {
                    Text(error).foregroundStyle(.red)
                }
            } header: {
                Text("API keys")
            } footer: {
                Text("Keys are kept in your login keychain and sent only to their provider.")
            }
            Section {
                TextField(
                    "Endpoint", text: $model.azureEndpoint,
                    prompt: Text(verbatim: "https://<resource>.cognitiveservices.azure.com/"))
                if !model.isAzureEndpointValid {
                    Text("Use the https endpoint from the Azure portal (Keys and Endpoint).").foregroundStyle(.red)
                }
            } header: {
                Text("Azure Speech")
            } footer: {
                Text("A Speech resource in Central India had the lowest latency from India.")
            }
            Section("Cleanup") {
                Picker("Model", selection: $model.cleanupModel) {
                    ForEach(CleanupModel.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One provider's key: a secure field to replace it, and Remove (enabled when one is stored). A stored key is never shown.
private struct KeyRow: View {
    let account: ProviderAccount
    let model: ProvidersModel
    @State private var draft = ""

    var body: some View {
        LabeledContent(account.title) {
            HStack {
                SecureField(
                    "Key", text: $draft,
                    prompt: Text(model.savedKeys.contains(account) ? "Saved" : "Not set")
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(save)
                Button("Save", action: save).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                // On every row, so the fields line up; it works only when a key is stored.
                Button("Remove", role: .destructive) { model.deleteKey(for: account) }
                    .disabled(!model.savedKeys.contains(account))
            }
        }
    }

    private func save() {
        model.saveKey(draft, for: account)
        draft = ""
    }
}

@MainActor
extension SettingsPane {
    static func providerSnapshots() -> [Snapshot] {
        [
            SettingsWindow.snapshot(
                of: .providers(
                    .sample(route: .openRouterGrok, azureEndpoint: "")
                ),
                named: "settings-providers", height: 640),
            SettingsWindow.snapshot(
                of: .providers(.sample(route: .azureMAI, azureEndpoint: "http://example.com")),
                named: "settings-providers-invalid-endpoint"),
        ]
    }
}
