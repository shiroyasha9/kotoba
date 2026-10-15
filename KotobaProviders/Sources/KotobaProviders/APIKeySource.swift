/// Where a provider reads its API key. The app reads the Keychain (`KeychainStore`); tests use a fake.
public protocol APIKeySource: Sendable {
    /// Throws `APIKeyError.missing` when no key is stored; the provider reports that as `ProviderError.auth`.
    /// Any other error (a locked keychain) becomes the retryable `ProviderError.keyUnavailable`.
    func apiKey() async throws -> String
}

public enum APIKeyError: Error {
    case missing
}
