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
    /// The page's "Advanced…" sheet is open: the page's button, the endpoint warning, or another window
    /// (`MainWindowController.showOtherSpeechServices`, onboarding's “Use xAI or Azure Instead…”).
    var isAdvancedShown = false
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

/// The speech service and its key; the direct routes, the Azure endpoint, other keys and the Grok switches are in
/// "Advanced…" (docs/research/ui-redesign.md, "Page map").
private struct SpeechPane: View {
    @Bindable var model: SpeechSettingsModel

    private var account: ProviderAccount { model.route.account }

    /// The OpenRouter models, and a direct one while it is in use, so the page always shows the model that transcribes.
    private var routes: [TranscriptionRoute] {
        TranscriptionRoute.allCases.filter { !$0.isAdvanced || $0 == model.route }
    }

    var body: some View {
        PageForm {
            Section {
                PageHeader(page: .speech, summary: "The service that turns your speech into text, and your key for it.")
            }
            Section("Speech Model") {
                ForEach(routes, id: \.self) { RouteRow(model: model, route: $0) }
            }
            Section {
                // The section header names the provider, so the row says only "Key".
                KeyRow(account: account, label: "Key", model: model)
                // The endpoint is in "Advanced…", where Azure is chosen; without it no dictation reaches Azure.
                if model.route == .azureMAI && model.azureEndpoint.isEmpty {
                    PageRow(title: "Azure needs your endpoint", subtitle: "Until you add it, dictations wait.") {
                        SymbolTile(
                            systemImage: "exclamationmark.triangle", tint: .orange, side: PageMetrics.rowTileSide)
                    } trailing: {
                        Button("Add Endpoint…") { model.isAdvancedShown = true }
                    }
                }
            } header: {
                Text("\(account.title) Key")
            } footer: {
                // The price with its link, as onboarding's; "Get a Key…" is in the key row while no key is saved.
                PageFooter(advanced: account == .openRouter ? showAdvanced : nil) {
                    PriceLine(route: model.route)
                }
            }
            // Cleanup and Rewrite run on OpenRouter whatever the speech model, so its key always has a place here: the
            // pill's “Add Key…” for a rewrite opens this page.
            if account != .openRouter {
                Section {
                    KeyRow(account: .openRouter, label: "Key", model: model)
                } header: {
                    Text("\(ProviderAccount.openRouter.title) Key for Cleanup and Rewrite")
                } footer: {
                    PageFooter(advanced: showAdvanced)
                }
            }
        }
        .sheet(isPresented: $model.isAdvancedShown) {
            SpeechAdvanced(model: model)
        }
    }

    private func showAdvanced() {
        model.isAdvancedShown = true
    }
}

/// The speech page's "Advanced…": the direct routes with their own keys, the Azure endpoint, the Grok switches and
/// the keys the page shows nowhere else.
struct SpeechAdvanced: View {
    @Bindable var model: SpeechSettingsModel

    /// The saved keys the page shows nowhere else: OpenRouter's has its own group while another service transcribes.
    private var otherSavedKeys: [ProviderAccount] {
        ProviderAccount.allCases.filter {
            $0 != model.route.account && $0 != .openRouter && model.keyChecks.isSaved($0)
        }
    }

    var body: some View {
        PageSheet(title: "Advanced Speech Settings") {
            Section {
                ForEach(TranscriptionRoute.allCases.filter(\.isAdvanced), id: \.self) {
                    RouteRow(model: model, route: $0)
                }
            } header: {
                Text("Other Services")
            } footer: {
                // Says the rows are choices (no check shows while OpenRouter transcribes), and where the chosen one's
                // key goes, apart from "Other Keys", the saved keys no service uses now (qa1-review, Speech).
                Text(
                    "Click a service to use your own xAI or Azure account in place of OpenRouter. The Speech page then "
                        + "shows its key.")
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
            if model.route.isGrok {
                Section("Grok") {
                    PageToggle(
                        title: "Format numbers and units", subtitle: "Writes “twenty dollars” as “$20”.",
                        isOn: $model.isGrokFormatOn)
                    PageToggle(
                        title: "Keep filler words", subtitle: "Pastes “um” and “uh” as you said them.",
                        isOn: $model.keepsGrokFillerWords)
                }
            }
            if !otherSavedKeys.isEmpty {
                Section("Other Keys") {
                    ForEach(otherSavedKeys, id: \.self) { other in
                        KeyRow(account: other, label: other.title, model: model)
                    }
                }
            }
        }
    }
}

/// A speech model: its name as the title and what it is in plain words under it (plan, Copy: model names stay visible).
private struct RouteRow: View {
    @Bindable var model: SpeechSettingsModel
    let route: TranscriptionRoute

