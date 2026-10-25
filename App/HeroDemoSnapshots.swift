import AppKit
import KotobaCore
import SwiftUI

/// The site's hero demo (`make hero-demo`, `--hero-demo <folder>`): a dictation into a chat, into a coding agent in a
/// terminal and into a message, one after the other, frame by frame, light and dark, at 2x, as PNG frames that `make
/// hero-demo` encodes into a looping video. Everything in a frame is real AppKit as the window server draws it
/// (`SnapshotCapture`): each window's title bar, toolbar, text and caret (`DemoWindow`), and the pill's glass, which
/// refracts the frame under it. Offscreen the pill takes each look at once
/// (`PillView.morph`), so the demo moves the glass with the pill's own spring and fades its items with the pill's
/// timings, and steps the pill's Core Animation clock (the bars settling, the sweep, the check drawing on) with the
/// frames. Nothing shows on screen.
@MainActor
enum HeroDemo {
    static let fps = 30.0
    /// The stage is a small screen: the window in its upper part, the pill at the bottom centre, where the app puts it.
    static let stage = NSRect(x: 0, y: 0, width: 680, height: 480)
    static let scale: CGFloat = 2
    private static let windowFrame = NSRect(x: 90, y: 104, width: 500, height: 336)

    /// The scenes, in turn: a chat reply, a prompt for a coding agent, an email. Each records for a short beat, not as
    /// long as its words take to say: the demo shows what kotoba does, not how long the owner speaks.
    private static let scenes = [
        Scene(
            kind: .chat, dictation: "Almost. I fixed the copy on step two. Give me ten minutes.",
            speech: Speech([Speech.Phrase(0.25, 0.65, 2), Speech.Phrase(0.75, 1.2, 3)])),
        Scene(
            kind: .terminal,
            dictation: "Rename useAuthStore to useSession in src/auth/store.ts, then run the tests with --coverage.",
            speech: Speech([Speech.Phrase(0.25, 1.2, 5)])),
        Scene(
            kind: .message, dictation: "Sounds good. Let’s move the review to Friday at three. I’ll bring the slides.",
            speech: Speech([Speech.Phrase(0.25, 0.55, 2), Speech.Phrase(0.65, 1.2, 3)])),
    ]

    private struct Scene {
        let kind: DemoWindow.Kind
        let dictation: String
        let speech: Speech
    }

    private struct LookChange {
        let at: Double
        let look: PillLook
        let isAnimated: Bool
    }

    /// A scene's times, in seconds from the timeline's start. The pill shows from the first frame of a scene to its
    /// last: the window and the pill fade in together, recording, and fade out together on the check.
    private struct Beat {
        /// The shortcut: the window fades in from the bare stage with the pill recording on it.
        let press: Double
        /// The stop tap: the bars sweep while the text is on its way.
        let stop: Double
        /// The text lands and the check shows.
        let paste: Double
        /// The window and the check fade out to the bare stage.
        let fadeOut: Double
        /// The check's time is up (`PillTimer.done`), the pill is gone, and the next scene starts.
        let end: Double

        static let fadeLength = 0.25

        init(at start: Double, speech: Speech) {
            press = start
            stop = press + speech.length
            // From the stop tap to the paste: 0.4.6's measured median (README, "Benchmarks"), as the site claims it.
            paste = stop + 0.987
            end = paste + PillTimer.done.duration / .seconds(1)
            fadeOut = end - Self.fadeLength
        }
    }

    /// The three scenes and the first again: the video starts in the first scene's recording (`poster`), so its first
    /// frame, the poster, shows kotoba at work, and it ends at the same moment of the first scene's repeat, so the loop
    /// has no jump. Each scene starts on a frame, so the repeat's frames are the first scene's.
    private static let beats = (scenes + scenes.prefix(1)).reduce(into: [Beat]()) { beats, scene in
        let start = ((beats.last?.end ?? 0) * fps).rounded(.up) / fps
        beats.append(Beat(at: start, speech: scene.speech))
    }
    /// The loop's length: from the first scene's start to its repeat's.
    private static let length = beats.last?.press ?? 0
    /// The video's first frame on the timeline: the first scene's bars up on a stressed syllable, the caret on.
    private static let poster = Int((0.6 * fps).rounded())

