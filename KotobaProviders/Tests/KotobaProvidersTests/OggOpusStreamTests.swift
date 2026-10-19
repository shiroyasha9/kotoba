import AVFAudio
import Foundation
import Testing

@testable import KotobaProviders

/// The Ogg framing of the Opus upload copy (`OggOpusStream`): the system's decoder reads the file back at the audio's
/// own length, and the header bytes are those ffmpeg checked with `-err_detect crccheck` (2026-10-19).
struct OggOpusStreamTests {
    @Test func theHeaderPagesAreTheCheckedBytes() {
        let stream = OggOpusStream(inputSampleRate: 16_000, preSkip: 104, serial: 0x6b6f_746f)

        let expected =
            "4f676753000200000000000000006f746f6b0000000045dfec6501134f7075734865616401013801803e0000000000"
            + "4f676753000000000000000000006f746f6b0100000002e0ffa301164f70757354616773060000006b6f746f626100000000"
        #expect(stream.header.hex == expected)
    }

    /// The decoder drops the encoder's priming (pre-skip) and its padding (the last page's granule), so the copy is
    /// as long as the recording, in 48 kHz samples.
    @Test func theSystemDecoderReadsTheCopyAtTheRecordingsLength() throws {
        let frames = 16_000 * 2 + 123
        let file = FileManager.default.temporaryDirectory.appending(path: "ogg-opus-\(UUID().uuidString).ogg")
        defer { try? FileManager.default.removeItem(at: file) }

        try Self.encode(tone(frames: frames)).write(to: file)

        let decoded = try AVAudioFile(forReading: file)
        #expect(decoded.fileFormat.sampleRate == 48_000)
        #expect(decoded.length == AVAudioFramePosition(frames * 3))
    }

    @Test func aPacketOfManyBytesTakesALacingValuePer255AndOneMore() throws {
        var stream = OggOpusStream(inputSampleRate: 16_000, preSkip: 0, serial: 1)

        #expect(stream.append(Data(count: 255), frames: 320) == nil)
        #expect(stream.append(Data(count: 600), frames: 320) == nil)
        let page = stream.finish(inputFrames: 640)

        #expect(page[26] == 5)  // Segment count.
        #expect(Array(page[27..<32]) == [255, 0, 255, 255, 90])
        #expect(page.count == 27 + 5 + 855)
        #expect(page[5] == 0x04)  // End of stream.
        #expect(page.oggGranule == 640 * 3)
    }

    @Test func aPageEndsBefore255LacingValues() throws {
        var stream = OggOpusStream(inputSampleRate: 16_000, preSkip: 0, serial: 1)
        // Each packet takes six lacing values: 42 fit (252), the 43rd starts the next page.
        let pages = (0..<43).compactMap { _ in stream.append(Data(count: 1_300), frames: 320) }

        let page = try #require(pages.only)
        #expect(page[26] == 252)
        #expect(page.oggGranule == 42 * 320 * 3)
        #expect(stream.finish(inputFrames: 43 * 320).oggGranule == 43 * 320 * 3)
    }

    /// The granule counts every sample the packets hold, the encoder's priming too: the decoder subtracts the
    /// pre-skip.
    @Test func aPageCarriesASecondOfPackets() throws {
        var stream = OggOpusStream(inputSampleRate: 16_000, preSkip: 104, serial: 1)

        let pages = (0..<OggOpusStream.packetsPerPage).compactMap { _ in stream.append(Data(count: 60), frames: 320) }

        let page = try #require(pages.only)
        #expect(page[26] == UInt8(OggOpusStream.packetsPerPage))
        #expect(page.oggGranule == Int64(OggOpusStream.packetsPerPage * 320 * 3))
        #expect(page[18..<22] == Data([2, 0, 0, 0]))  // Sequence: after the two header pages.
    }

    // MARK: Helpers

    /// `frames` of a 440 Hz tone at 16 kHz mono Int16.
    private func tone(frames: Int) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = try #require(buffer.int16ChannelData?[0])
        for index in 0..<frames {
            samples[index] = Int16(8_000 * sin(2 * Double.pi * 440 * Double(index) / 16_000))
        }
        return buffer
    }

    /// The buffer as Opus packets from the system encoder, framed by `OggOpusStream`.
    private static func encode(_ buffer: AVAudioPCMBuffer) throws -> Data {
        var description = AudioStreamBasicDescription(
            mSampleRate: 16_000, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: 320, mBytesPerFrame: 0, mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
        let opus = try #require(AVAudioFormat(streamDescription: &description))
        let converter = try #require(AVAudioConverter(from: buffer.format, to: opus))
        converter.bitRate = 24_000
        let packets = AVAudioCompressedBuffer(
            format: opus, packetCapacity: 64, maximumPacketSize: converter.maximumOutputPacketSize)
        var stream = OggOpusStream(inputSampleRate: 16_000, preSkip: Int(converter.primeInfo.leadingFrames))
        var file = stream.header
        var isFed = false
        var status: AVAudioConverterOutputStatus
        repeat {
            status = converter.convert(to: packets, error: nil) { _, inputStatus in
                if isFed {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                isFed = true
                inputStatus.pointee = .haveData
                return buffer
            }
            let descriptions = try #require(packets.packetDescriptions)
            for index in 0..<Int(packets.packetCount) {
                let packet = Data(
                    bytes: packets.data.advanced(by: Int(descriptions[index].mStartOffset)),
                    count: Int(descriptions[index].mDataByteSize))
                file += stream.append(packet, frames: 320) ?? Data()
            }
        } while status == .haveData
        #expect(status == .endOfStream)
        return file + stream.finish(inputFrames: Int(buffer.frameLength))
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }

    /// An Ogg page's granule position.
    var oggGranule: Int64 {
        self[startIndex + 6..<startIndex + 14].enumerated().reduce(Int64(0)) {
            $0 | Int64($1.element) << (8 * $1.offset)
        }
    }
}
