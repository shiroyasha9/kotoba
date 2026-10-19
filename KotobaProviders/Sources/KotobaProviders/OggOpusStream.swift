import Foundation

/// Ogg framing (RFC 3533) of one Opus stream (RFC 7845): the two header pages, then audio pages of whole packets. The
/// capture frames the upload copy of a recording with it (`OpusUploadWriter` in App/): MAI through OpenRouter takes
/// Ogg Opus, about a fifth of the FLAC's bytes, and answers faster for it (docs/research/latency-pass-2.md). The
/// system's file writer has no Ogg output (ExtAudioFile fails with 'fmt?', 2026-10-19), so kotoba writes the pages.
public struct OggOpusStream {
    /// Opus counts time in 48 kHz samples, whatever the input rate (RFC 7845 section 4).
    static let granuleRate = 48_000
    /// About a second of 20 ms packets per page: few pages, and a crash loses at most that much of the copy.
    static let packetsPerPage = 50

    private let serial: UInt32
    private let samplesPerFrame: Int64
    private let preSkip: Int64
    private var sequence: UInt32 = 0
    private var pending: [Data] = []
    private var pendingSegments = 0
    /// 48 kHz samples up to the end of the last packet appended, priming included.
    private var granule: Int64

    /// The two header pages, written first.
    public private(set) var header = Data()

    /// `preSkip` is the encoder's priming in input frames (`AVAudioConverter.primeInfo.leadingFrames`).
    public init(inputSampleRate: Int, preSkip: Int, serial: UInt32 = .random(in: .min ... .max)) {
        precondition(Self.granuleRate % inputSampleRate == 0, "Opus input rates divide 48 kHz")
        self.serial = serial
        samplesPerFrame = Int64(Self.granuleRate / inputSampleRate)
        self.preSkip = Int64(preSkip) * samplesPerFrame
        granule = 0
        header = page([Self.identification(inputSampleRate: inputSampleRate, preSkip: self.preSkip)], flags: 0x02)
        header += page([Self.comment], flags: 0)
    }

    /// Adds one Opus packet that holds `frames` input frames. Returns a finished page when one filled, else nil.
    public mutating func append(_ packet: Data, frames: Int) -> Data? {
        let segments = packet.count / 255 + 1
        // A page holds at most 255 lacing values.
        let full = pendingSegments + segments > 255 ? flush(flags: 0) : nil
        pending.append(packet)
        pendingSegments += segments
        granule += Int64(frames) * samplesPerFrame
        if let full { return full }
        return pending.count >= Self.packetsPerPage ? flush(flags: 0) : nil
    }

    /// The last page, marked as the end of the stream. Its granule is the audio's own length (`inputFrames`), so a
    /// decoder drops the encoder's padding after it (RFC 7845 section 4.5).
    public mutating func finish(inputFrames: Int) -> Data {
        granule = min(granule, preSkip + Int64(inputFrames) * samplesPerFrame)
        return flush(flags: 0x04)
    }

    private mutating func flush(flags: UInt8) -> Data {
        defer {
            pending.removeAll(keepingCapacity: true)
            pendingSegments = 0
        }
        return page(pending, flags: flags, granule: granule)
    }

    private mutating func page(_ packets: [Data], flags: UInt8, granule: Int64 = 0) -> Data {
        var lacing: [UInt8] = []
        for packet in packets {
            lacing += [UInt8](repeating: 255, count: packet.count / 255) + [UInt8(packet.count % 255)]
        }
        var page = Data("OggS".utf8)
        page.append(0)  // Version.
        page.append(flags)
        page.appendLittleEndian(granule)
        page.appendLittleEndian(serial)
        page.appendLittleEndian(sequence)
        page.appendLittleEndian(UInt32(0))  // The CRC, set below over the whole page with this field zero.
        page.append(UInt8(lacing.count))
        page.append(contentsOf: lacing)
        for packet in packets { page.append(packet) }
        let crc = Self.crc(page)
        page.replaceSubrange(22..<26, with: withUnsafeBytes(of: crc.littleEndian) { Data($0) })
        sequence += 1
        return page
    }

    /// "OpusHead": version 1, one channel, the priming, the input rate, no gain, mapping family 0 (RFC 7845 5.1).
    private static func identification(inputSampleRate: Int, preSkip: Int64) -> Data {
        var head = Data("OpusHead".utf8)
        head.append(1)
        head.append(1)
        head.appendLittleEndian(UInt16(preSkip))
        head.appendLittleEndian(UInt32(inputSampleRate))
        head.appendLittleEndian(UInt16(0))
        head.append(0)
        return head
    }

    /// "OpusTags": the vendor and no comments (RFC 7845 5.2).
    private static let comment: Data = {
        let vendor = Data("kotoba".utf8)
        var tags = Data("OpusTags".utf8)
        tags.appendLittleEndian(UInt32(vendor.count))
        tags.append(vendor)
        tags.appendLittleEndian(UInt32(0))
        return tags
    }()

    /// Ogg's CRC-32: polynomial 0x04C11DB7, initial value 0, no reflection, no final XOR (RFC 3533 section 6).
    static func crc(_ bytes: Data) -> UInt32 {
        bytes.reduce(UInt32(0)) { crc, byte in (crc << 8) ^ crcTable[Int((crc >> 24) ^ UInt32(byte))] }
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index) << 24) { value, _ in
            value & 0x8000_0000 != 0 ? (value << 1) ^ 0x04C1_1DB7 : value << 1
        }
    }
}

extension Data {
    mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
