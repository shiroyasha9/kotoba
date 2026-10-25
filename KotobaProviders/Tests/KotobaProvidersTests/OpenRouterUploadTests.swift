import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

// The audio a transcription request sends through OpenRouter: which form, and the route's upload cap. Stubs as in
// OpenRouterProviderTests.

/// The Ogg Opus copy of a recording (`TranscriptionRequest.upload`): sent only on the route measured with it.
struct OpenRouterOpusUploadTests {
    /// MAI through OpenRouter answers about 240 ms sooner for the Ogg Opus copy at the WER of the FLAC
    /// (docs/research/latency-pass-2.md).
    @Test func maiRequestSendsTheOggOpusCopyWhenTheRecordingHasOne() async throws {
        let stub = StubHost(reply: .fixture("success"))

        _ = try await stub.provider().transcribe(stub.request(upload: StubHost.opusBytes))

        let audio = try #require(try stub.requests.only?.json()["input_audio"] as? [String: String])
        #expect(audio["format"] == "ogg")
        #expect(audio["data"] == StubHost.opusBytes.base64EncodedString())
        #expect(stub.copies.made.isEmpty)
    }

    /// A request with no copy (a retry, History's Transcribe Again, a segment upload's fallback to the whole
    /// recording) or with a copy that is gone (a launch empties the copies' folder) sends a copy made from the FLAC
    /// now, and that copy goes after the request.
    @Test(arguments: [false, true])
    func maiRequestWithoutTheRecordingsCopyMakesOneFromTheFLAC(hadCopy: Bool) async throws {
        let stub = StubHost(reply: .fixture("success"))
        var request = try stub.request()
        if hadCopy {
            request.upload = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).ogg")
        }

        _ = try await stub.provider().transcribe(request)

        let audio = try #require(try stub.requests.only?.json()["input_audio"] as? [String: String])
        #expect(audio["format"] == "ogg")
        #expect(audio["data"] == StubHost.madeOpusBytes.base64EncodedString())
        let made = try #require(stub.copies.made.only)
        #expect(made.flac == request.audio)
        #expect(!FileManager.default.fileExists(atPath: made.copy.path))
    }

    /// The FLAC is the form every route takes: a copy that cannot be made does not lose the dictation.
    @Test func maiRequestSendsTheFLACWhenNoCopyCanBeMade() async throws {
        let stub = StubHost(reply: .fixture("success"))
        stub.copies.failure = FakeCopyEncoder.Failed()

        _ = try await stub.provider().transcribe(stub.request())

        let audio = try #require(try stub.requests.only?.json()["input_audio"] as? [String: String])
        #expect(audio["format"] == "flac")
        #expect(audio["data"] == StubHost.audioBytes.base64EncodedString())
    }

    /// A request cancelled while its copy is made (Esc, quit) ends there: no FLAC goes in its place.
    @Test func aCancelledCopySendsNothing() async throws {
        let stub = StubHost(reply: .fixture("success"))
        stub.copies.failure = CancellationError()
        let provider = stub.provider()
        let request = try stub.request()

        await #expect(throws: CancellationError.self) {
            try await provider.transcribe(request)
        }
        #expect(stub.requests.isEmpty)
    }

    /// Only a route measured with the Opus copy sends it.
    @Test(arguments: [TranscriptionRoute.openRouterGrok, .xaiGrok, .azureMAI])
    func otherRoutesSendTheFLACAlsoWhenThereIsAnOpusCopy(route: TranscriptionRoute) async throws {
        let stub = StubHost(
            reply: .fixture(route == .azureMAI ? "azure-success" : route == .xaiGrok ? "xai-success" : "success"))
        if route == .azureMAI { stub.useAzure() } else { stub.settings.route = route }

        _ = try await stub.provider().transcribe(stub.request(upload: StubHost.opusBytes))

        let body = try #require(stub.requests.only).body
        #expect(body.range(of: StubHost.opusBytes) == nil)
        #expect(body.range(of: StubHost.opusBytes.base64EncodedData()) == nil)
        let flac = route == .openRouterGrok ? StubHost.audioBytes.base64EncodedData() : StubHost.audioBytes
        #expect(body.range(of: flac) != nil)
        #expect(stub.copies.made.isEmpty)
    }
}

/// OpenRouter refuses a body over 25 MB on every route kotoba uses (`OpenRouterProvider.bodyLimit`): a whole FLAC passes
/// it at about 20 minutes, the Opus copy at about 100.
struct OpenRouterBodyLimitTests {
    /// The size of the body `stub` sends for `request` with no cap.
    private func bodySize(_ stub: StubHost, _ request: TranscriptionRequest) async throws -> Int {
        _ = try await stub.provider().transcribe(request)
        return try #require(stub.requests.last).body.count
    }

    /// Grok takes only the FLAC: a body over the cap fails at once with what the owner can read, never as an upload
    /// that the route refuses after minutes.
    @Test func aBodyOverTheCapIsRefusedBeforeAnyUpload() async throws {
        let stub = StubHost(reply: .fixture("success"))
        stub.settings.route = .openRouterGrok
        let request = try stub.request()
        let size = try await bodySize(stub, request)

        await #expect(throws: ProviderError.tooLong(bytes: size, limit: size - 1)) {
            try await stub.provider(bodyLimit: size - 1).transcribe(request)
        }
        #expect(stub.requests.count == 1)
        _ = try await stub.provider(bodyLimit: size).transcribe(request)
        #expect(stub.requests.count == 2)
    }

    /// The cap counts the body that goes: on MAI a recording whose FLAC is over it goes as its Opus copy.
    @Test func maiSendsTheOpusCopyOfARecordingWhoseFLACIsOverTheCap() async throws {
        let stub = StubHost(reply: .fixture("success"))
        let request = try stub.request()
        let opus = try await bodySize(stub, request)
        stub.copies.failure = FakeCopyEncoder.Failed()
        let flac = try await bodySize(stub, request)
        #expect(opus < flac)

        let error = await #expect(throws: ProviderError.self) {
            try await stub.provider(bodyLimit: opus).transcribe(request)
        }
        guard case .tooLong(let bytes, let limit) = error else {
            Issue.record("expected tooLong, got \(String(describing: error))")
            return
        }
        // The body stops at the write that passes the cap.
        #expect(bytes > opus && bytes <= flac && limit == opus)
        stub.copies.failure = nil
        _ = try await stub.provider(bodyLimit: opus).transcribe(request)
        #expect(stub.requests.count == 3)
    }

    /// The direct routes have no cap of OpenRouter's.
    @Test(arguments: [TranscriptionRoute.xaiGrok, .azureMAI])
    func directRoutesHaveNoOpenRouterCap(route: TranscriptionRoute) async throws {
        let stub = StubHost(reply: .fixture(route == .azureMAI ? "azure-success" : "xai-success"))
        if route == .azureMAI { stub.useAzure() } else { stub.settings.route = route }

        _ = try await stub.provider(bodyLimit: 1).transcribe(stub.request())

        #expect(stub.requests.count == 1)
    }
}
