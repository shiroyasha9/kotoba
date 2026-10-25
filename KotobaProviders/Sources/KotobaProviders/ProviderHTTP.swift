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
        /// A body sent from memory: a small one, or a route primer kept for every send.
        case data(Data)
        /// A body with the audio in it, written to a temp file piece by piece and uploaded from there.
        case streamed((BodyWriter) throws -> Void)
    }

    let account: ProviderAccount
    private let apiKey: any APIKeySource
    private let keyHeader: KeyHeader
    /// The owner typed the host (Azure's resource endpoint): a host that does not resolve may be a typo, so the pill
    /// names it instead of saying offline.
    private let isHostSetByOwner: Bool
    private let session: URLSession
    private let interfaces = InterfaceMemo()

    init(
        account: ProviderAccount,
        apiKey: any APIKeySource,
        keyHeader: KeyHeader = .bearer,
        isHostSetByOwner: Bool = false,
        configuration: URLSessionConfiguration = ProviderHTTP.sessionConfiguration()
    ) {
        self.account = account
        self.apiKey = apiKey
        self.keyHeader = keyHeader
        self.isHostSetByOwner = isHostSetByOwner
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

    /// One answer to `send`.
    struct Reply {
        let data: Data
        let response: HTTPURLResponse
        /// The upload's moments, when the system's metrics came before the answer.
        let network: NetworkTiming?
    }

    /// POSTs `body` to `url` with the key, mapping a timeout to `ProviderError.timedOut`, a host the owner typed that
    /// does not resolve to `.hostNotFound`, and other transport failures to `.offline`. `idleTimeout`
    /// replaces the session's idle limit for this request only.
    func send(
        _ url: URL, contentType: String, label: String, body: Body, idleTimeout: TimeInterval? = nil
    ) async throws -> Reply {
        let key = try await key()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let idleTimeout { request.timeoutInterval = idleTimeout }
        authorize(&request, with: key)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let metrics = UploadMetrics(label, interfaces: interfaces)
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
            return Reply(data: data, response: http, network: metrics.timing)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            // The network works; the route was slow, and may have taken the audio.
            throw ProviderError.timedOut
        } catch let error as URLError where error.code == .cannotFindHost && isHostSetByOwner {
            throw ProviderError.hostNotFound(host: url.host() ?? url.absoluteString)
        } catch let error as URLError where Self.blockingCodes.contains(error.code) {
            throw ProviderError.connectionBlocked
        } catch is URLError {
            throw ProviderError.offline
        }
    }

    /// The network is up but refuses the secure connection: a captive portal or a filtering proxy shows its own
    /// certificate, or the clock is wrong.
    private static let blockingCodes: Set<URLError.Code> = [
        .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
        .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
        .clientCertificateRequired,
    ]

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
    /// for connectivity. Upstreams time out after about 60 s, so the default resource limit sits just above that.
    static func sessionConfiguration(resourceTimeout: TimeInterval = 75) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }

    /// A transcription's upload grows with the recording, so the pipeline bounds it by the audio's length
    /// (`DictationPipeline.Settings.transcriptionTimeout(for:)`); the connection allows a minute more than the longest
    /// bound, so the pipeline's decides and a long recording on a slow uplink is not cut at a fixed time.
    /// A transcription's idle limit (`ProviderConnection.send`): the route sends nothing while it works on a long
    /// recording, so the request may stay idle as long as the pipeline's bound for its audio, never cut first by the
    /// session's 30 s. A request's own limit wins over the session's both ways (spike, 2026-10-17: with a 2 s session
    /// limit, a 5 s request limit got a 3.5 s answer, and a 1 s one timed out at 1 s).
    static func idleTimeout(for request: TranscriptionRequest) -> TimeInterval {
        DictationPipeline.Settings.transcriptionTimeout(for: request.duration) / .seconds(1)
    }

    static let transcriptionResourceTimeout: TimeInterval =
        (DictationPipeline.Settings.longestTranscription + .seconds(60)) / .seconds(1)

    /// Sorted keys and unescaped slashes, so request bodies are stable bytes for the fixture tests.
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// The success body of `reply`, or the `ProviderError` for its status. A success body that does not parse is
    /// `.unreadableAnswer`: the route billed it, and sending it again gets the same answer. Failures are logged under
    /// `label`.
    static func decode<Body: Decodable>(
        _ type: Body.Type,
        from reply: ProviderConnection.Reply,
        label: String
    ) throws(ProviderError) -> Body {
        let (data, response) = (reply.data, reply.response)
        let status = response.statusCode
        guard (200..<300).contains(status) else {
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
            throw logged(error(status: status, retryAfter: retryAfter, body: data), label: label)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw logged(.unreadableAnswer(status: status), label: label)
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

    /// The error for a non-2xx status, the same on every route: 401/403 auth, 402 no credit, 429 rate limit (and 503
    /// with a `Retry-After`: the route asks to wait), 408/5xx server, any other 4xx rejected with the body's message.
    static func error(status: Int, retryAfter header: String?, body: Data) -> ProviderError {
        let retryAfter = header.flatMap { retryAfter($0, now: Date()) }
        switch status {
        case 401, 403: return .auth(status: status)
        case 402: return .noCredit
        case 429: return .rateLimited(retryAfter: retryAfter)
        case 503 where retryAfter != nil: return .rateLimited(retryAfter: retryAfter)
        case 408, 500...: return .server(status: status)
        default: return .rejected(status: status, message: errorMessage(in: body))
        }
    }

    /// A `Retry-After` value (RFC 9110 section 10.2.3): whole seconds, or an HTTP date, counted from `now`.
    static func retryAfter(_ header: String, now: Date) -> Duration? {
        if let seconds = Int(header) { return seconds >= 0 ? .seconds(seconds) : nil }
        guard let date = try? httpDate.parse(header) else { return nil }  // Not a date: no wait was given.
        return .seconds(max(date.timeIntervalSince(now), 0))
    }

    /// The IMF-fixdate form, the one senders must use.
    private static let httpDate = Date.ParseStrategy(
        format: """
            \(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \
            \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\
            \(second: .twoDigits) GMT
            """, locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt)

    /// The message from the error shapes the routes send (`{"error": {"message"}}` on OpenRouter and Azure,
    /// `{"error": "..."}` and `{"message": "..."}` elsewhere), else the start of the raw body.
    static func errorMessage(in data: Data) -> String {
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data), let message = body.message {
            return message
        }
        // A body that is not JSON (an HTML page from a proxy) is still worth showing.
        return String(bytes: data.prefix(200), encoding: .utf8) ?? ""
    }

    /// The label and the error are public; a refusal's message is private, as the body can echo the request
    /// (keyterms, words of the transcript).
    private static func logged(_ error: ProviderError, label: String) -> ProviderError {
        if case .rejected(let status, let message) = error {
            log.error("\(label, privacy: .public) failed: rejected \(status): \(message, privacy: .private)")
        } else {
            log.error("\(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
        return error
    }
}

/// Azure's `phraseList` field, sent direct and through OpenRouter's `provider.options.azure`.
struct PhraseList: Encodable, Equatable {
    var phrases: [String]
}

/// MAI-Transcribe-2 in Azure's `enhancedMode`, sent direct and through OpenRouter's `provider.options.azure`, with
/// the `clean` style unless the owner keeps filler words (`verbatim`, Microsoft's default). `clean` "removes filler
/// words and auto-formats common speech patterns"
/// (https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe). On 60 of the owner's real clips
/// with the phrase list (2026-10-25): "um"/"uh" 22 to 0, repeated words and false starts dropped, every dictionary
/// term kept, time within the noise (docs/research/real-usage-pass.md). `transcribeStyle` takes effect only here; at
/// the top of the options it does nothing.
struct MAIEnhancedMode: Encodable, Equatable {
    enum TranscribeStyle: String, Encodable {
        case clean
        case verbatim
    }

    struct ModelOptions: Encodable, Equatable {
        var transcribeStyle: TranscribeStyle
    }

    var enabled = true
    var model = "MAI-Transcribe-2"
    var modelOptions: ModelOptions

    init(keepsFillerWords: Bool) {
        modelOptions = ModelOptions(transcribeStyle: keepsFillerWords ? .verbatim : .clean)
    }
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

    /// Copies `file` as is, or as base64 text. A file that is gone (the kept recording deleted outside kotoba) throws
    /// `ProviderError.audioMissing`.
    func write(contentsOf file: URL, base64: Bool = false) throws {
        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: file)
        } catch let error as CocoaError where [.fileNoSuchFile, .fileReadNoSuchFile].contains(error.code) {
            throw ProviderError.audioMissing
        }
        defer { try? input.close() }  // Read-only: closing cannot lose data.
        try write(contentsOf: input, base64: base64)
    }

    /// Copies the rest of `input`, as is or as base64 text.
    func write(contentsOf input: FileHandle, base64: Bool = false) throws {
        // FileHandle's autoreleased read buffers must drain per chunk, not after the whole upload body.
        while try autoreleasepool(invoking: {
            guard let chunk = try input.read(upToCount: Self.chunk), !chunk.isEmpty else { return false }
            try output.write(contentsOf: base64 ? chunk.base64EncodedData() : chunk)
            return true
        }) {}
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
