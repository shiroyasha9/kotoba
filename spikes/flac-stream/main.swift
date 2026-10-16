// FLAC stream spike (L2 in docs/research/quality-perf-2.md): does AVAudioFile write FLAC frames as it goes, and what
// does the header hold before close? Writes a 16 kHz mono Int16 WAV to FLAC with the app's settings
// (App/CaptureWriter.swift), 1,600 frames (100 ms) per write, at real-time pace or as fast as it can. After every
// write it prints one JSON line with the file size on disk, so a reader (stream.ts) can send the new bytes. With
// --snapshots DIR it copies the file after the first write, halfway, after the last write (before close) and after
// close. Usage: writer IN.wav OUT.flac [--realtime] [--snapshots DIR]
import AVFoundation
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: writer IN.wav OUT.flac [--realtime] [--snapshots DIR]\n".utf8))
    exit(2)
}
let input = URL(filePath: arguments[1])
let output = URL(filePath: arguments[2])
let isRealtime = arguments.contains("--realtime")
let snapshots = arguments.firstIndex(of: "--snapshots").map { URL(filePath: arguments[$0 + 1]) }
let chunk: AVAudioFrameCount = 1_600

func size() -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: output.path)[.size]) as? Int) ?? -1
}

func emit(_ fields: [String: Any]) {
    var line = fields
    line["t"] = Date().timeIntervalSince1970
    line["size"] = size()
    let data = try! JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

func snapshot(_ name: String) {
    guard let snapshots else { return }
    let target = snapshots.appending(path: "\(output.deletingPathExtension().lastPathComponent)-\(name).flac")
    try? FileManager.default.removeItem(at: target)
    try! FileManager.default.copyItem(at: output, to: target)
}

let source = try AVAudioFile(forReading: input, commonFormat: .pcmFormatInt16, interleaved: true)
precondition(source.fileFormat.sampleRate == 16_000 && source.fileFormat.channelCount == 1, "want 16 kHz mono")
try? FileManager.default.removeItem(at: output)
let file = try AVAudioFile(
    forWriting: output,
    settings: [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1],
    commonFormat: .pcmFormatInt16,
    interleaved: true
)
emit(["event": "open"])
let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: chunk)!
let totalWrites = Int((source.length + Int64(chunk) - 1) / Int64(chunk))
let start = Date()
var writes = 0
while source.framePosition < source.length {
    if isRealtime {
        // A chunk is written once its 100 ms have been recorded, as in the app.
        Thread.sleep(until: start.addingTimeInterval(Double(writes + 1) * Double(chunk) / 16_000))
    }
    try source.read(into: buffer, frameCount: chunk)
    try file.write(from: buffer)
    writes += 1
    emit(["event": "write", "writes": writes, "frames": file.length])
    if writes == 1 { snapshot("first") }
    if writes == totalWrites / 2 { snapshot("half") }
}
snapshot("open")
emit(["event": "stop", "frames": file.length])
file.close()
emit(["event": "closed"])
snapshot("closed")
