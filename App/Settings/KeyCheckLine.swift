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
/// save or a removal while a check runs wins, so a slow answer never shows for a key that is gone. It also holds the
/// masked text of each saved key (`KeyMask`), so a key field shows which key is saved without the key.
@MainActor
@Observable
final class KeyChecks {
    private(set) var status: [ProviderAccount: KeyStatus] = [:]
    /// The masked saved key per account: set by a save here, or read once from the Keychain by `loadMask(for:)`.
    private(set) var masks: [ProviderAccount: String] = [:]

    @ObservationIgnored private let saveKey: @MainActor (String, ProviderAccount) throws -> Void
    @ObservationIgnored private let removeKey: @MainActor (ProviderAccount) throws -> Void
    /// The router's free key check; nil saves without a check (snapshots).
    @ObservationIgnored private let checkKey: (@MainActor (String, ProviderAccount) async -> KeyCheck)?
    /// The saved key of an account, read only to mask it; nil when there is none or the Keychain is locked.
    @ObservationIgnored private let readKey: @MainActor (ProviderAccount) async -> String?
    /// Whether the Keychain holds a key for the account, without reading it (`KeyVault.hasKey`).
    @ObservationIgnored private let hasKey: @MainActor (ProviderAccount) -> Bool
    /// Bumped by each save and removal, so an older check's answer is dropped.
    @ObservationIgnored private var generation: [ProviderAccount: Int] = [:]

    /// `checkKey` is `TranscriptionRouter.checkKey(_:for:)`.
    convenience init(vault: KeyVault, checkKey: (@MainActor (String, ProviderAccount) async -> KeyCheck)?) {
        self.init(
            saveKey: { try vault.save($0, for: $1) }, removeKey: { try vault.delete(for: $0) }, checkKey: checkKey,
            // A missing key and a locked keychain both leave nothing to mask; the field then shows dots.
            readKey: { try? await vault.source(for: $0).apiKey() }, hasKey: vault.hasKey(for:))
    }

    init(
        saveKey: @escaping @MainActor (String, ProviderAccount) throws -> Void,
        removeKey: @escaping @MainActor (ProviderAccount) throws -> Void,
        checkKey: (@MainActor (String, ProviderAccount) async -> KeyCheck)?,
        readKey: @escaping @MainActor (ProviderAccount) async -> String?,
        hasKey: @escaping @MainActor (ProviderAccount) -> Bool
    ) {
        self.saveKey = saveKey
        self.removeKey = removeKey
        self.checkKey = checkKey
        self.readKey = readKey
        self.hasKey = hasKey
    }

    /// Fixed results with nothing behind them, for snapshots. `savedKeys` hold a sample key each, masked as a saved
    /// key is.
    static func sample(_ status: [ProviderAccount: KeyStatus], savedKeys: Set<ProviderAccount> = []) -> KeyChecks {
        let checks = KeyChecks(
            saveKey: { _, _ in }, removeKey: { _ in }, checkKey: nil, readKey: { _ in nil },
            hasKey: savedKeys.contains)
        checks.status = status
        for account in savedKeys {
            checks.masks[account] = KeyMask.text(of: account.sampleKey)
        }
        return checks
    }

    /// Whether `account` has a stored key. Reads `status` and `masks`, so a view that asks redraws after each save or
    /// removal.
    func isSaved(_ account: ProviderAccount) -> Bool {
        _ = (status, masks)
        return hasKey(account)
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
        masks[account] = KeyMask.text(of: key)
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
            masks[account] = nil
            return true
        } catch {
            Log.app.error("Cannot remove the \(account.rawValue, privacy: .public) key: \(error)")
            status[account] = .removeFailed
            return false
        }
    }

    /// Masks a key saved before this window opened, once: one Keychain read, and the key goes no further than here.
    func loadMask(for account: ProviderAccount) async {
        guard masks[account] == nil else { return }
        let current = generation[account]
        guard let key = await readKey(account), generation[account] == current else { return }
        masks[account] = KeyMask.text(of: key)
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
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking the key…").foregroundStyle(.secondary)
            }
        case .checked(.valid):
            StatusLabel("Connected", systemImage: "checkmark.circle.fill", color: .green)
        case .checked(.invalid):
            StatusLabel("\(account.title) didn’t accept this key.", systemImage: "xmark.circle.fill", color: .red)
        case .checked(.noCredit):
            // The link under the status, as System Settings' "Learn More…" under a description: beside it, the two
            // squeezed into the row's text column and wrapped.
            VStack(alignment: .leading, spacing: 0) {
                StatusLabel("This key has no credit.", systemImage: "exclamationmark.circle.fill", color: .orange)
                Button("Add Credit…") { NSWorkspace.shared.open(account.creditsPage) }
                    .buttonStyle(.link)
                    // A subtitle's grey would take the link's colour.
                    .foregroundStyle(.link)
            }
        case .checked(.unreachable):
            StatusLabel(
                "Couldn’t reach \(account.title). The key is saved; kotoba checks it at your first dictation.",
                systemImage: "wifi.exclamationmark", color: .secondary
            )
            .foregroundStyle(.secondary)
        case .checked(.needsEndpoint):
            StatusLabel(
                "Key saved. Add your Azure endpoint to check it.", systemImage: "checkmark.circle", color: .secondary
            )
            .foregroundStyle(.secondary)
        case .saveFailed:
            StatusLabel(
                "Couldn’t save the key in your keychain. Try again.", systemImage: "xmark.circle.fill", color: .red)
        case .removeFailed:
            StatusLabel(
                "Couldn’t remove the key from your keychain. Try again.", systemImage: "xmark.circle.fill", color: .red)
        }
    }
}

/// A status line where only the symbol carries the status color, as in System Settings; the words keep the label
/// colors. The key check line and the Speech pane's "Saved" use it.
struct StatusLabel<Style: ShapeStyle>: View {
    let text: String
    let systemImage: String
    let color: Style

    init(_ text: String, systemImage: String, color: Style) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(color)
        }
        // The symbol beside its words: in a form row a plain label takes the row's icon column, which left a wide gap
        // after the symbol (owner QA 1, Q18).
        .labelStyle(.titleAndIcon)
    }
}

/// A line with a symbol in its status color: allowed, off, or a hint. Onboarding and the Microphone pane use it.
struct StatusLine: View {
    enum Kind { case good, problem, neutral }

    let text: String
    let kind: Kind

    init(_ text: String, _ kind: Kind) {
        self.text = text
        self.kind = kind
    }

    var body: some View {
        switch kind {
        case .good: StatusLabel(text, systemImage: "checkmark.circle.fill", color: .green)
        case .problem: StatusLabel(text, systemImage: "exclamationmark.triangle.fill", color: .orange)
        case .neutral: StatusLabel(text, systemImage: "info.circle", color: .secondary)
        }
    }
}

/// The cost line next to a key field: who bills the owner, and a "See Pricing…" link to the provider's price page
/// (lead decision 11). No price in words: MAI's is a promotion until 2026-12-31 (copy pass, chief of staff).
struct PriceLine: View {
    let route: TranscriptionRoute

    /// Who bills the owner for `route`.
    static func text(for route: TranscriptionRoute) -> String {
        "\(route.account.title) bills you for what you use."
    }

    var body: some View {
        HStack {
            Text(Self.text(for: route)).foregroundStyle(.secondary)
            Button("See Pricing…") { NSWorkspace.shared.open(route.account.pricingPage) }
                .buttonStyle(.link)
        }
        // A footer's size: the form sets it on text only, so the link came out larger than its line.
        .font(.subheadline)
    }
}
