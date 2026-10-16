import Foundation

/// Where a provider reads its API key. The app reads the Keychain (`KeychainStore`); tests use a fake.
public protocol APIKeySource: Sendable {
    /// Throws `APIKeyError.missing` when no key is stored; the provider reports that as `ProviderError.auth`.
    /// Any other error (a locked keychain) becomes the retryable `ProviderError.keyUnavailable`.
    func apiKey() async throws -> String
}

public enum APIKeyError: Error {
    case missing
}

/// A saved key as a key field shows it, so the owner can tell which key is saved without seeing it: the provider's
/// prefix ("sk-or-v1-", "xai-") and the last four characters, as provider dashboards show a key after it is made.
public enum KeyMask {
    public static func text(of key: String) -> String {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixEnd = key.prefix(10).lastIndex { $0 == "-" || $0 == "_" }.map { key.index(after: $0) }
        let prefix = prefixEnd.map { key[..<$0] } ?? ""
        let rest = key[(prefixEnd ?? key.startIndex)...]
        // At least eight hidden characters, so a short key never shows most of itself.
        return prefix + "…" + (rest.count >= 12 ? rest.suffix(4) : "")
    }
}
