/// The hotkey events for one keyboard event, stored inline so the tap callback does not allocate. One event
/// makes at most four: a missed modifier change found at a key gives a gesture change, and a missed key-up found as
/// the chord key is pressed again gives up, down and cleanup. A fifth would be dropped, not crash the tap.
public struct HotkeyEvents: Sequence, Sendable, Equatable, ExpressibleByArrayLiteral {
    private var first: HotkeyEvent?
    private var second: HotkeyEvent?
    private var third: HotkeyEvent?
    private var fourth: HotkeyEvent?
    private var count = 0

    public init() {}

    init(_ event: HotkeyEvent) {
        append(event)
    }

    /// For tests: a variadic list allocates, so the classifier uses the two inits above.
    public init(arrayLiteral events: HotkeyEvent...) {
        for event in events {
            append(event)
        }
    }

    mutating func append(_ event: HotkeyEvent) {
        switch count {
        case 0: first = event
        case 1: second = event
        case 2: third = event
        case 3: fourth = event
        default: return
        }
        count += 1
    }

    public func makeIterator() -> Iterator {
        Iterator(events: self)
    }

    public struct Iterator: IteratorProtocol {
        let events: HotkeyEvents
        var index = 0

        public mutating func next() -> HotkeyEvent? {
            defer { index += 1 }
            switch index {
            case 0: return events.first
            case 1: return events.second
            case 2: return events.third
            case 3: return events.fourth
            default: return nil
            }
        }
    }
}
