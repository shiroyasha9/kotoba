import AppKit
import KotobaCore

/// A thin bar that empties over a `Countdown`. Custom because the native `ProgressView(timerInterval:)` redraws
/// in kotoba's process at the frame rate (measured: 0.6 s CPU per 7 s pill and +2 MB, docs/research/memory-spike.md).
/// Here one Core Animation run per start or resume moves it in the render server; a held countdown stops it.
final class CountdownBar: NSView {
    /// The height of the native mini progress bar.
    static let thickness: CGFloat = 4

    private let fill = CALayer()

    var countdown: Countdown? {
        didSet { needsLayout = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Self.thickness / 2
        fill.cornerRadius = Self.thickness / 2
        // The bar shrinks toward its leading end.
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer?.addSublayer(fill)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CountdownBar is built in code")
    }

    override func layout() {
        super.layout()
        fill.removeAnimation(forKey: "countdown")
        guard let countdown else { return }
        let now = ContinuousClock.now
        let width = bounds.width * countdown.fraction(at: now)
        let remaining = countdown.remaining(at: now)
        let runs = !countdown.isHeld && remaining > .zero
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.bounds = CGRect(x: 0, y: 0, width: runs ? 0 : width, height: bounds.height)
        fill.position = CGPoint(x: 0, y: bounds.midY)
        CATransaction.commit()
        guard runs else { return }
        let run = CABasicAnimation(keyPath: "bounds.size.width")
        run.fromValue = width
        run.toValue = 0
        run.duration = remaining / .seconds(1)
        run.timingFunction = CAMediaTimingFunction(name: .linear)
        fill.add(run, forKey: "countdown")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            fill.backgroundColor = NSColor.secondaryLabelColor.cgColor
        }
    }
}

/// A bar whose filled part follows the mic level: left to right, or bottom to top when vertical. Custom because
/// `NSLevelIndicator` draws only horizontally, and the pill stands vertical at a side edge.
final class LevelMeter: NSView {
    private static let length: CGFloat = 56
    private static let thickness: CGFloat = 6

    private let fill = CALayer()
    private lazy var horizontalConstraints = [
        widthAnchor.constraint(equalToConstant: Self.length),
        heightAnchor.constraint(equalToConstant: Self.thickness),
    ]
    private lazy var verticalConstraints = [
        widthAnchor.constraint(equalToConstant: Self.thickness),
        heightAnchor.constraint(equalToConstant: Self.length),
    ]

    var level: CGFloat = 0 {
        // A muted mic sends the same 0 ten times a second.
        didSet { if level != oldValue { needsLayout = true } }
    }

    var isVertical = false {
        didSet {
            guard isVertical != oldValue else { return }
            NSLayoutConstraint.deactivate(isVertical ? horizontalConstraints : verticalConstraints)
            NSLayoutConstraint.activate(isVertical ? verticalConstraints : horizontalConstraints)
            needsLayout = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        fill.cornerRadius = 3
        layer?.addSublayer(fill)
        updateColors()
        NSLayoutConstraint.activate(horizontalConstraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LevelMeter is built in code")
    }

    override func layout() {
        super.layout()
        let level = max(0, min(1, level))
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        fill.frame =
            isVertical
            ? CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * level)
            : CGRect(x: 0, y: 0, width: bounds.width * level, height: bounds.height)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            fill.backgroundColor = NSColor.labelColor.cgColor
        }
    }
}
