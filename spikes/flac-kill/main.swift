// Orphan audio spike (5.4 in docs/research/phase3-plan.md): what does a FLAC look like when the process that writes it
// with AVAudioFile dies before close (a crash, a force quit), and can kotoba read it back?
//
// Result (2026-10-16, macOS 26, no paid call): the frames written before the kill are on disk, but bytes 4-41 (the
// STREAMINFO block header and body) are all zero; the VORBIS_COMMENT block and the frames follow as in a closed file.
// AVAudioFile does not open it ('fmt?'), and `flac -t` and ffprobe refuse it; the L2 spike (spikes/flac-stream) found
// that MAI refuses a FLAC with total samples 0. A kill after 5 s kept 73,728 of 81,600 frames, after 30 s 474,624 of
// 480,000 (the encoder's buffer, under 0.5 s, is lost); a kill after 0.3 s left an empty file. `repair` (STREAMINFO with
// rate, channels, bits and block size, the rest 0) opens with length 0 and reads every frame on disk; the frames written
// to a new AVAudioFile and closed give a file that `flac -t` passes, with the same samples as the closed file's first
// 73,728 (ffmpeg decode, cmp). That file is what a normal stop writes, which MAI accepts. Rewrite time: 28 ms for 4.6 s
// and 42 ms for 29.7 s (first run in the process, codec load included). A copy cut 550 bytes short (a power loss
// mid-write) reads 69,120 frames: the cut frame is dropped. A copy with 400 bytes overwritten mid-file reads 470,016
// frames: the decoder skips the damaged frame and reads on. Each read ends with a failed read past the last frame.
//   probe write OUT.flac SECONDS   writes a tone with the app's settings (App/CaptureWriter.swift: 16 kHz mono Int16,
//                                  4,800 frames per write), then SIGKILLs itself, so the file is never closed.
//                                  With --close it closes the file instead, for comparison.
//   probe read IN.flac             prints the STREAMINFO bytes, then what AVAudioFile reads: length, format, frames.
//   probe repair IN.flac OUT.flac  writes the STREAMINFO the app's settings fix (block size 4,608, 16 kHz, mono,
//                                  16 bits; frame sizes, total samples and MD5 0, "unknown" in RFC 9639) into a copy,
//                                  reads it with AVAudioFile and writes the frames it reads to a new, closed FLAC.
import AVFoundation
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: probe write OUT.flac SECONDS | probe read IN.flac\n".utf8))
    exit(2)
}
let url = URL(filePath: arguments[2])
let chunk: AVAudioFrameCount = 4_800
let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

switch arguments[1] {
case "write":
    let seconds = Double(arguments[3])!
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(
        forWriting: url,
        settings: [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1],
        commonFormat: .pcmFormatInt16,
        interleaved: true
    )
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
    buffer.frameLength = chunk
    var written = 0
    while Double(written) < seconds * 16_000 {
        let samples = buffer.int16ChannelData![0]
        for index in 0..<Int(chunk) {
            // A 440 Hz tone with a slow wobble, so the encoder cannot fold frames into constants.
            let time = Double(written + index) / 16_000
            samples[index] = Int16(8_000 * sin(2 * .pi * 440 * time) * (0.6 + 0.4 * sin(2 * .pi * 0.7 * time)))
        }
        try file.write(from: buffer)
        written += Int(chunk)
    }
    if arguments.contains("--close") {
        file.close()
        print("wrote \(written) frames, closed")
    } else {
        print("wrote \(written) frames, length \(file.length); killing before close")
        kill(getpid(), SIGKILL)
    }
case "read":
    let data = try Data(contentsOf: url)
    print("size \(data.count) bytes")
    print("head \(data.prefix(42).map { String(format: "%02x", $0) }.joined())")
    do {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        print("open ok: length \(file.length), rate \(file.fileFormat.sampleRate), channels \(file.fileFormat.channelCount)")
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk)!
        var frames = 0
        do {
            while true {
                try file.read(into: buffer, frameCount: chunk)
                if buffer.frameLength == 0 { break }
                frames += Int(buffer.frameLength)
            }
            print("read \(frames) frames")
        } catch {
            print("read stopped after \(frames) frames: \(error)")
        }
    } catch {
        print("open failed: \(error)")
    }
case "repair":
    var data = try Data(contentsOf: url)
    var header = [UInt8](repeating: 0, count: 38)
    // Block header: STREAMINFO (type 0), not the last block (VORBIS_COMMENT follows), 34 bytes.
    header[0...3] = [0x00, 0x00, 0x00, 0x22]
    // Min and max block size 4,608 (0x1200); min and max frame size 0 (unknown).
    header[4...7] = [0x12, 0x00, 0x12, 0x00]
    // 20 bits rate (16,000 = 0x03E80), 3 bits channels - 1 (0), 5 bits bits - 1 (15), 36 bits total samples (0).
    header[14...17] = [0x03, 0xE8, 0x00, 0xF0]
    data.replaceSubrange(4..<42, with: header)
    let patched = url.deletingPathExtension().appendingPathExtension("patched.flac")
    try data.write(to: patched)
    let source = try AVAudioFile(forReading: patched, commonFormat: .pcmFormatInt16, interleaved: true)
    print("patched open ok: length \(source.length)")
    let output = URL(filePath: arguments[3])
    try? FileManager.default.removeItem(at: output)
    let started = Date()
    var frames = 0
    do {
        let target = try AVAudioFile(
            forWriting: output,
            settings: [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1],
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: chunk)!
        do {
            while true {
                try source.read(into: buffer, frameCount: chunk)
                if buffer.frameLength == 0 { break }
                try target.write(from: buffer)
                frames += Int(buffer.frameLength)
            }
        } catch {
            print("read stopped after \(frames) frames: \(error)")
        }
        target.close()
    }
    print("rewrote \(frames) frames in \(Int(Date().timeIntervalSince(started) * 1_000_000)) µs")
default:
    exit(2)
}