    /// Renders every frame to `<folder>/light/0000.png` and `<folder>/dark/0000.png` on, and exits.
    static func run(writingTo folder: URL) -> Never {
        if let problem = SnapshotCapture.problem() ?? SnapshotCapture.drawWindowsAsActive() {
            FileHandle.standardError.write(Data("Hero demo failed: \(problem)\n".utf8))
            exit(1)
        }
        do {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                guard let appearance = NSAppearance(named: appearance) else { continue }
                NSApp.appearance = appearance
                let frames = folder.appending(path: name, directoryHint: .isDirectory)
                // Absent on a first run; a failed removal fails the creation below or the writes.
                try? FileManager.default.removeItem(at: frames)
                try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
                try autoreleasepool { try render(in: appearance, to: frames) }
            }
        } catch {
            FileHandle.standardError.write(Data("Hero demo failed: \(error)\n".utf8))
            exit(1)
        }
        FileHandle.standardError.write(Data("Wrote the hero demo's frames to \(folder.path)\n".utf8))
        exit(0)
    }

    private static func render(in appearance: NSAppearance, to folder: URL) throws {
        let windows = scenes.map {
            DemoWindow($0.kind, dictation: $0.dictation, frame: windowFrame, appearance: appearance)
        }
        // A pill of its own for each scene, as each dictation shows the pill anew: the bars' drift starts over, so the
        // first scene's repeat draws as the first scene did.
        let pills = beats.map { _ in DemoPill(on: stage, appearance: appearance) }
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let bareStage = try stageImage(isDark: isDark)
        // The pill appears recording; from there its glass flows to each next look.
        var looks = beats.map { beat in
            [
                LookChange(at: beat.press, look: look(.init(.recording(isLong: false))), isAnimated: false),
                LookChange(at: beat.stop, look: look(.init(.transcribing)), isAnimated: true),
                LookChange(at: beat.paste, look: look(.init(.idle, isPasted: true)), isAnimated: true),
            ]
        }
        func renderFrame(_ index: Int) throws {
            let time = Double(index) / fps
            let scene = beats.lastIndex { $0.press <= time } ?? 0
            let beat = beats[scene]
            let pill = pills[scene]
            while let next = looks[scene].first, next.at <= time {
                pill.show(next.look, at: next.at, isAnimated: next.isAnimated)
                looks[scene].removeFirst()
            }
            if time < beat.stop {
                pill.view.level = scenes[scene % scenes.count].speech.level(at: time - beat.press)
            }
            pill.step(to: time)
            // The caret blinks from the window's fade-in end, and again from the paste.
            let isPasted = time >= beat.paste
            let window = try windows[scene % scenes.count].onStage(
                isPasted: isPasted,
                showsCaret: Caret.isShown(at: time - (isPasted ? beat.paste : beat.press + Beat.fadeLength)),
                isDark: isDark)
            var image = try pill.drawn(over: window)
            if time < beat.press + Beat.fadeLength {
                let progress = (time - beat.press) / Beat.fadeLength
                image = try blend(image, into: bareStage, opacity: UnitCurve.easeOut.value(at: progress))
            } else if time >= beat.fadeOut {
                let progress = min(1, (time - beat.fadeOut) / Beat.fadeLength)
                image = try blend(image, into: bareStage, opacity: 1 - UnitCurve.easeIn.value(at: progress))
            }
            // The frames before the poster only bring the first pill to its state there.
            guard index >= poster else { return }
            let file = folder.appending(path: String(format: "%04d.png", index - poster))
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw DemoError.noBitmap
            }
            try png.write(to: file)
        }
        for index in 0..<(poster + Int((length * fps).rounded())) {
            // Each frame's images and bitmap data go at its end, not at the end of the pass.
            try autoreleasepool { try renderFrame(index) }
        }
    }

    /// The pill's look for `state`, as the panel maps it.
    private static func look(_ state: DictationState) -> PillLook {
        IndicatorPanel.content(
            for: state, context: StatusContext(provider: .openRouter), visibility: .whileDictating)?.look ?? .idle
    }

    /// The window with a shadow at its place on the stage, as a bitmap of the whole stage.
    static func onStage(_ window: NSWindow, isDark: Bool) throws -> CGImage {
        let capture = try SnapshotCapture.image(of: window, scale: scale)
        let context = try bitmap()
        Stage.draw(in: context, size: CGSize(width: context.width, height: context.height), isDark: isDark)
        let place = CGRect(
            x: windowFrame.minX * scale, y: windowFrame.minY * scale, width: windowFrame.width * scale,
            height: windowFrame.height * scale)
        Showcase.drawWindow(capture, in: place, of: context, scale: scale, isDark: isDark)
        guard let image = context.makeImage() else { throw DemoError.noBitmap }
        return image
    }

    /// The stage with no window on it.
    private static func stageImage(isDark: Bool) throws -> CGImage {
        let context = try bitmap()
        Stage.draw(in: context, size: CGSize(width: context.width, height: context.height), isDark: isDark)
        guard let image = context.makeImage() else { throw DemoError.noBitmap }
        return image
    }

    private static func blend(_ top: CGImage, into bottom: CGImage, opacity: CGFloat) throws -> CGImage {
        guard opacity < 1 else { return top }
        let context = try bitmap()
        let rect = CGRect(x: 0, y: 0, width: context.width, height: context.height)
        context.draw(bottom, in: rect)
        context.setAlpha(opacity)
        context.draw(top, in: rect)
        guard let image = context.makeImage() else { throw DemoError.noBitmap }
        return image
    }

    /// A bitmap the size of the stage at `scale`.
    static func bitmap() throws -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(stage.width * scale), height: Int(stage.height * scale), bitsPerComponent: 8,
                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw DemoError.noBitmap }
        return context
    }

    enum DemoError: Error {
        case noBitmap
    }
}

