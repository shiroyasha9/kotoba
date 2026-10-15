import Foundation
import KotobaProviders
import Security
import Synchronization

/// One provider's API key as a generic password in the login keychain (service `tech.teensy.kotoba`, account = the
/// route, e.g. "openrouter"). The item's access list names this app's Developer ID signature, so the key stays
/// readable across rebuilds. What the Keychain holds is cached after the first look, a missing key included: every
/// save and delete goes through this store (`KeyVault` has one per account), so the cache stays true. A key added
/// outside kotoba (Keychain Access) shows after a relaunch.
final class KeychainStore: APIKeySource {
    /// A Security framework failure other than "no key" (`APIKeyError.missing`), such as a locked keychain.
    enum KeychainError: Error {
        case status(OSStatus)
    }

    private let service: String
    private let account: String
    private enum Cached {
        case unknown
        case missing
        /// A key is stored; its value is not read yet.
        case present
        case key(String)
    }

    private let cached = Mutex(Cached.unknown)

    init(account: String, service: String = "tech.teensy.kotoba") {
        self.service = service
        self.account = account
    }

    /// Whether a key is stored, without reading it.
    func hasKey() -> Bool {
        switch cached.withLock({ $0 }) {
        case .key, .present: return true
        case .missing: return false
        case .unknown: break
        }
        let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        let found: Cached? =
            switch status {
            case errSecSuccess: .present
            case errSecItemNotFound: .missing
            default: nil  // A locked keychain: ask again next time.
            }
        return cached.withLock { cached in
            // A save or delete during the lookup is newer than its answer; keep it.
            if case .unknown = cached, let found {
                cached = found
            }
            switch cached {
            case .key, .present: return true
            case .missing: return false
            case .unknown: return status == errSecSuccess
            }
        }
    }

    func apiKey() async throws -> String {
        switch cached.withLock({ $0 }) {
        case .key(let key): return key
        case .missing: throw APIKeyError.missing
        case .unknown, .present: break
        }
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            cached.withLock { $0 = .missing }
            throw APIKeyError.missing
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw APIKeyError.missing
        }
        cached.withLock { $0 = .key(key) }
        return key
    }

    func save(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.status(added) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
        cached.withLock { $0 = .key(key) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
        cached.withLock { $0 = .missing }
    }

    private var baseQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }
}
