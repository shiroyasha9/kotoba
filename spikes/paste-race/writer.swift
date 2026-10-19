// Throwaway spike (2026-10-19, docs/research/paste-restore.md): restore timing against a reader on a private pasteboard.
// Build: swiftc -O -swift-version 5 reader.swift -o reader; swiftc -O -swift-version 5 writer.swift -o writer
// Run: ./writer now|finished|never|settle:<ms> <trials> ./reader
// Writer: promises a transcript on a named pasteboard, asks the reader to read it, and restores the "old" clipboard
// at a variant's moment. Counts reads that got the transcript, the old text, or nothing.
import AppKit

let name = NSPasteboard.Name("tech.teensy.kotoba.spike.race")
let board = NSPasteboard(name: name)
let trials = Int(CommandLine.arguments[2]) ?? 200
let variant = CommandLine.arguments[1]  // now | finished | settle:<ms>

final class Promise: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    let text: String
    let onRead: () -> Void
    let onFinished: () -> Void
    init(_ text: String, onRead: @escaping () -> Void, onFinished: @escaping () -> Void) {
        self.text = text; self.onRead = onRead; self.onFinished = onFinished
    }
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString(text, forType: type)
        onRead()
    }
    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) { onFinished() }
}

let reader = Process()
reader.executableURL = URL(fileURLWithPath: CommandLine.arguments[3])
reader.arguments = [name.rawValue]
let toReader = Pipe(), fromReader = Pipe()
reader.standardInput = toReader
reader.standardOutput = fromReader
try! reader.run()
let lines = fromReader.fileHandleForReading

func readLine(from handle: FileHandle) -> String {
    var bytes = Data()
    while true {
        let byte = handle.readData(ofLength: 1)
        if byte.isEmpty || byte == Data([10]) { break }
        bytes.append(byte)
    }
    return String(decoding: bytes, as: UTF8.self)
}

func restore(_ count: Int) {
    guard board.changeCount == count else { return }
    board.clearContents()
    board.setString("OLD", forType: .string)
}

DispatchQueue.global().async {
    var got: [String: Int] = [:]
    var finishedAfterRead: [Double] = []
    var gaps: [Double] = []
    var promise: Promise?
    for i in 0..<trials {
        let text = "NEW \(i)"
        let readAt = Atomic()
        let done = DispatchSemaphore(value: 0)
        var count = 0
        DispatchQueue.main.sync {
            board.clearContents()
            let item = NSPasteboardItem()
            item.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
            promise = Promise(text, onRead: {
                readAt.set(DispatchTime.now().uptimeNanoseconds)
                switch variant {
                case "now":
                    DispatchQueue.global().async { restore(count); done.signal() }
                case let v where v.hasPrefix("settle:"):
                    let ms = Int(v.dropFirst(7))!
                    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(ms)) { restore(count); done.signal() }
                default: break
                }
            }, onFinished: {
                let r = readAt.get()
                if r > 0 { finishedAfterRead.append(Double(DispatchTime.now().uptimeNanoseconds - r) / 1e6) }
                if variant == "finished" { DispatchQueue.global().async { restore(count); done.signal() } }
            })
            item.setDataProvider(promise!, forTypes: [.string])
            board.writeObjects([item])
            count = board.changeCount
        }
        toReader.fileHandleForWriting.write("go\n".data(using: .utf8)!)
        let line = readLine(from: lines)
        let space = line.firstIndex(of: " ")!
        let gotAt = UInt64(line[..<space])!
        let answer = String(line[line.index(after: space)...])
        if readAt.get() > 0, gotAt > readAt.get() { gaps.append(Double(gotAt - readAt.get()) / 1e6) }
        let key = answer == text ? "transcript" : answer == "NIL" ? "nothing" : answer == "OLD" ? "old" : "other:\(answer)"
        got[key, default: 0] += 1
        if variant != "never", done.wait(timeout: .now() + 2) == .timedOut { got["no-restore", default: 0] += 1 }
    }
    let f = finishedAfterRead.sorted()
    let med = f.isEmpty ? -1 : f[f.count / 2]
    let g = gaps.sorted()
    func p(_ q: Double) -> Double { g.isEmpty ? -1 : g[min(g.count - 1, Int(Double(g.count) * q))] }
    print("read signal -> reader has data (ms): n=\(g.count) p50=\(p(0.5)) p90=\(p(0.9)) p99=\(p(0.99)) max=\(g.last ?? -1)")
    print("\(variant): \(got.sorted { $0.key < $1.key }) finishedWithDataProvider after read: n=\(f.count) median=\(med) ms")
    exit(0)
}

final class Atomic: @unchecked Sendable {
    private var v: UInt64 = 0
    private let lock = NSLock()
    func set(_ x: UInt64) { lock.lock(); v = x; lock.unlock() }
    func get() -> UInt64 { lock.lock(); defer { lock.unlock() }; return v }
}

RunLoop.main.run()
