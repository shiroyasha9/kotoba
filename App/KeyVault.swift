import KotobaProviders

/// The app's one set of API keys: one Keychain store per provider account. Every read and save goes
/// through here (lint flags `KeychainStore(` anywhere else), so a saved key always replaces the copy
/// the router reads, and every save is announced on `saves`.
final class KeyVault: Sendable {
    /// The account of each saved key; the app retries the dictations that waited for it.
    let saves: AsyncStream<ProviderAccount>
    private let savesContinuation: AsyncStream<ProviderAccount>.Continuation
    private let stores: [ProviderAccount: KeychainStore]

    init() {
        stores = Dictionary(
            uniqueKeysWithValues: ProviderAccount.allCases.map { account in
                // swiftlint:disable:next keychain_store_construction
                (account, KeychainStore(account: account.rawValue))
            })
        (saves, savesContinuation) = AsyncStream.makeStream(of: ProviderAccount.self)
    }

    /// The key source the router and the cleaner read for `account`.
    func source(for account: ProviderAccount) -> any APIKeySource {
        store(for: account)
    }

    func hasKey(for account: ProviderAccount) -> Bool {
        store(for: account).hasKey()
    }

    func save(_ key: String, for account: ProviderAccount) throws {
        try store(for: account).save(key)
        savesContinuation.yield(account)
    }

    func delete(for account: ProviderAccount) throws {
        try store(for: account).delete()
    }

    private func store(for account: ProviderAccount) -> KeychainStore {
        guard let store = stores[account] else {
            preconditionFailure("Every ProviderAccount has a key store")
        }
        return store
    }
}
