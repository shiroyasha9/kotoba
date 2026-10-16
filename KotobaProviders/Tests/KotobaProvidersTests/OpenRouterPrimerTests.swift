import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

/// The primer (`TranscriptionProvider.prime`): half a second of silence through the route's whole path, the same
/// model, language and data policy as a dictation, with no dictionary terms.
struct OpenRouterPrimerTests {
    @Test func maiPrimerSendsHalfASecondOfSilenceWithTheRoutesDataPolicy() async throws {
        let stub = StubHost(reply: .fixture("success"))

        _ = await stub.provider().prime(language: Locale.Language(identifier: "en"), size: .silent)

        let sent = try #require(stub.requests.only)
        #expect(sent.url == stub.baseURL.appending(path: "audio/transcriptions"))
        #expect(sent.method == "POST")
        #expect(sent.headers["Authorization"] == "Bearer sk-or-test")
        let body = try sent.json()
        #expect(body["model"] as? String == "microsoft/mai-transcribe-2")
        #expect(body["language"] as? String == "en")
        #expect(body["provider"] as? [String: Bool] == ["zdr": true])
        let audio = try #require(body["input_audio"] as? [String: String])
        #expect(audio["format"] == "flac")
        let flac = try #require(audio["data"].flatMap { Data(base64Encoded: $0) })
        #expect(audio["data"] == OpenRouterProvider.primerAudio)
        #expect(flac.prefix(4) == Data("fLaC".utf8))
    }

    @Test func thePrimerReturnsItsAnswerForItsCost() async throws {
        let stub = StubHost(reply: .fixture("success"))

        let primer = try #require(
            await stub.provider().prime(language: Locale.Language(identifier: "en"), size: .silent))

        #expect(primer.model == "microsoft/mai-transcribe-2")
        #expect(primer.usage.cost == .reported(try #require(Decimal(string: "0.000344"))))
    }

    @Test func aFailedPrimerIsNil() async {
        let stub = StubHost(reply: .raw(status: 502, body: #"{"error":{"message":"Provider returned 500"}}"#))

        #expect(await stub.provider().prime(language: Locale.Language(identifier: "en"), size: .silent) == nil)
    }

    @Test func directRoutesSendNoPrimer() async {
        let stub = StubHost(reply: .fixture("success"))
        #expect(stub.provider().hasPrimer)
        stub.settings.route = .xaiGrok

        #expect(stub.provider().hasPrimer == false)
        #expect(await stub.provider().prime(language: Locale.Language(identifier: "en"), size: .silent) == nil)
        stub.useAzure()
        #expect(stub.provider().hasPrimer == false)
        #expect(await stub.provider().prime(language: Locale.Language(identifier: "en"), size: .silent) == nil)
        #expect(stub.requests.isEmpty)
    }

    // MARK: Large primer

    /// One second of 48 kHz stereo 32-bit noise as WAV: about 384 KB that does not compress, billed as one second.
    @Test func theLargePrimerSendsOneSecondOfNoiseAsWAV() async throws {
        let stub = StubHost(reply: .fixture("success"))

        _ = await stub.provider().prime(language: Locale.Language(identifier: "en"), size: .large)

        let body = try #require(stub.requests.only).json()
        #expect(body["model"] as? String == "microsoft/mai-transcribe-2")
        #expect(body["provider"] as? [String: Bool] == ["zdr": true])
        let audio = try #require(body["input_audio"] as? [String: String])
        #expect(audio["format"] == "wav")
        let wav = try #require(audio["data"].flatMap { Data(base64Encoded: $0) })
        #expect(wav.count == 384_044)  // 44 header bytes + 48,000 frames x 2 channels x 4 bytes
        #expect(wav.prefix(4) == Data("RIFF".utf8))
        #expect(wav[8..<16] == Data("WAVEfmt ".utf8))
        // Little-endian fields: 2 channels, 48 kHz, 32 bits.
        #expect(Array(wav[22..<24]) == [2, 0])
        #expect(Array(wav[24..<28]) == [0x80, 0xBB, 0x00, 0x00])
        #expect(Array(wav[34..<36]) == [32, 0])
        // The first samples of the WAV that MAI accepted on 2026-10-17 (billed one second; latency-pass.md 2.1).
        #expect(
            wav[44..<60]
                == Data([
                    0xF4, 0x65, 0xB9, 0xA1, 0x6A, 0x9E, 0x78, 0x6E, 0x4F, 0x45, 0x09, 0x80, 0x18, 0x5D, 0xC4, 0x06,
                ]))
    }

    /// The bodies are built once and kept: a later primer copies and encodes nothing.
    @Test func primerBodiesAreBuiltOnce() async throws {
        let stub = StubHost(reply: .fixture("success"))
        let provider = stub.provider()
        let english = Locale.Language(identifier: "en")

        _ = await provider.prime(language: english, size: .large)
        _ = await provider.prime(language: english, size: .large)
        _ = await provider.prime(language: english, size: .silent)
        _ = await provider.prime(language: english, size: .silent)

        let bodies = stub.requests.map(\.body)
        #expect(bodies.count == 4)
        #expect(bodies[0] == bodies[1])
        #expect(bodies[2] == bodies[3])
        #expect(provider.primerBodyBuilds == 2)
    }

    /// A kept body follows the request fields: a changed route option builds a new one.
    @Test func aChangedRouteOptionBuildsANewPrimerBody() async throws {
        let stub = StubHost(reply: .fixture("success"))
        stub.settings.route = .openRouterGrok
        let provider = stub.provider()
        let english = Locale.Language(identifier: "en")

        _ = await provider.prime(language: english, size: .silent)
        stub.settings.isGrokFormatOn = true
        _ = await provider.prime(language: english, size: .silent)

        #expect(provider.primerBodyBuilds == 2)
        #expect(try #require(stub.requests.last).json().xaiOptions["format"] as? Bool == true)
    }
}