    var body: some View {
        ChoiceRow(title: route.title, subtitle: route.summary, isChosen: model.route == route) {
            model.route = route
        }
    }
}

extension TranscriptionRoute {
    /// What the model is, in plain words: the line under its name on the Speech page.
    var summary: String {
        switch self {
        case .openRouterMAI: "Recommended: the most accurate in kotoba’s tests. OpenRouter keeps none of your audio."
        case .openRouterGrok: "Grok from xAI, which keeps your audio for 30 days."
        case .xaiGrok: "Grok with your own xAI key. xAI keeps your audio for 30 days."
        case .azureMAI: "MAI-Transcribe-2 from your own Azure Speech resource."
        }
    }
}

/// The Azure endpoint: edited in a draft and saved on Return, when the field loses focus, or when the sheet closes.
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
            // The sheet can close while the field has the focus (Done, Esc), which ends no editing: the draft is
            // saved then too, so a typed endpoint is never lost.
            .onDisappear { model.commitAzureEndpoint(draft) }
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
            KeyField(account: account, route: model.route, keyChecks: model.keyChecks)
        } label: {
            // The status is the row's subtitle, as System Settings shows a row's state under its name.
            Text(label)
            Group {
                if let status = model.keyChecks.status[account] {
                    KeyCheckLine(status: status, account: account)
                } else if model.keyChecks.isSaved(account) {
                    StatusLabel("Saved", systemImage: "checkmark.circle.fill", color: .green)
                } else {
                    // Where the owner pastes the key, as onboarding's Connect step (owner QA 1, Q3).
                    Button("Get a Key…") { NSWorkspace.shared.open(account.keysPage) }
                        .buttonStyle(.link)
                        // A subtitle's grey would take the link's colour.
                        .foregroundStyle(.link)
                }
            }
            // A row's subtitle style (`RowText`); only the symbol keeps the status colour.
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
            MainWindow.sheetSnapshot(named: "settings-speech-advanced") {
                SpeechAdvanced(
                    model: .sample(route: .openRouterGrok, azureEndpoint: "", savedKeys: [.openRouter, .xai]))
            },
            MainWindow.sheetSnapshot(named: "settings-speech-advanced-azure") {
                SpeechAdvanced(
                    model: .sample(
                        route: .azureMAI, azureEndpoint: "https://example.cognitiveservices.azure.com/",
                        savedKeys: [.openRouter, .azure]))
            },
            // One per message: the speech model's OpenRouter key, its xAI key, the OpenRouter key beside xAI, another key.
            removeKeyAlert("settings-speech-remove-key", .openRouter, route: .openRouterMAI),
            removeKeyAlert("settings-speech-remove-key-speech", .xai, route: .xaiGrok),
            removeKeyAlert("settings-speech-remove-key-cleanup", .openRouter, route: .xaiGrok),
            removeKeyAlert("settings-speech-remove-key-unused", .azure, route: .openRouterMAI),
        ]
    }

    /// The Remove confirmation as AppKit draws it, with KeyField's words: SwiftUI's `.alert` is a sheet on the window,
    /// which an offscreen run cannot show.
    private static func removeKeyAlert(_ name: String, _ account: ProviderAccount, route: TranscriptionRoute)
        -> Snapshot
    {
        Snapshot(name: name) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = KeyField.removeTitle(account)
            alert.informativeText = KeyField.removeMessage(account, route: route)
            alert.addButton(withTitle: "Remove").hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            alert.layout()
            return alert.window.contentView ?? NSView()
        }
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
