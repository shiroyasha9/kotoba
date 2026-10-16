import Foundation
import KotobaCore
import Synchronization

// The route primer (`TranscriptionProvider.prime`). After a quiet minute OpenRouter MAI answered about 1.6 s slower,
// and the key-down `HEAD` did not change that; a billed transcription did. A silent one warms most of the path; the
// rest warms only with the bytes sent, so a cold route gets a large one (docs/research/latency-pass.md, section 2.1).

extension OpenRouterProvider {
    var hasPrimer: Bool { true }

    /// The route's model, language and data policy and no dictionary terms, from a body built once (`PrimerBodies`). A
    /// failure only means the next answer pays the cold start.
    func prime(
        _ options: TranscriptionSettings.RouteOptions, language: Locale.Language, size: PrimerSize
    ) async -> Transcript? {
        let label = "primer \(options.route.rawValue)"
        let fields = Self.fields(terms: [], language: language, options: options)
        guard
            let body = try? primerBodies.body(size, fields: fields, make: Self.primerBody),
            let reply = try? await connection.send(
                baseURL.appending(path: "audio/transcriptions"), contentType: "application/json", label: label,
                body: .data(body)),
            let answer = try? ProviderHTTP.decode(OpenRouterAnswer.self, from: reply, label: label)
        else { return nil }
        let usage = TranscriptionUsage.priced(
            audio: answer.usage?.seconds.map { .seconds($0) }, cost: answer.usage?.charged,
            recorded: size == .silent ? .milliseconds(500) : .seconds(1), on: options.route)
        return Transcript(text: answer.text ?? "", usage: usage, model: options.route.rawValue)
    }

    var primerBodyBuilds: Int { primerBodies.builds }

    /// Half a second of 16 kHz mono silence as FLAC (110 bytes), in base64: `flac --best --no-padding --no-seektable`
    /// on the output of `ffmpeg -f lavfi -i anullsrc=r=16000:cl=mono -t 0.5 -c:a pcm_s16le`. MAI bills it as one
    /// second.
    static let primerAudio =
        "ZkxhQwAAACIQABAAAAALAAANA+gA8AAAH0Ae4Bk2cWCcfWPP6JuSCtMThAAAKCAAAAByZWZlcmVuY2UgbGliRkxBQyAxLjUuMCAyMDI1"
        + "MDIxMQAAAAD/+MUIAG8AAABlVf/4dQgBDz/iAAAAZoI="

    /// The JSON body: `input_audio` first, then the other fields. The large one is built in one buffer of its final
    /// size, its WAV made and base64-encoded in place, so the kept body is all the build leaves in memory
    /// (latency-pass.md, section 3).
    private static func primerBody(_ size: PrimerSize, fields: RequestFields) throws -> Data {
        let format = size == .silent ? "flac" : "wav"
        let prefix = Data(#"{"input_audio":{"format":"\#(format)","data":""#.utf8)
        let suffix = Data(#""},"#.utf8) + (try ProviderHTTP.encode(fields).dropFirst())  // Drop the object's "{".
        guard size == .large else { return prefix + Data(primerAudio.utf8) + suffix }
        var body = Data(count: prefix.count + Base64Writer.length(of: noiseWAVBytes) + suffix.count)
        body.withUnsafeMutableBytes { out in
            out.copyBytes(from: prefix)
            var writer = Base64Writer(into: out, at: prefix.count)
            writeNoiseWAV { writer.append($0) }
            let end = writer.finish()
            assert(end + suffix.count == out.count, "the body's size is exact")
            UnsafeMutableRawBufferPointer(rebasing: out[end...]).copyBytes(from: suffix)
        }
        return body
    }

    /// 44 header bytes and one second of 48 kHz stereo 32-bit samples.
    static let noiseWAVBytes = 44 + 48_000 * 2 * 4

    /// One second of full-scale white noise as a 48 kHz stereo 32-bit PCM WAV (`noiseWAVBytes`), handed to `write` a
    /// few bytes at a time. Random samples do not compress, so every byte goes up the route, as the probe's
    /// `noise-1s-48k-s32.wav` did. SplitMix64 with a fixed seed: the same bytes every launch.
    static func writeNoiseWAV(_ write: (UnsafeRawBufferPointer) -> Void) {
        let (rate, channels, sampleBytes) = (48_000, 2, 4)
        let dataBytes = rate * channels * sampleBytes
        func append<Integer: FixedWidthInteger>(_ value: Integer) {
            withUnsafeBytes(of: value.littleEndian, write)
        }
        func append(_ text: String) {
            Array(text.utf8).withUnsafeBytes(write)
        }
        append("RIFF")
        append(UInt32(36 + dataBytes))
        append("WAVEfmt ")
        append(UInt32(16))  // PCM fmt chunk size
        append(UInt16(1))  // PCM
        append(UInt16(channels))
        append(UInt32(rate))
        append(UInt32(rate * channels * sampleBytes))  // bytes per second
        append(UInt16(channels * sampleBytes))  // block align
        append(UInt16(sampleBytes * 8))
        append("data")
        append(UInt32(dataBytes))
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for _ in 0..<(dataBytes / 8) {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = (state ^ (state >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            append(mixed ^ (mixed >> 31))
        }
    }
}

/// Base64 written in place into a buffer of the final size, so no piece is allocated.
private struct Base64Writer {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    private let out: UnsafeMutableRawBufferPointer
    private var offset: Int
    private var carry: UInt32 = 0
    private var held = 0

    init(into out: UnsafeMutableRawBufferPointer, at offset: Int) {
        self.out = out
        self.offset = offset
    }

    static func length(of bytes: Int) -> Int { (bytes + 2) / 3 * 4 }

    mutating func append(_ bytes: UnsafeRawBufferPointer) {
        for byte in bytes {
            carry = carry << 8 | UInt32(byte)
            held += 1
            if held == 3 { emit(4) }
        }
    }

    /// Pads the last group; returns the offset after it.
    mutating func finish() -> Int {
        guard held > 0 else { return offset }
        let missing = 3 - held
        carry <<= UInt32(8 * missing)
        emit(4 - missing)
        for _ in 0..<missing {
            out[offset] = UInt8(ascii: "=")
            offset += 1
        }
        return offset
    }

    private mutating func emit(_ count: Int) {
        for index in 0..<count {
            out[offset + index] = Self.alphabet[Int(carry >> UInt32(18 - 6 * index) & 0x3F)]
        }
        offset += count
        carry = 0
        held = 0
    }
}

/// The primer bodies, one per size for the last request fields (route, language, data policy, route options): built at
/// the first primer of that kind and kept, so a primer copies no audio and encodes nothing. The large one holds about
/// 512 KB (its base64).
final class PrimerBodies: Sendable {
    private let kept = Mutex<(bodies: [PrimerSize: (fields: RequestFields, body: Data)], builds: Int)>(([:], 0))

    var builds: Int { kept.withLock { $0.builds } }

    func body(
        _ size: PrimerSize, fields: RequestFields, make: (PrimerSize, RequestFields) throws -> Data
    ) throws -> Data {
        if let entry = kept.withLock({ $0.bodies[size] }), entry.fields == fields { return entry.body }
        let body = try make(size, fields)
        kept.withLock {
            $0.bodies[size] = (fields, body)
            $0.builds += 1
        }
        return body
    }
}