/// The caret blinks: on for half a second after the text changes, then off and on every half second.
private enum Caret {
    static func isShown(at time: Double) -> Bool {
        time < 0.5 || !Int((time - 0.5) / 0.5).isMultiple(of: 2)
    }
}

/// What the microphone hears: one bump of loudness per syllable, phrases apart by short pauses. The capture measures
/// a level every 100 ms (`CaptureWriter.measureLevel`) and the bars glide to each one in 0.2 s (`PillBars`), so the bars
/// show these levels eased, as on screen.
private struct Speech {
    /// A phrase: its start and end after the press, and its syllables.
    struct Phrase {
        let start: Double
        let end: Double
        let syllables: Int

        init(_ start: Double, _ end: Double, _ syllables: Int) {
            self.start = start
            self.end = end
            self.syllables = syllables
        }
    }

    private let phrases: [Phrase]
    /// From the press to the stop tap: a short silence after the last phrase.
    let length: Double

    init(_ phrases: [Phrase]) {
        self.phrases = phrases
        length = (phrases.last?.end ?? 0) + 0.15
    }

    /// The syllables' loudness, in turn: stressed ones louder.
    private static let loudness: [Double] = [0.62, 0.78, 0.5, 0.72, 0.45, 0.66, 0.8, 0.55, 0.7, 0.48, 0.75, 0.6]
    private static let interval = 0.1

    /// The level the bars show `time` after the press.
    func level(at time: Double) -> CGFloat {
        let last = Int((time / Self.interval).rounded(.down))
        // The level measured over the 100 ms that ended at each event, and the tween each one still runs.
        var shown = measured(last)
        for event in max(0, last - 2)...max(0, last) {
            let progress = (time - Double(event) * Self.interval) / PillBars.tween
            guard progress < 1 else { continue }
            shown += (measured(event - 1) - measured(event)) * (1 - UnitCurve.easeInOut.value(at: progress))
        }
        return CGFloat(max(0, shown))
    }

    /// The level measured over the window that ends at event `index` (the first ends 100 ms after the press).
    private func measured(_ index: Int) -> Double {
        guard index > 0 else { return 0 }
        let start = Double(index - 1) * Self.interval
        let samples = 10
        return (0..<samples).map { loudness(at: start + Self.interval * Double($0) / Double(samples)) }.reduce(0, +)
            / Double(samples)
    }

    /// The voice's loudness at `time`: a raised cosine per syllable.
    private func loudness(at time: Double) -> Double {
        var syllable = 0
        for phrase in phrases {
            defer { syllable += phrase.syllables }
            guard time >= phrase.start, time < phrase.end else { continue }
            let slot = (phrase.end - phrase.start) / Double(phrase.syllables)
            let index = Int((time - phrase.start) / slot)
            let within = (time - phrase.start) / slot - Double(index)
            let peak = Self.loudness[(syllable + index) % Self.loudness.count]
            return peak * (0.55 + 0.45 * sin(.pi * within))
        }
        return 0
    }
}
