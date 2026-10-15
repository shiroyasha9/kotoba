import Foundation
import KotobaCore
import os

/// One provider's connection: its long-lived URLSession, its API key and how the key is sent. Every route's request
/// goes through `send`, so the key read, the body, the upload and the transport errors are written once; each client
/// keeps only its URL, its body layout and its response shape.
final class ProviderConnection: Sendable {
    enum KeyHeader: Sendable {
        /// `Authorization: Bearer <key>` (OpenRouter, xAI).
        case bearer
        /// `Ocp-Apim-Subscription-Key: <key>` (Azure).
        case subscriptionKey
    }

    enum Body {
        /// A small body sent from memory.
        case data(Data)
        /// A body with the audio in it, written to a temp file piece by piece and uploaded from there.
        case streamed((BodyWriter) throws -> Void)
    }

    let account: ProviderAccount
    private let apiKey: any APIKeySource
    private let keyHeader: KeyHeader
    private let session: URLSession

    init(
        account: ProviderAccount,
        apiKey: any APIKeySource,
        keyHeader: KeyHeader = .bearer,
        configuration: URLSessionConfiguration = ProviderHTTP.sessionConfiguration()
    ) {
        self.account = account
        self.apiKey = apiKey
        self.keyHeader = keyHeader
        // swiftlint:disable:next url_session_construction
        session = URLSession(configuration: configuration)
    }

    /// Opens the TLS connection the upload reuses, and reads the key so the Keychain lookup is off the stop path.
    func warm(_ url: URL) async {
        async let key = apiKey.apiKey()
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        // The answers do not matter: a failed warm-up only means the upload opens its own connection, and a missing
        // key is reported by `send`.
        _ = try? await session.data(for: request)
        _ = try? await key
    }

    /// POSTs `body` to `url` with the key, mapping transport failures to `ProviderError.offline`.
    func send(_ url: URL, contentType: String, label: String, body: Body) async throws -> (Data, HTTPURLResponse) {
        let key = try await key()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        authorize(&request, with: key)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let metrics = UploadMetrics(label)
        do {
            let (data, response): (Data, URLResponse)
            switch body {
            case .data(let bytes):
                (data, response) = try await session.upload(for: request, from: bytes, delegate: metrics)
            case .streamed(let write):
                let file = FileManager.default.temporaryDirectory.appending(path: "kotoba-upload-\(UUID().uuidString)")
                // The body is a copy of the kept FLAC; losing it to a failed delete costs only temp space.
                defer { try? FileManager.default.removeItem(at: file) }
                try write(BodyWriter(file: file))
                // Splits the body build from the network time in Instruments and the latency report.
                Log.signposter.emitEvent("bodyReady")
                (data, response) = try await session.upload(for: request, fromFile: file, delegate: metrics)
            }
            guard let http = response as? HTTPURLResponse else { throw ProviderError.server(status: 0) }
            return (data, http)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw ProviderError.offline
        }
    }

    /// One free request with `key` (the one being checked, not the stored one), for the key check. Nil when no
    /// answer came: offline, or a timeout.
    func probe(_ url: URL, method: String, key: String) async -> (Data, HTTPURLResponse)? {
        var request = URLRequest(url: url)
        request.httpMethod = method
        authorize(&request, with: key)
        do {
            let (data, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { (data, $0) }
        } catch {
            return nil
        }
    }

    private func authorize(_ request: inout URLRequest, with key: String) {
        switch keyHeader {
        case .bearer: request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .subscriptionKey: request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        }
    }

    private func key() async throws(ProviderError) -> String {
        do {
            return try await apiKey.apiKey()
        } catch APIKeyError.missing {
            throw .needsSetup(provider: account.title, item: .key)
        } catch {
            throw .keyUnavailable
        }
    }
}

/// The parts of the request and response every route shares.
enum ProviderHTTP {
    static let log = Logger(subsystem: Log.subsystem, category: "provider")

    /// No disk cache or cookies. A request fails at once when offline (the pipeline queues it) instead of waiting
    /// for connectivity. Upstreams time out after about 60 s, so the resource limit sits just above that.
    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 75
        return configuration
    }

    /// Sorted keys and unescaped slashes, so request bodies are stable bytes for the fixture tests.
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// The success body of `response`, or the `ProviderError` for its status (or for a body that does not parse).
    /// Failures are logged under `label`.
    static func decode<Body: Decodable>(
        _ type: Body.Type,
        from data: Data,
        response: HTTPURLResponse,
        label: String
    ) throws(ProviderError) -> Body {
        let status = response.statusCode
        guard (200..<300).contains(status) else {
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
            throw logged(error(status: status, retryAfter: retryAfter, body: data), label: label)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw logged(.server(status: status), label: label)
        }
    }

    /// The key check result for a status that is not plain success: 401/403 refused, 402 no credit, anything else
    /// (or no answer) unreachable. Each provider reads its own 200 body.
    static func keyCheck(status: Int?) -> KeyCheck {
        switch status {
        case 401, 403: .invalid
        case 402: .noCredit
        default: .unreachable
        }
    }

