import AppKit
import KotobaCore
import SwiftUI

/// The pill's clips (`make pill-clip`, `--pill-clip <folder>`): the shipping pill with its glass plays a dictation's
/// looks as the panel shows them (it appears, records, loads, pastes, goes; Esc and Undo; push to talk and an error),
/// frame by frame at 30 fps and 2x, from windows never ordered in (`SnapshotCapture`). The pill's layers run on the
/// clip's clock (speed 0, each frame sets their time) and so does its glass (`PillView.glassClock`), so a frame shows
/// what the screen shows at that time. Each frame stacks the pill at the bottom and at the right edge, light over dark;
/// `scripts/pill-clip.sh` encodes them. Clips: "While dictating", "Always" (the idle bar between) and Reduce Motion.
@MainActor
enum PillClips {
    static let fps = 30.0
    static let scale: CGFloat = 2

    private struct Clip {
        let name: String
        var showsIdleBar = false
        var reducesMotion = false
    }

    private static let clips = [
        Clip(name: "pill-while-dictating"), Clip(name: "pill-always", showsIdleBar: true),
        Clip(name: "pill-reduce-motion", reducesMotion: true),
    ]

    /// The screen the clips stand for, and the two parts a frame shows: the bottom pill's room, and the band across the
    /// right pill's room where it stands vertical or reaches inward with words.
    static let screen = NSRect(x: 0, y: 0, width: 720, height: 420)
    private static let bottom = NSRect(x: 150, y: 0, width: 420, height: 96)
    private static let side = NSRect(x: 300, y: screen.midY - 80, width: 420, height: 160)

    static func run(writingTo folder: URL) -> Never {
        if let problem = SnapshotCapture.problem() ?? SnapshotCapture.drawWindowsAsActive() {
            FileHandle.standardError.write(Data("Pill clips failed: \(problem)\n".utf8))
            exit(1)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for clip in clips {
                try autoreleasepool { try render(clip, to: folder) }
            }
        } catch {
            FileHandle.standardError.write(Data("Pill clips failed: \(error)\n".utf8))
            exit(1)
        }
        FileHandle.standardError.write(Data("Wrote the pill clips' frames to \(folder.path)\n".utf8))
        exit(0)
    }

    private static func render(_ clip: Clip, to folder: URL) throws {
        let frames = folder.appending(path: clip.name, directoryHint: .isDirectory)
        // Absent on a first run; a failed removal fails the creation below or the writes.
        try? FileManager.default.removeItem(at: frames)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        PillView.prefersStill = clip.reducesMotion
        defer { PillView.prefersStill = false }
        let appearances = [NSAppearance.Name.aqua, .darkAqua]
        let players = appearances.flatMap { name in
            [bottom, side].map { shown in
                ClipPlayer(
                    anchor: shown == bottom ? .bottomCenter : .right, showing: shown,
                    appearance: NSAppearance(named: name), showsIdleBar: clip.showsIdleBar)
            }
        }
        for index in 0..<Int((ClipScript.length * fps).rounded()) {
            try autoreleasepool {
                for player in players {
                    player.step(to: Double(index) / fps)
                }
                let images = try players.map { try SnapshotCapture.image(of: $0.window, scale: scale) }
                try write(stacked(images), to: frames.appending(path: String(format: "%04d.png", index)))
            }
        }
    }

    // MARK: Images

    /// The captures, one under the other, at their own size.
    private static func stacked(_ images: [CGImage]) throws -> CGImage {
        let width = images.map(\.width).max() ?? 0
        let height = images.map(\.height).reduce(0, +)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ClipError.noBitmap }
        var top = height
        for image in images {
            top -= image.height
            context.draw(image, in: CGRect(x: 0, y: top, width: image.width, height: image.height))
        }
        guard let stacked = context.makeImage() else { throw ClipError.noBitmap }
        return stacked
    }

    private static func write(_ image: CGImage, to file: URL) throws {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ClipError.noBitmap
        }
        try png.write(to: file)
    }

    enum ClipError: Error {
        case noBitmap
    }
}

/// What a clip plays: one look after another, in seconds, as the panel shows them.
@MainActor
private enum ClipScript {
    enum Beat {
        case look(PillLook)
        /// The pill goes: the idle bar with "Always", else nothing.
        case rest
    }

    struct Cue {
        let at: Double
        let beat: Beat
        /// The recording hears speech from this cue on.
        var speaks = false
    }

    static let cues: [Cue] = [
        Cue(at: 0.6, beat: .look(look(.init(.recording(isLong: false)))), speaks: true),
        Cue(at: 4.0, beat: .look(look(.init(.transcribing)))),
        Cue(at: 7.6, beat: .look(.done)),
        Cue(at: 8.8, beat: .rest),
        Cue(at: 10.0, beat: .look(look(.init(.recording(isLong: false)))), speaks: true),
        Cue(at: 12.2, beat: .look(look(.init(.undoable)))),
        Cue(at: 14.6, beat: .look(look(.init(.recording(isLong: false)))), speaks: true),
        Cue(at: 16.2, beat: .look(look(.init(.undoable)))),
        Cue(at: 18.0, beat: .rest),
        Cue(at: 19.2, beat: .look(look(.init(.recording(isLong: false, isPushToTalk: true)))), speaks: true),
        Cue(at: 21.2, beat: .look(look(.init(.transcribing)))),
        Cue(at: 22.8, beat: .look(look(.init(.idle, notice: .failed(DictationID()))))),
        Cue(at: 26.0, beat: .rest),
    ]
    static let length = 27.0

    /// The pill's look for `state`, as the panel maps it.
    private static func look(_ state: DictationState) -> PillLook {
        IndicatorPanel.content(
            for: state, context: StatusContext(provider: .openRouter), visibility: .whileDictating)?.look ?? .idle
    }

