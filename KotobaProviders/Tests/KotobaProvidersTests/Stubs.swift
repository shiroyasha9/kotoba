import Foundation
import KotobaCore
import Synchronization
import Testing

@testable import KotobaProviders

// Test doubles for OpenRouterProviderTests: a per-test `StubURLProtocol` host with fixture replies, an in-memory
// settings store and a fake key source.

/// A key source: a key, no key (`key: nil`), or a store that fails for another reason (`isLocked`).
struct FakeAPIKey: APIKeySource {
    struct Locked: Error {}

    let key: String?
    var isLocked = false

    func apiKey() async throws -> String {
        if isLocked { throw Locked() }
        guard let key else { throw APIKeyError.missing }
        return key
    }
}

enum StubReply: Sendable {
    case raw(status: Int, headers: [String: String] = [:], body: String)
    case failure(URLError.Code)

    static func status(_ status: Int) -> Self { .raw(status: status, body: "") }

    static func fixture(_ name: String, status: Int = 200, headers: [String: String] = [:]) -> Self {
        .raw(status: status, headers: headers, body: fixtureText(name))
    }

    static func fixtureText(_ name: String, extension ext: String = "json") -> String {
        String(bytes: fixtureData(name, extension: ext), encoding: .utf8) ?? ""
    }

    static func fixtureData(_ name: String, extension ext: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
            let data = try? Data(contentsOf: url)
        else { preconditionFailure("missing fixture \(name).\(ext)") }
        return data
    }
}

struct SentRequest: Sendable {
    var url: URL?
    var method: String?
    var headers: [String: String]
    var body: Data

    func json() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}

extension [String: Any] {
    /// `provider.options.xai`, or empty.
    var xaiOptions: [String: Any] {
        ((self["provider"] as? [String: Any])?["options"] as? [String: Any])?["xai"] as? [String: Any] ?? [:]
    }
}

/// One test's slice of `StubURLProtocol`: a unique host, its reply, and the requests it saw. The host also names the
/// test's audio file, removed when the test drops its `StubHost`.
final class StubHost {
    static let key = "sk-or-test"
    static let audioBytes = Data("fLaC\u{0}\u{0}\u{0}\"stub audio".utf8)

    let host = "openrouter-\(UUID().uuidString.lowercased()).test"
    var baseURL: URL { url("/api/v1") }

    /// `https://<host><path>`.
    func url(_ path: String) -> URL {
        guard let url = URL(string: "https://\(host)\(path)") else { preconditionFailure("stub URL") }
        return url
    }
    var requests: [SentRequest] { StubURLProtocol.routes.withLock { $0[host]?.requests ?? [] } }

    init(reply: StubReply) {
        StubURLProtocol.routes.withLock { $0[host] = StubURLProtocol.Route(reply: reply) }
    }

    func onRequest(_ action: @escaping @Sendable () -> Void) {
        StubURLProtocol.routes.withLock { $0[host]?.onRequest = action }
    }

    deinit {
        StubURLProtocol.routes.withLock { $0[host] = nil }
        // The file exists only for tests that built a request.
        try? FileManager.default.removeItem(at: audioFile)
    }

    private var audioFile: URL { FileManager.default.temporaryDirectory.appending(path: "\(host).flac") }

    /// The multipart boundary the direct routes use in tests, so their bodies match the fixtures byte for byte.
    static let boundary = "test-boundary"

    /// Route settings in memory; the router reads the same storage, as the app's menu and router share
    /// UserDefaults.
    let settings = TranscriptionSettings.inMemory()

    /// An Azure Speech endpoint that routes to this test's host: `<host>.cognitiveservices.azure.com`.
    var azureEndpoint: String { "https://\(host).cognitiveservices.azure.com/" }

    /// Selects Azure direct with `azureEndpoint`.
    func useAzure() {
        settings.route = .azureMAI
        settings.azureEndpoint = azureEndpoint
    }

    /// The router with every route pointed at this test's host: OpenRouter at /api/v1, xAI at /v1/stt; Azure takes
    /// its endpoint from the settings (`useAzure`).
    func provider(key: String? = StubHost.key, isKeyLocked: Bool = false) -> TranscriptionRouter {
        let apiKey = FakeAPIKey(key: key, isLocked: isKeyLocked)
        return TranscriptionRouter(
            settings: settings,
            openRouter: OpenRouterProvider(apiKey: apiKey, baseURL: baseURL, configuration: Self.configuration()),
            xai: XAIProvider(
                apiKey: apiKey, endpoint: url("/v1/stt"),
                configuration: Self.configuration(), makeBoundary: { Self.boundary }),
            azure: AzureProvider(apiKey: apiKey, configuration: Self.configuration(), makeBoundary: { Self.boundary })
        )
    }

    func cleaner(key: String? = StubHost.key) -> OpenRouterCleaner {
        OpenRouterCleaner(
            apiKey: FakeAPIKey(key: key), settings: settings, baseURL: baseURL, configuration: Self.configuration())
    }

    private static func configuration() -> URLSessionConfiguration {
        let configuration = ProviderHTTP.sessionConfiguration()
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    func request(
        terms: [String] = [], audio: Data = StubHost.audioBytes, duration: Duration = .seconds(10)
    ) throws -> TranscriptionRequest {
        try audio.write(to: audioFile)
        return TranscriptionRequest(
            audio: audioFile, duration: duration, language: Locale.Language(identifier: "en"), dictionaryTerms: terms)
    }
}

/// Answers from a route table keyed by host, so tests running in parallel never share a reply.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    // @unchecked: URLProtocol is not Sendable; this subclass adds no stored state, and the route table sits behind
    // `routes`' Mutex.
    struct Route {
        var reply: StubReply
        var requests: [SentRequest] = []
        /// Runs when a request arrives, before the reply.
        var onRequest: (@Sendable () -> Void)?
    }

    static let routes = Mutex<[String: Route]>([:])

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let sent = SentRequest(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? request.httpBodyStream.map(Self.drain) ?? Data()
        )
        let requestHost = request.url?.host() ?? ""
        let (reply, onRequest) = Self.routes.withLock { routes in
            // Azure requests go to `<host>.cognitiveservices.azure.com`.
            guard let host = routes.keys.first(where: { requestHost == $0 || requestHost.hasPrefix("\($0).") }) else {
                return (StubReply?.none, (@Sendable () -> Void)?.none)
            }
            routes[host]?.requests.append(sent)
            return (routes[host]?.reply, routes[host]?.onRequest)
        }
        onRequest?()
        guard let client, let url = request.url else { return }
        switch reply {
        case .raw(let status, let headers, let body):
            guard
                let response = HTTPURLResponse(
                    url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: headers)
            else { return }
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data(body.utf8))
            client.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client.urlProtocol(self, didFailWithError: URLError(code))
        case nil:
            client.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
        }
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

extension Array {
    /// The element of a one-element array, else nil.
    var only: Element? { count == 1 ? first : nil }
}