    /// `text` trimmed; an empty or missing text is `ProviderError.emptyTranscript`.
    static func nonEmpty(_ text: String?, label: String) throws(ProviderError) -> String {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw logged(.emptyTranscript, label: label) }
        return trimmed
    }

    /// The error for a non-2xx status, the same on every route: 401/403 auth, 402 no credit, 429 rate limit,
    /// 408/5xx server, any other 4xx rejected with the body's message.
    static func error(status: Int, retryAfter: String?, body: Data) -> ProviderError {
        switch status {
        case 401, 403: .auth(status: status)
        case 402: .noCredit
        case 429: .rateLimited(retryAfter: retryAfter.flatMap(Int.init).map { .seconds($0) })
        case 408, 500...: .server(status: status)
        default: .rejected(status: status, message: errorMessage(in: body))
        }
    }

    /// The message from the error shapes the routes send (`{"error": {"message"}}` on OpenRouter and Azure,
    /// `{"error": "..."}` and `{"message": "..."}` elsewhere), else the start of the raw body.
    static func errorMessage(in data: Data) -> String {
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data), let message = body.message {
            return message
        }
        // A body that is not JSON (an HTML page from a proxy) is still worth showing.
        return String(bytes: data.prefix(200), encoding: .utf8) ?? ""
    }

    private static func logged(_ error: ProviderError, label: String) -> ProviderError {
        log.error("\(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        return error
    }
}

/// Azure's `phraseList` field, sent direct and through OpenRouter's `provider.options.azure`.
struct PhraseList: Encodable {
    var phrases: [String]
}

/// Writes a request body to a file piece by piece, so the audio is copied in chunks and never held whole in memory.
final class BodyWriter {
    /// Base64 turns 3 bytes into 4 characters, so chunks of a multiple of 3 bytes encode to pieces that join
    /// without padding in the middle.
    static let chunk = 48 * 1024

    private let output: FileHandle

    init(file: URL) throws {
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
        }
        output = try FileHandle(forWritingTo: file)
    }

    deinit {
        // Every write throws its own error first; closing a file that is already complete cannot lose data.
        try? output.close()
    }

    func write(_ text: String) throws {
        try output.write(contentsOf: Data(text.utf8))
    }

    func write(_ data: Data) throws {
        try output.write(contentsOf: data)
    }

    /// Copies `file` as is, or as base64 text.
    func write(contentsOf file: URL, base64: Bool = false) throws {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }  // Read-only: closing cannot lose data.
        while let chunk = try input.read(upToCount: Self.chunk), !chunk.isEmpty {
            try output.write(contentsOf: base64 ? chunk.base64EncodedData() : chunk)
        }
    }
}

/// `multipart/form-data` framing (RFC 7578) for the direct routes. The file part goes last: xAI requires it.
struct Multipart {
    let boundary: String

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    func field(_ name: String, _ value: String, contentType: String? = nil) -> String {
        let type = contentType.map { "Content-Type: \($0)\r\n" } ?? ""
        return "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\(type)\r\n\(value)\r\n"
    }

    func fileHeader(_ name: String, filename: String, contentType: String) -> String {
        "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
            + "Content-Type: \(contentType)\r\n\r\n"
    }

    var end: String { "\r\n--\(boundary)--\r\n" }

    static func randomBoundary() -> String { "kotoba-\(UUID().uuidString)" }
}

/// Logs how the upload connected, next to the pipeline's latency line: a reused connection means the key-down
/// warm-up worked; a new one shows its connect and TLS cost.
private final class UploadMetrics: NSObject, URLSessionTaskDelegate, Sendable {
    private let label: String

    init(_ label: String) {
        self.label = label
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let last = metrics.transactionMetrics.last else { return }
        Log.latency.info(
            """
            upload \(self.label, privacy: .public): reused \(last.isReusedConnection, privacy: .public), \
            protocol \(last.networkProtocolName ?? "unknown", privacy: .public), \
            connect \(Self.milliseconds(last.connectStartDate, last.connectEndDate), privacy: .public), \
            tls \(Self.milliseconds(last.secureConnectionStartDate, last.secureConnectionEndDate), privacy: .public)
            """
        )
    }

    private static func milliseconds(_ start: Date?, _ end: Date?) -> String {
        guard let start, let end else { return "none" }
        return "\(Int((end.timeIntervalSince(start) * 1000).rounded())) ms"
    }
}

private struct ErrorBody: Decodable {
    private struct Detail: Decodable {
        var message: String?
    }

    private enum CodingKeys: String, CodingKey {
        case error
        case message
    }

    let message: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The three shapes are tried in turn; a key with another type is simply not this shape.
        if let detail = try? container.decode(Detail.self, forKey: .error), let message = detail.message {
            self.message = message
        } else if let text = try? container.decode(String.self, forKey: .error) {
            message = text
        } else {
            message = try container.decodeIfPresent(String.self, forKey: .message)
        }
    }
}
