import KotobaProviders
import Observation
import SwiftUI

/// What kotoba knows about a key the owner just saved or removed. The Speech pane and onboarding share it, so both
/// show the same words for the same result.
enum KeyStatus: Equatable {
    case checking
    case checked(KeyCheck)
    case saveFailed
    case removeFailed
}

/// The save-then-check sequence of a key field: trim, save through the `KeyVault`, then one free key check. A newer
/// save or a removal while a check runs wins, so a slow answer never shows for a key that is gone.
@MainActor
@Observable
final class KeyChecks {
    private(set) var status: [ProviderAccount: KeyStatus] = [:]

    @ObservationIgnored private let saveKey: @MainActor (String, ProviderAccount) throws -> Void
    @ObservationIgnored private let removeKey: @MainActor (ProviderAccount) throws -> Void
    /// The router's free key check; nil saves without a check (snapshots).
    @ObservationIgnored private let checkKey: (@MainActor (String, ProviderAccount) async -> KeyCheck)?
    /// Bumped by each save and removal, so an older check's answer is dropped.
    @ObservationIgnored private var generation: [ProviderAccount: Int] = [:]

    /// `checkKey` is `TranscriptionRouter.checkKey(_:for:)`.
    convenience init(vault: KeyVault, checkKey: (@MainActor (String, ProviderAccount) async -> KeyCheck)?) {
        self.init(
            saveKey: { try vault.save($0, for: $1) }, removeKey: { try vault.delete(for: $0) }, checkKey: checkKey)
    }

    init(
        saveKey: @escaping @MainActor (String, ProviderAccount) throws -> Void,
        removeKey: @escaping @MainActor (ProviderAccount) throws -> Void,
        checkKey: (@MainActor (String, ProviderAccount) async -> KeyCheck)?
    ) {
        self.saveKey = saveKey
        self.removeKey = removeKey
        self.checkKey = checkKey
    }

    /// Fixed results with nothing behind them, for snapshots.
    static func sample(_ status: [ProviderAccount: KeyStatus]) -> KeyChecks {
        let checks = KeyChecks(saveKey: { _, _ in }, removeKey: { _ in }, checkKey: nil)
        checks.status = status
        return checks
    }

    /// Saves `draft` (trimmed) for `account`, then checks it. Returns false when nothing was saved: an empty draft,
    /// or a Keychain failure (then the status is `.saveFailed`).
    @discardableResult
    func save(_ draft: String, for account: ProviderAccount) async -> Bool {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        let current = bump(account)
        do {
            try saveKey(key, account)
        } catch {
            Log.app.error("Cannot save the \(account.rawValue, privacy: .public) key: \(error)")
            status[account] = .saveFailed
            return false
        }
        guard let checkKey else {
            status[account] = nil
            return true
        }
        status[account] = .checking
        let result = await checkKey(key, account)
        if generation[account] == current {
            status[account] = .checked(result)
        }
        return true
    }

    /// Removes the key of `account`. Returns false when the Keychain refused (then the status is `.removeFailed`).
    @discardableResult
    func remove(_ account: ProviderAccount) -> Bool {
        bump(account)
        do {
            try removeKey(account)
            status[account] = nil
            return true
        } catch {
            Log.app.error("Cannot remove the \(account.rawValue, privacy: .public) key: \(error)")
            status[account] = .removeFailed
            return false
        }
    }

    @discardableResult
    private func bump(_ account: ProviderAccount) -> Int {
        let next = (generation[account] ?? 0) + 1
        generation[account] = next
        return next
    }
}

/// The result line under a key field, with its one fix button where there is one.
struct KeyCheckLine: View {
    let status: KeyStatus
    let account: ProviderAccount

    var body: some View {
        switch status {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking the key…").foregroundStyle(.secondary)
            }
        case .checked(.valid):
            Label("Key works", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .checked(.invalid):
            Label("\(account.title) did not accept this key", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .checked(.noCredit):
            HStack {
                Label("This key has no credit.", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Button("Add Credit…") { NSWorkspace.shared.open(account.creditsPage) }
            }
        case .checked(.unreachable):
            Label(
                "Couldn’t reach \(account.title). The key is saved; kotoba checks it at your first dictation.",
                systemImage: "wifi.exclamationmark"
            )
            .foregroundStyle(.secondary)
        case .checked(.needsEndpoint):
            Label("Key saved. Add your Azure endpoint to check it.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .saveFailed:
            Label("Couldn’t save the key in your keychain. Try again.", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .removeFailed:
            Label("Couldn’t remove the key from your keychain. Try again.", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

/// The cost line next to a key field: "a few cents per hour" only for the model with a known low price, and a
/// "See Pricing…" link to the provider's price page for every model (lead decision 11).
struct PriceLine: View {
    let route: TranscriptionRoute

    /// The price sentence for `route`, or nil when it shows only the link.
    static func text(for route: TranscriptionRoute) -> String? {
        route == .openRouterMAI ? "You pay OpenRouter directly, a few cents per hour of speech." : nil
    }

    var body: some View {
        HStack {
            if let text = Self.text(for: route) {
                Text(text).foregroundStyle(.secondary)
            }
            Button("See Pricing…") { NSWorkspace.shared.open(route.account.pricingPage) }
                .buttonStyle(.link)
        }
    }
}
