import AppKit

/// Every look of the 0.5.0 pill prototype on real glass, for the owner's review (the `--prototype` launch mode opens
/// it). Glass samples what is behind it in the window, so each pill sits on a backdrop the owner picks: white, a
/// colour band, or black. While the window is open, made-up speech levels drive the recording pills, the processing
/// pills sweep, and the live pill at the top plays a whole dictation. All of it stops when the window closes.
final class PillPrototypeGallery: NSView {
    enum Backdrop: Int, CaseIterable {
        case light, colour, dark

        var title: String {
            switch self {
            case .light: "White"
            case .colour: "Colour"
            case .dark: "Black"
            }
        }
    }

    /// A titled window that holds the gallery in a scroll view.
    static func makeWindow() -> NSWindow {
        let gallery = PillPrototypeGallery()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = gallery
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: gallery.frame.width, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Pill Prototype"
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.center()
        return window
    }

    private var backdrop = Backdrop.colour {
        didSet {
            for cell in cells {
                cell.needsDisplay = true
            }
        }
    }
    private var cells: [BackdropCell] = []
    private var levelPills: [PillPrototypeView] = []
    private let live = PillPrototypeView()
    private let liveSide = PillPrototypeView()
    private var levels: Task<Void, Never>?
    private var demo: Task<Void, Never>?
    private var closeObserver: (any NSObjectProtocol)?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = PillGeometry.gap
        rows.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.setViews(
            [controls(), heading("A dictation, live"), liveRow(), heading("At the bottom")] + bottomRows()
                + [heading("At a side edge"), sideRow()], in: .top)
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
        ])
        setFrameSize(rows.fittingSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PillPrototypeGallery is built in code")
    }

    // MARK: Layout

    private func controls() -> NSView {
        let appearance = NSSegmentedControl(
            labels: ["System", "Light", "Dark"], trackingMode: .selectOne, target: self,
            action: #selector(appearanceChanged(_:)))
        appearance.selectedSegment = 0
        let backdrops = NSSegmentedControl(
            labels: Backdrop.allCases.map(\.title), trackingMode: .selectOne, target: self,
            action: #selector(backdropChanged(_:)))
        backdrops.selectedSegment = backdrop.rawValue
        let row = NSStackView(views: [
            NSTextField(labelWithString: "Appearance"), appearance, NSTextField(labelWithString: "Backdrop"), backdrops,
        ])
        row.spacing = PillGeometry.gap
        return row
    }

    private func heading(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    /// The live pills, bottom and side, and the dictations they play.
    private func liveRow() -> NSView {
        live.hoverKeys = PillPrototypeView.sampleKeys
        liveSide.hoverKeys = PillPrototypeView.sampleKeys
        liveSide.isAtSideEdge = true
        for pill in [live, liveSide] {
            pill.onAction = { [weak self] action in self?.liveAction(action) }
        }
        levelPills += [live, liveSide]
        let plays = NSStackView(views: [
            NSButton(title: "Push to Talk", target: self, action: #selector(playPushToTalk)),
            NSButton(title: "Hands-free", target: self, action: #selector(playHandsFree)),
            NSButton(title: "Silent Mic", target: self, action: #selector(playSilent)),
            NSButton(title: "Error", target: self, action: #selector(playError)),
        ])
        plays.orientation = .vertical
        plays.alignment = .leading
        let hint = NSTextField(
            wrappingLabelWithString:
                "Point at the idle bar to see the keys; click it to start. At a side edge, words show as at the bottom."
        )
        hint.preferredMaxLayoutWidth = 220
        hint.textColor = .secondaryLabelColor
        let column = NSStackView(views: [plays, hint])
        column.orientation = .vertical
        column.alignment = .leading
        let row = NSStackView(views: [
            cell(holding: live, size: NSSize(width: PillGeometry.maxLength + 40, height: 160)),
            // Wide enough for the hover's words, which stay horizontal at a side edge.
            cell(holding: liveSide, size: NSSize(width: 200, height: 160)), column,
        ])
        row.alignment = .top
        row.spacing = PillGeometry.gap
        return row
    }

    /// One row per look at the bottom: its name and the pill.
    private func bottomRows() -> [NSView] {
        PillPrototypeView.samples.map { sample in
            let pill = PillPrototypeView()
            // Only the idle bar answers the pointer; the hover row stays as it is.
            pill.hoverKeys = sample.look == .idle ? PillPrototypeView.sampleKeys : []
            pill.look = sample.look
            if case .recording = sample.look { levelPills.append(pill) }
            let name = NSTextField(labelWithString: sample.name)
            name.textColor = .secondaryLabelColor
            name.widthAnchor.constraint(equalToConstant: 160).isActive = true
            let row = NSStackView(views: [
                name, cell(holding: pill, size: NSSize(width: PillGeometry.maxLength + 40, height: 52)),
            ])
            row.spacing = PillGeometry.gap
            return row
        }
    }

    /// Every look that stands vertical at a side edge, side by side.
    private func sideRow() -> NSView {
        let pills = PillPrototypeView.samples.filter { $0.look.canStandVertical }.map { sample in
            let pill = PillPrototypeView()
            pill.isAtSideEdge = true
            pill.look = sample.look
            if case .recording = sample.look { levelPills.append(pill) }
            return cell(holding: pill, size: NSSize(width: 64, height: 160))
        }
        let row = NSStackView(views: pills)
        row.spacing = PillGeometry.gap
        return row
    }

    private func cell(holding pill: PillPrototypeView, size: NSSize) -> NSView {
        let cell = BackdropCell { [weak self] in self?.backdrop ?? .colour }
        cell.translatesAutoresizingMaskIntoConstraints = false
        pill.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(pill)
        NSLayoutConstraint.activate([
            cell.widthAnchor.constraint(equalToConstant: size.width),
            cell.heightAnchor.constraint(equalToConstant: size.height),
            pill.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            pill.topAnchor.constraint(equalTo: cell.topAnchor),
            pill.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
        ])
        cells.append(cell)
        return cell
    }

    // MARK: Controls

    @objc private func appearanceChanged(_ control: NSSegmentedControl) {
        window?.appearance = [nil, NSAppearance(named: .aqua), NSAppearance(named: .darkAqua)][control.selectedSegment]
    }

    @objc private func backdropChanged(_ control: NSSegmentedControl) {
        backdrop = Backdrop(rawValue: control.selectedSegment) ?? .colour
    }

    @objc private func playPushToTalk() { play(.init()) }
    @objc private func playHandsFree() { play(.init(isHandsFree: true, isCleaned: true)) }
    @objc private func playSilent() { play(.init(isHandsFree: true, isSilent: true)) }

    @objc private func playError() {
        play(
            .init(),
            then: .message(.init(text: "Couldn’t reach OpenRouter. Will retry.", isProblem: true, button: "Retry")))
    }

    /// Clicks on the live pill: the idle bar starts a hands-free dictation, Stop ends it, Cancel shows Undo.
    private func liveAction(_ action: PillPrototypeView.Action) {
        switch (action, live.look) {
        case (.click, .idle), (.click, .hover): play(.init(isHandsFree: true))
        case (.stop, _): finish(then: nil)
        case (.cancel, _):
            showLive(.message(.init(text: "Canceled", button: "Undo")), for: .seconds(3))
        default: showLive(.idle)
        }
    }

    // MARK: Live dictation

    /// Records for a few seconds (hands-free waits for Stop), then the sweep, then the check or `outcome`.
    private func play(_ recording: PillRecording, then outcome: PillLook? = nil) {
        demo?.cancel()
        showLive(.recording(recording))
        guard !recording.isHandsFree else { return }
        demo = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(3))) != nil else { return }
            self?.finish(then: outcome)
        }
    }

    private func finish(then outcome: PillLook?) {
        demo?.cancel()
        showLive(.processing)
        demo = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(1.6))) != nil else { return }
            self?.showLive(outcome ?? .done, for: outcome == nil ? .seconds(0.9) : .seconds(4))
        }
    }

    /// Shows `look` on both live pills, back to idle after `duration`.
    private func showLive(_ look: PillLook, for duration: Duration? = nil) {
        if duration != nil { demo?.cancel() }
        live.look = look
        // Words keep the pill horizontal at every anchor; the bottom pill shows them.
        liveSide.look = look.canStandVertical ? look : .idle
        guard let duration else { return }
        demo = Task { [weak self] in
            guard (try? await Task.sleep(for: duration)) != nil else { return }
            self?.showLive(.idle)
        }
    }

    // MARK: Made-up levels

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        levels?.cancel()
        levels = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        guard let window else {
            demo?.cancel()
            return
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        levels = Task { [weak self] in await self?.feedLevels() }
    }

    private func stop() {
        levels?.cancel()
        demo?.cancel()
    }

    /// About 20 levels a second, like the mic's: syllables of speech with short pauses. A demo source, not the app's.
    private func feedLevels() async {
        var phase = 0.0
        while (try? await Task.sleep(for: .milliseconds(50))) != nil {
            phase += 0.05
            let syllable = abs(sin(phase * 9)) * (0.55 + 0.45 * sin(phase * 1.7))
            let pause = sin(phase * 0.8) < -0.6
            let level = pause ? 0.02 : max(0.05, syllable + Double.random(in: -0.1...0.1))
            for pill in levelPills where Self.isRecording(pill.look) {
                pill.level = Self.isSilent(pill.look) ? 0 : level
            }
        }
    }

    private static func isRecording(_ look: PillLook) -> Bool {
        if case .recording = look { return true }
        return false
    }

    private static func isSilent(_ look: PillLook) -> Bool {
        if case .recording(let recording) = look { return recording.isSilent }
        return false
    }
}

/// Draws the gallery's chosen backdrop behind one pill.
private final class BackdropCell: NSView {
    private let backdrop: () -> PillPrototypeGallery.Backdrop

    init(backdrop: @escaping () -> PillPrototypeGallery.Backdrop) {
        self.backdrop = backdrop
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BackdropCell is built in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        switch backdrop() {
        case .light:
            NSColor.white.setFill()
            bounds.fill()
        case .dark:
            NSColor.black.setFill()
            bounds.fill()
        case .colour:
            // Bands of colour and thin stripes: something for the glass to bend.
            NSGradient(colors: [.systemTeal, .systemPink, .systemYellow, .systemIndigo])?.draw(in: bounds, angle: 0)
            NSColor.white.withAlphaComponent(0.35).setFill()
            for y in stride(from: 0, to: bounds.height, by: 6) {
                NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
            }
        }
    }
}
