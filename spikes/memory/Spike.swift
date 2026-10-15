// Throwaway idle-memory spike (docs/research/memory-spike.md). Not part of the app or `make check`.
// One source, one variant per compile flag:
//   A: NSStatusItem only
//   B: A + floating NSPanel with NSGlassEffectView, shown once then hidden
//   C: B + AVAudioEngine prepared, not started. With `--time-start <file>`: 10 runs of
//      engine.start() -> first input buffer, written to <file>, then exit.
//   E: A + SwiftUI Settings window (NSHostingController), opened once then closed
import AppKit

#if VARIANT_C
    import AVFoundation
#endif
#if VARIANT_E
    import SwiftUI
#endif

@MainActor
final class SpikeDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    #if VARIANT_C
        private let engine = AVAudioEngine()
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "spike")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        #if VARIANT_B || VARIANT_C
            showGlassPanelOnce()
        #endif
        #if VARIANT_C
            prepareEngine()
        #endif
        #if VARIANT_E
            showSettingsOnce()
        #endif
    }

    #if VARIANT_B || VARIANT_C
        private func showGlassPanelOnce() {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 180, height: 44),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false

            let glass = NSGlassEffectView(frame: panel.contentLayoutRect)
            glass.cornerRadius = 22
            let label = NSTextField(labelWithString: "Recording")
            label.alignment = .center
            glass.contentView = label
            panel.contentView = glass

            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: frame.midX - 90, y: frame.minY + 80))
            }
            panel.orderFrontRegardless()
            self.panel = panel
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { panel.orderOut(nil) }
        }
    #endif

    #if VARIANT_C
        private func prepareEngine() {
            let args = CommandLine.arguments
            let timingFile = args.firstIndex(of: "--time-start").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            Self.append("mic authorization status (0 notDetermined, 1 restricted, 2 denied, 3 authorized): \(status.rawValue)\n", to: timingFile)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    Self.append("mic granted: \(granted)\n", to: timingFile)
                    _ = self.engine.inputNode.outputFormat(forBus: 0)
                    self.engine.prepare()
                    if granted, let timingFile {
                        self.runStartTimings(to: timingFile)
                    }
                }
            }
        }

        private nonisolated static func append(_ line: String, to path: String?) {
            guard let path else { return }
            let url = URL(filePath: path)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }

        /// Measures engine.start() -> first input buffer, 10 runs, the same way the app will start at key-down.
        private func runStartTimings(to path: String) {
            let engine = self.engine
            Thread.detachNewThread {
                var results: [(start: Double, firstBuffer: Double, firstSample: Double)] = []
                for run in 1...10 {
                    let clock = ContinuousClock()
                    let gotBuffer = DispatchSemaphore(value: 0)
                    let firstBufferAt = FirstBuffer()
                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    input.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, when in
                        if firstBufferAt.set(clock.now, frames: buffer.frameLength, hostTime: when.hostTime) {
                            gotBuffer.signal()
                        }
                    }
                    engine.prepare()
                    let t0Host = mach_absolute_time()
                    let t0 = clock.now
                    do { try engine.start() } catch {
                        Self.append("run \(run): start failed: \(error)\n", to: path)
                        continue
                    }
                    let tStarted = clock.now
                    _ = gotBuffer.wait(timeout: .now() + 3)
                    let tFirst = firstBufferAt.value
                    engine.stop()
                    input.removeTap(onBus: 0)
                    let startMs = Self.ms(tStarted - t0)
                    let firstMs = tFirst.map { Self.ms($0 - t0) } ?? -1
                    let frames = firstBufferAt.frames
                    let sampleHost = firstBufferAt.hostTime
                    let firstSampleMs = sampleHost >= t0Host
                        ? AVAudioTime.seconds(forHostTime: sampleHost - t0Host) * 1000
                        : -AVAudioTime.seconds(forHostTime: t0Host - sampleHost) * 1000
                    results.append((startMs, firstMs, firstSampleMs))
                    Self.append(
                        String(format: "run %d: start() returned %.1f ms, first buffer delivered %.1f ms (%d frames = %.1f ms), its first sample at %.1f ms (%.0f Hz, %d ch)\n",
                               run, startMs, firstMs, frames, Double(frames) / format.sampleRate * 1000, firstSampleMs, format.sampleRate, format.channelCount),
                        to: path
                    )
                    Thread.sleep(forTimeInterval: 1.5)
                }
                func pct(_ values: [Double], _ p: Double) -> Double {
                    let v = values.sorted()
                    return v.isEmpty ? -1 : v[min(v.count - 1, Int((p * Double(v.count)).rounded(.up)) - 1)]
                }
                let delivered = results.map(\.firstBuffer).filter { $0 >= 0 }
                let sample = results.map(\.firstSample)
                let starts = results.map(\.start)
                Self.append(String(format: "start() returned p50 %.1f / p90 %.1f ms; first buffer delivered p50 %.1f / p90 %.1f ms; first sample p50 %.1f / p90 %.1f ms; n=%d\nDONE\n",
                                   pct(starts, 0.5), pct(starts, 0.9), pct(delivered, 0.5), pct(delivered, 0.9), pct(sample, 0.5), pct(sample, 0.9), delivered.count), to: path)
                DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            }
        }

        private nonisolated static func ms(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
    #endif

    #if VARIANT_E
        private func showSettingsOnce() {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Settings"
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            settingsWindow = window
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.settingsWindow?.close()
                self.settingsWindow = nil
            }
        }
    #endif
}

#if VARIANT_C
    /// First-buffer timestamp, written once from the audio thread.
    final class FirstBuffer: @unchecked Sendable {  // guarded by `lock`
        private let lock = NSLock()
        private var instant: ContinuousClock.Instant?
        private(set) var frames: AVAudioFrameCount = 0
        private(set) var hostTime: UInt64 = 0

        func set(_ now: ContinuousClock.Instant, frames: AVAudioFrameCount, hostTime: UInt64) -> Bool {
            lock.withLock {
                guard instant == nil else { return false }
                instant = now
                self.frames = frames
                self.hostTime = hostTime
                return true
            }
        }

        var value: ContinuousClock.Instant? { lock.withLock { instant } }
    }
#endif

#if VARIANT_E
    struct SettingsView: View {
        @State private var provider = "OpenRouter"
        @State private var sounds = true
        @State private var language = "en"

        var body: some View {
            Form {
                Picker("Provider", selection: $provider) {
                    Text("OpenRouter").tag("OpenRouter")
                    Text("xAI").tag("xAI")
                    Text("Azure MAI").tag("Azure MAI")
                }
                Toggle("Sound cues", isOn: $sounds)
                TextField("Language", text: $language)
            }
            .formStyle(.grouped)
            .frame(width: 420, height: 240)
        }
    }
#endif

MainActor.assumeIsolated {
    let delegate = SpikeDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
