import AVFAudio
import Foundation
import KotobaProviders

/// The upload copy of a recording: Opus at 24 kbps in Ogg, encoded chunk by chunk on the capture writer's thread as the
/// FLAC is written, so the stop adds only the last chunk's encode (Apple's encoder runs at about 145x real time; the
/// whole of a 20 s recording at the stop would cost about 140 ms). MAI through OpenRouter answers about 240 ms sooner
/// for it at the same WER (docs/research/latency-pass-2.md). The FLAC stays the kept recording.
final class OpusUploadWriter {
    /// Speech at 24 kbps kept the WER of FLAC on 80 bench clips (5.71% against 5.68%).
    static let bitRate = 24_000

    private let url: URL
    private let output: FileHandle
    private let converter: AVAudioConverter
    private let packets: AVAudioCompressedBuffer
    private let framesPerPacket: Int
    private var stream: OggOpusStream
    private var inputFrames = 0

    /// `format` is the capture's 16 kHz mono Int16 (`CaptureWriter.outputFormat`).
    init(file url: URL, format: AVAudioFormat) throws {
        var description = AudioStreamBasicDescription(
            mSampleRate: format.sampleRate, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
            // 20 ms packets.
            mFramesPerPacket: UInt32(format.sampleRate / 50), mBytesPerFrame: 0,
            mChannelsPerFrame: format.channelCount, mBitsPerChannel: 0, mReserved: 0)
        guard let opus = AVAudioFormat(streamDescription: &description),
            let converter = AVAudioConverter(from: format, to: opus)
        else { throw CocoaError(.featureUnsupported) }
        converter.bitRate = Self.bitRate
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        self.url = url
        output = try FileHandle(forWritingTo: url)
        self.converter = converter
        framesPerPacket = Int(description.mFramesPerPacket)
        packets = AVAudioCompressedBuffer(
            format: opus, packetCapacity: 32, maximumPacketSize: converter.maximumOutputPacketSize)
        stream = OggOpusStream(
            inputSampleRate: Int(format.sampleRate), preSkip: Int(converter.primeInfo.leadingFrames))
        try output.write(contentsOf: stream.header)
    }

    deinit {
        // `close` writes the last page first; a copy that never closed is not uploaded.
        try? output.close()
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        inputFrames += Int(buffer.frameLength)
        var isFed = false
        try encode { _, status in
            if isFed {
                status.pointee = .noDataNow
                return nil
            }
            isFed = true
            status.pointee = .haveData
            return buffer
        }
    }

    /// Encodes what the encoder still holds, writes the last page and closes the file.
    func close() throws -> URL {
        try encode { _, status in
            status.pointee = .endOfStream
            return nil
        }
        try output.write(contentsOf: stream.finish(inputFrames: inputFrames))
        try output.close()
        return url
    }

    private func encode(_ input: AVAudioConverterInputBlock) throws {
        var status: AVAudioConverterOutputStatus
        repeat {
            var error: NSError?
            status = converter.convert(to: packets, error: &error, withInputFrom: input)
            if status == .error { throw error ?? CocoaError(.coderInvalidValue) }
            try writePackets()
        } while status == .haveData
    }

    private func writePackets() throws {
        guard let descriptions = packets.packetDescriptions else { return }
        for index in 0..<Int(packets.packetCount) {
            let description = descriptions[index]
            let packet = Data(
                bytes: packets.data.advanced(by: Int(description.mStartOffset)), count: Int(description.mDataByteSize))
            if let page = stream.append(packet, frames: framesPerPacket) {
                try output.write(contentsOf: page)
            }
        }
    }
}

/// Makes the upload copy of a kept FLAC for a request whose recording has none (a retry, History, a segment upload's
/// fallback): the FLAC read back through the same writer, at about 145x real time, so an hour costs about 25 s of one
/// core. Only a FLAC in the capture's format is read; another throws, and the FLAC goes.
struct OpusCopyEncoder: UploadCopyEncoder {
    /// 0.3 s at 16 kHz: the Ogg pages follow the encoder's packets, so any read size gives the same copy.
    private static let chunk: AVAudioFrameCount = 4_800

    func encodeCopy(of flac: URL, to copy: URL) async throws {
        let format = CaptureWriter.outputFormat
        let file = try AVAudioFile(forReading: flac, commonFormat: format.commonFormat, interleaved: true)
        guard file.processingFormat.sampleRate == format.sampleRate,
            file.processingFormat.channelCount == format.channelCount,
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: Self.chunk)
        else { throw CocoaError(.featureUnsupported) }
        let writer = try OpusUploadWriter(file: copy, format: file.processingFormat)
        while file.framePosition < file.length {
            // A cancelled request stops here; the provider removes the part written.
            try Task.checkCancellation()
            // The reads' autoreleased objects drain per chunk, not after the whole recording.
            try autoreleasepool {
                try file.read(into: buffer, frameCount: Self.chunk)
                try writer.write(buffer)
            }
            await Task.yield()
        }
        _ = try writer.close()
    }
}
