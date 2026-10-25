import AppKit
import KotobaCore
import SwiftUI

/// The site's hero demo (`make hero-demo`, `--hero-demo <folder>`): one dictation into a message window, frame by
/// frame, light and dark, at 2x, as PNG frames that `make hero-demo` encodes into a short looping video. Everything in a
/// frame is real AppKit as the window server draws it (`SnapshotCapture`): the window's title bar, toolbar, text and
/// caret, and the pill's glass, which refracts the frame under it. Offscreen the pill takes each look at once
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

    /// The scene, in seconds. The video loops, and its first frame is the finished message, so the poster (that frame)
    /// leads into the playback with no jump.
    private static let clearAt = 1.2
    private static let clearLength = 0.5
    /// The shortcut: the pill shows, recording.
    private static let pressAt = 2.6
    /// The stop tap: the bars sweep while the text is on its way.
    private static let stopAt = pressAt + Speech.length
    /// The stop tap to the paste: 0.4.6's measured median (README, "Benchmarks"), as the site claims it.
    private static let pasteAt = stopAt + 0.987
    /// The check shows for its time, then the pill hides.
    private static let hideAt = pasteAt + PillTimer.done.duration / .seconds(1)
    private static let length = 11.0

    static let greeting = "Hi Maya,\n\n"
    static let dictation = "Sounds good. Let’s move the review to Friday at three. I’ll bring the slides."

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
        let message = MessageWindow(frame: windowFrame, appearance: appearance)
        let pill = DemoPill(on: stage, appearance: appearance)
        var looks: [(at: Double, look: PillLook)] = [
            (pressAt, look(.init(.recording(isLong: false)))), (stopAt, look(.init(.transcribing))),
            (pasteAt, look(.init(.idle, isPasted: true))),
        ]
        func renderFrame(_ index: Int) throws {
            let time = Double(index) / fps
            var image: CGImage
            if time < clearAt + clearLength {
                // The last frame's message, then the empty one fading in over it.
                let done = try message.onStage(isPasted: true, showsCaret: Caret.isShown(at: time + length - pasteAt))
                let empty = try message.onStage(isPasted: false, showsCaret: true)
                let fade = UnitCurve.easeInOut.value(at: min(1, max(0, (time - clearAt) / clearLength)))
                image = try blend(done, into: empty, opacity: 1 - fade)
            } else {
                let isPasted = time >= pasteAt
                let since = isPasted ? time - pasteAt : time - clearAt - clearLength
                image = try message.onStage(isPasted: isPasted, showsCaret: Caret.isShown(at: since))
            }
            if time >= pressAt, time < hideAt {
                while let next = looks.first, next.at <= time {
                    pill.show(next.look, at: next.at, isAnimated: next.at > pressAt)
                    looks.removeFirst()
                }
                if time < stopAt {
                    pill.view.level = Speech.level(at: time - pressAt)
                }
                pill.step(to: time)
                image = try pill.drawn(over: image)
            }
            let file = folder.appending(path: String(format: "%04d.png", index))
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw DemoError.noBitmap
            }
            try png.write(to: file)
        }
        for index in 0..<Int((length * fps).rounded()) {
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
        // The capture of a window that was never on screen has no shadow, also with a shadow margin (measured
        // 2026-10-25: the margin came back clear): the demo draws an active window's, wide and soft under it and close
        // at its edge, from the window's own shape.
        for (drop, blur, alpha) in [(18.0, 50.0, isDark ? 0.55 : 0.24), (0.0, 2.0, isDark ? 0.7 : 0.2)] {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -drop * scale), blur: blur * scale,
                color: CGColor(gray: 0, alpha: alpha))
            context.draw(capture, in: place)
            context.restoreGState()
        }
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

/// What the microphone hears: "Sounds good. Let’s move the review to Friday at three. I’ll bring the slides.", one
/// bump of loudness per syllable, phrases apart by short pauses. The capture measures a level every 100 ms
/// (`CaptureWriter.measureLevel`) and the bars glide to each one in 0.2 s (`PillBars`), so the bars show these levels
/// eased, as on screen.
private enum Speech {
    /// A phrase: its start and end after the press, and its syllables.
    private struct Phrase {
        let start: Double
        let end: Double
        let syllables: Int
    }

    private static let phrases = [
        Phrase(start: 0.3, end: 0.9, syllables: 2), Phrase(start: 1.2, end: 3.1, syllables: 10),
        Phrase(start: 3.4, end: 4.3, syllables: 5),
    ]
    static let length = 4.6
    /// The syllables' loudness, in turn: stressed ones louder.
    private static let loudness: [Double] = [0.62, 0.78, 0.5, 0.72, 0.45, 0.66, 0.8, 0.55, 0.7, 0.48, 0.75, 0.6]
    private static let interval = 0.1

    /// The level the bars show `time` after the press.
    static func level(at time: Double) -> CGFloat {
        let last = Int((time / interval).rounded(.down))
        // The level measured over the 100 ms that ended at each event, and the tween each one still runs.
        var shown = measured(last)
        for event in max(0, last - 2)...max(0, last) {
            let progress = (time - Double(event) * interval) / PillBars.tween
            guard progress < 1 else { continue }
            shown += (measured(event - 1) - measured(event)) * (1 - UnitCurve.easeInOut.value(at: progress))
        }
        return CGFloat(max(0, shown))
    }

