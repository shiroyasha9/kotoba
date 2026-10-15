import KotobaProviders

/// The app's one set of API keys: one Keychain store per provider account. Every read and save goes
/// through here (lint flags `KeychainStore(` anywhere else), so a saved key always replaces the copy
/// the router reads, and every save and delete is announced on `changes`.
final class KeyVault: Sendable {
    /// The account of each saved or deleted key: the app retries the dictations that waited for a key, and
    /// refreshes `Readiness`. One consumer (AppDelegate).
    let changes: AsyncStream<ProviderAccount>
    private let changesContinuation: AsyncStream<ProviderAccount>.Continuation
    private let stores: [ProviderAccount: KeychainStore]

    init() {
        stores = Dictionary(
            uniqueKeysWithValues: ProviderAccount.allCases.map { account in
                // swiftlint:disable:next keychain_store_construction
                (account, KeychainStore(account: account.rawValue))
            })
        (changes, changesContinuation) = AsyncStream.makeStream(of: ProviderAccount.self)
    }

    /// The key source the router and the cleaner read for `account`.
    func source(for account: ProviderAccount) -> any APIKeySource {
        store(for: account)
    }

    /// Cached by the store, so the menu and `Readiness` read no Keychain after the first look.
    func hasKey(for account: ProviderAccount) -> Bool {
        store(for: account).hasKey()
    }

    func save(_ key: String, for account: ProviderAccount) throws {
        try store(for: account).save(key)
        changesContinuation.yield(account)
    }

    func delete(for account: ProviderAccount) throws {
        try store(for: account).delete()
        changesContinuation.yield(account)
    }

    private func store(for account: ProviderAccount) -> KeychainStore {
        guard let store = stores[account] else {
            preconditionFailure("Every ProviderAccount has a key store")
        }
        return store
    }
}
