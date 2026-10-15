// Throwaway spike: how long does stop wait for the audio that covers the stop moment?
// Compares an input tap (current app) with an AVAudioSinkNode (IO-cycle buffers). 10 stops each.
// Usage: open -g -n build/StopLatency.app --args <out-file>
import AVFAudio
import AppKit
import Synchronization

let out = CommandLine.arguments.dropFirst().first ?? "/dev/null"
func log(_ line: String) {
    if let handle = FileHandle(forWritingAtPath: out) {
        handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close()
    } else { try? Data((line + "\n").utf8).write(to: URL(filePath: out)) }
}
func ms(_ host: UInt64) -> Double { AVAudioTime.seconds(forHostTime: host) * 1000 }

let lastEnd = Atomic<UInt64>(0)
let cycleFrames = Atomic<UInt32>(0)
let signal = DispatchSemaphore(value: 0)

func measure(_ name: String, engine: AVAudioEngine) {
    var waits: [Double] = []
    for _ in 0..<10 {
        Thread.sleep(forTimeInterval: Double.random(in: 0.3...0.6))
        let stop = mach_absolute_time()
        while lastEnd.load(ordering: .acquiring) < stop { _ = signal.wait(timeout: .now() + 1) }
        waits.append(ms(mach_absolute_time() - stop))
    }
    let sorted = waits.sorted()
    log(String(format: "%@: frames/callback %u, stop wait p50 %.1f ms, p90 %.1f ms, max %.1f ms, all %@", name,
               cycleFrames.load(ordering: .relaxed), sorted[4], sorted[8], sorted[9],
               waits.map { String(format: "%.1f", $0) }.joined(separator: " ")))
}

Thread.detachNewThread {
    // 1. Input tap, as the app does today.
    let tapEngine = AVAudioEngine()
    let input = tapEngine.inputNode
    let format = input.outputFormat(forBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
        cycleFrames.store(buffer.frameLength, ordering: .relaxed)
        let end = time.hostTime + AVAudioTime.hostTime(forSeconds: Double(buffer.frameLength) / format.sampleRate)
        lastEnd.store(end, ordering: .releasing)
        signal.signal()
    }
    do { try tapEngine.start() } catch { log("tap start failed: \(error)"); exit(1) }
    Thread.sleep(forTimeInterval: 1)
    measure("tap(1024)", engine: tapEngine)
    tapEngine.stop(); input.removeTap(onBus: 0)
    lastEnd.store(0, ordering: .releasing)

    // 2. Sink node: called on the IO thread once per hardware cycle.
    let sinkEngine = AVAudioEngine()
    let sinkFormat = sinkEngine.inputNode.outputFormat(forBus: 0)
    let sink = AVAudioSinkNode { timestamp, frames, _ in
        cycleFrames.store(frames, ordering: .relaxed)
        let end = timestamp.pointee.mHostTime + AVAudioTime.hostTime(forSeconds: Double(frames) / sinkFormat.sampleRate)
        lastEnd.store(end, ordering: .releasing)
        signal.signal()
        return noErr
    }
    sinkEngine.attach(sink)
    sinkEngine.connect(sinkEngine.inputNode, to: sink, format: sinkFormat)
    do { try sinkEngine.start() } catch { log("sink start failed: \(error)"); exit(1) }
    Thread.sleep(forTimeInterval: 1)
    measure("sink", engine: sinkEngine)
    sinkEngine.stop()

    // 3. The app's full stop path, 10 dictations: start, speak 1 s, stop request -> covering cycle,
    //    then engine.stop() and prepare(). Times in ms.
    var rows: [String] = []
    for _ in 0..<10 {
        sinkEngine.prepare()
        do { try sinkEngine.start() } catch { log("restart failed: \(error)"); exit(1) }
        Thread.sleep(forTimeInterval: Double.random(in: 0.8...1.2))
        let stop = mach_absolute_time()
        while lastEnd.load(ordering: .acquiring) < stop { _ = signal.wait(timeout: .now() + 1) }
        let covered = mach_absolute_time()
        sinkEngine.stop()
        let stopped = mach_absolute_time()
        sinkEngine.prepare()
        let prepared = mach_absolute_time()
        rows.append(String(format: "wait %.1f + engine.stop %.1f (+ prepare %.1f, after return)",
                           ms(covered - stop), ms(stopped - covered), ms(prepared - stopped)))
    }
    log("full stop path: " + rows.joined(separator: "; "))
    log("DONE")
    exit(0)
}
NSApplication.shared.run()