    /// The level measured over the window that ends at event `index` (the first ends 100 ms after the press).
    private static func measured(_ index: Int) -> Double {
        guard index > 0 else { return 0 }
        let start = Double(index - 1) * interval
        let samples = 10
        return (0..<samples).map { loudness(at: start + interval * Double($0) / Double(samples)) }.reduce(0, +)
            / Double(samples)
    }

    /// The voice's loudness at `time`: a raised cosine per syllable.
    private static func loudness(at time: Double) -> Double {
        var syllable = 0
        for phrase in phrases {
            defer { syllable += phrase.syllables }
            guard time >= phrase.start, time < phrase.end else { continue }
            let slot = (phrase.end - phrase.start) / Double(phrase.syllables)
            let index = Int((time - phrase.start) / slot)
            let within = (time - phrase.start) / slot - Double(index)
            let peak = loudness[(syllable + index) % loudness.count]
            return peak * (0.55 + 0.45 * sin(.pi * within))
        }
        return 0
    }
}

/// A plain message window of the demo's own: a title, a glass toolbar with three tools, To and Subject, and the body
/// with its caret.
@MainActor
private final class MessageWindow {
    let window: NSWindow
    private let body = NSTextView()
    private let caret = NSTextInsertionIndicator()
    private let toolbarTools = MessageToolbar()
    /// The message on the stage, one capture for each text and caret.
    private var images: [State: CGImage] = [:]

    private struct State: Hashable {
        let isPasted: Bool
        let showsCaret: Bool
    }

    init(frame: NSRect, appearance: NSAppearance) {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: frame.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.title = "Re: Friday review"
        let toolbar = NSToolbar(identifier: "message")
        toolbar.delegate = toolbarTools
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.setFrame(NSRect(origin: .zero, size: frame.size), display: false)

        let paper = Paper(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = paper
        let top = paper.bounds.height - window.contentLayoutRect.maxY
        let width = paper.bounds.width
        var y = top
        for (name, value) in [("To:", "Maya Chen"), ("Subject:", "Re: Friday review")] {
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 14)
            label.textColor = .secondaryLabelColor
            let field = NSTextField(labelWithString: value)
            field.font = .systemFont(ofSize: 14)
            label.sizeToFit()
            field.sizeToFit()
            label.setFrameOrigin(NSPoint(x: 20, y: y + (36 - label.frame.height) / 2))
            field.setFrameOrigin(NSPoint(x: label.frame.maxX + 6, y: y + (36 - field.frame.height) / 2))
            let line = NSBox(frame: NSRect(x: 20, y: y + 36, width: width - 20, height: 1))
            line.boxType = .separator
            paper.addSubview(label)
            paper.addSubview(field)
            paper.addSubview(line)
            y += 37
        }
        body.frame = NSRect(x: 0, y: y + 6, width: width, height: paper.bounds.height - y - 6)
        body.textContainerInset = NSSize(width: 15, height: 8)
        body.font = .systemFont(ofSize: 16)
        body.textColor = .labelColor
        body.drawsBackground = false
        paper.addSubview(body)
        caret.displayMode = .hidden
        caret.color = .controlAccentColor
        body.addSubview(caret)
        window.makeFirstResponder(body)
    }

    /// The message before or after the paste on the stage, with the caret at its end, shown or not.
    func onStage(isPasted: Bool, showsCaret: Bool) throws -> CGImage {
        let state = State(isPasted: isPasted, showsCaret: showsCaret)
        if let image = images[state] { return image }
        show(isPasted: isPasted, showsCaret: showsCaret)
        let image = try HeroDemo.onStage(
            window, isDark: window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        images[state] = image
        return image
    }

    private func show(isPasted: Bool, showsCaret: Bool) {
        body.string = HeroDemo.greeting + (isPasted ? HeroDemo.dictation : "")
        let end = body.string.utf16.count
        body.setSelectedRange(NSRange(location: end, length: 0))
        body.layoutManager?.ensureLayout(for: body.textContainer ?? NSTextContainer())
        let screen = body.firstRect(forCharacterRange: NSRange(location: end, length: 0), actualRange: nil)
        let rect = body.convert(window.convertFromScreen(screen), from: nil)
        caret.frame = NSRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
        caret.displayMode = showsCaret ? .visible : .hidden
        window.layoutIfNeeded()
        // The caret fades in and out on screen; a frame shows it on or off.
        SnapshotCapture.endAnimations(in: window)
    }
}

/// The message's background: the text background, edge to edge under the glass toolbar.
private final class Paper: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

/// Send at the leading end, Attach and Format at the trailing end.
private final class MessageToolbar: NSObject, NSToolbarDelegate {
    private static let tools = [
        "send": ("paperplane", "Send"), "attach": ("paperclip", "Attach"), "format": ("textformat", "Format"),
    ]

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("send"), .flexibleSpace, .init("attach"), .init("format")]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let (symbol, label) = Self.tools[identifier.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.isBordered = true
        // A tool with an action draws enabled.
        item.target = self
        item.action = #selector(use)
        return item
    }

    @objc private func use(_ sender: Any?) {}
}