    /// The speaker's level `time` after the recording began: short phrases of syllables with pauses.
    static func level(at time: Double) -> CGFloat {
        let phrases = [(0.15, 1.2), (1.6, 3.0)]
        guard let phrase = phrases.first(where: { time >= $0.0 && time < $0.1 }) else { return 0 }
        let syllable = (time - phrase.0) * 5
        let loudness = [0.62, 0.8, 0.5, 0.74, 0.46, 0.68, 0.84, 0.55][Int(syllable) % 8]
        return CGFloat(loudness * (0.55 + 0.45 * sin(.pi * syllable.truncatingRemainder(dividingBy: 1))))
    }
}

/// One pill in its own window over the backdrop, on the clip's clock: it shows and hides as the panel does
/// (`IndicatorPanel.present`, `orderOut`).
@MainActor
private final class ClipPlayer {
    let window: NSWindow
    private let pill: PillView
    private let showsIdleBar: Bool
    private let origin = CACurrentMediaTime()
    private var time = 0.0
    private var next = 0
    private var isShown = false
    /// Since when the recording hears speech, and how many levels it has sent.
    private var speech: (since: Double, sent: Int)?
    /// The glass's move under way and when it began.
    private var move: (at: Double, move: PillView.GlassMove)?
    private static let levelsPerSecond = 30.0

    init(anchor: IndicatorAnchor, showing shown: NSRect, appearance: NSAppearance?, showsIdleBar: Bool) {
        self.showsIdleBar = showsIdleBar
        let room = NSRect(
            IndicatorPlacement.room(at: anchor, thickness: PillGeometry.height, in: ScreenRect(PillClips.screen)))
        pill = PillView(frame: room.offsetBy(dx: -shown.minX, dy: -shown.minY))
        pill.anchor = anchor
        pill.levelsPerSecond = Self.levelsPerSecond
        let backdrop = ClipBackdrop(showing: shown)
        backdrop.addSubview(pill)
        window = ClipWindow(contentRect: backdrop.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = backdrop
        pill.wantsLayer = true
        pill.layer?.speed = 0
        pill.glassClock = { [weak self] move in
            guard let self else { return }
            self.move = (self.time, move)
        }
        setLayerTime()
        if showsIdleBar {
            pill.prepareToAppear()
            pill.appear(.idle)
            isShown = true
        }
    }

    /// Plays the script up to `target` seconds: each cue at its time, the speech's levels as they come, then the glass.
    func step(to target: Double) {
        while next < ClipScript.cues.count, ClipScript.cues[next].at <= target {
            advance(to: ClipScript.cues[next].at)
            fire(ClipScript.cues[next])
            next += 1
        }
        advance(to: target)
        guard let move else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.glass.frame = move.move.frame(at: time - move.at)
        CATransaction.commit()
        if time - move.at > move.move.spring.swiftUI.settlingDuration {
            self.move = nil
        }
    }

    /// The clock and the speech up to `target`.
    private func advance(to target: Double) {
        time = max(time, target)
        setLayerTime()
        guard let speech else { return }
        let due = Int(((time - speech.since) * Self.levelsPerSecond).rounded(.down)) + 1
        for index in speech.sent..<max(speech.sent, due) {
            pill.level = ClipScript.level(at: Double(index) / Self.levelsPerSecond)
        }
        self.speech?.sent = max(speech.sent, due)
    }

    private func setLayerTime() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.layer?.timeOffset = origin + time
        CATransaction.commit()
    }

    private func fire(_ cue: ClipScript.Cue) {
        speech = cue.speaks ? (time, 0) : nil
        if !cue.speaks {
            pill.level = 0
        }
        switch cue.beat {
        case .rest where showsIdleBar:
            pill.look = .idle
        case .rest:
            pill.vanish {}
            isShown = false
        case .look(let look):
            if !isShown {
                pill.prepareToAppear()
                isShown = true
                pill.appear(look)
            } else if pill.isVanishing {
                pill.appear(look)
            } else {
                pill.look = look
            }
        }
    }
}

/// The clips' window: never ordered in, yet its pill runs its on-screen changes.
private final class ClipWindow: NSWindow {
    override var isVisible: Bool { true }
}

/// The showcase's colour fields with lines of text, so the glass bends something.
private final class ClipBackdrop: NSView {
    private let shown: NSRect

    /// Lines of text under each pill, as a chat or a terminal would have there.
    private static let lines: [(String, NSPoint)] = [
        ("Almost. I fixed the copy on step two. Give me ten minutes.", NSPoint(x: 150, y: 70)),
        ("Sounds good. Let’s move the review to Friday at three.", NSPoint(x: 168, y: 36)),
        ("I’ll bring the slides and the numbers from last week.", NSPoint(x: 180, y: 12)),
        ("Rename useAuthStore to useSession in src/auth/store.ts,", NSPoint(x: 330, y: 226)),
        ("then run the tests with --coverage and fix what fails.", NSPoint(x: 330, y: 202)),
        ("The build is green on main; ship it after lunch.", NSPoint(x: 330, y: 178)),
    ]

    init(showing shown: NSRect) {
        self.shown = shown
        super.init(frame: NSRect(origin: .zero, size: shown.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClipBackdrop is built in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        context.saveGState()
        context.translateBy(x: -shown.minX, y: -shown.minY)
        Stage.draw(in: context, size: PillClips.screen.size, isDark: isDark)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: isDark ? NSColor(white: 0.92, alpha: 0.9) : NSColor(white: 0.1, alpha: 0.85),
        ]
        for (text, point) in Self.lines {
            NSAttributedString(string: text, attributes: attributes).draw(at: point)
        }
        context.restoreGState()
    }
}
