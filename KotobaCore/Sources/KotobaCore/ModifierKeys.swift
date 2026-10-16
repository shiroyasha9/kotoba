/// Modifier keys, left and right apart, as the app's event tap reports them. In a `Chord`, a kind with both
/// sides set (`.option`) takes either side; one side (`.rightOption`) takes only that key.
public struct ModifierKeys: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let leftControl = Self(rawValue: 1 << 0)
    public static let rightControl = Self(rawValue: 1 << 1)
    public static let leftOption = Self(rawValue: 1 << 2)
    public static let rightOption = Self(rawValue: 1 << 3)
    public static let leftShift = Self(rawValue: 1 << 4)
    public static let rightShift = Self(rawValue: 1 << 5)
    public static let leftCommand = Self(rawValue: 1 << 6)
    public static let rightCommand = Self(rawValue: 1 << 7)
    /// The Fn / Globe key; it has one side.
    public static let function = Self(rawValue: 1 << 8)

    public static let control: Self = [.leftControl, .rightControl]
    public static let option: Self = [.leftOption, .rightOption]
    public static let shift: Self = [.leftShift, .rightShift]
    public static let command: Self = [.leftCommand, .rightCommand]
    public static let rightSides: Self = [.rightControl, .rightOption, .rightShift, .rightCommand]
    /// Each kind with all its sides, in Apple's display order: fn ⌃ ⌥ ⇧ ⌘.
    public static let allKinds: [Self] = [.function, .control, .option, .shift, .command]

    /// Each kind present, with both its sides: right ⌥ and ⌘ give ⌥⌘.
    public var kinds: Self {
        var kinds: Self = []
        for kind in Self.allKinds where !isDisjoint(with: kind) {
            kinds.formUnion(kind)
        }
        return kinds
    }

    /// How many kinds (fn, ⌃, ⌥, ⇧, ⌘) it holds; both sides of one kind count once.
    public var kindCount: Int {
        Self.allKinds.count { !isDisjoint(with: $0) }
    }

    /// Read as a chord's modifiers: every kind in it is held, on one of the sides it allows.
    func isSatisfied(by held: Self) -> Bool {
        Self.allKinds.allSatisfy { kind in
            let sides = intersection(kind)
            return sides.isEmpty || !sides.isDisjoint(with: held)
        }
    }

    /// Read as a chord's modifiers: whenever `other` (another chord's modifiers) is satisfied, so is this.
    func isImplied(by other: Self) -> Bool {
        Self.allKinds.allSatisfy { kind in
            let sides = intersection(kind)
            let otherSides = other.intersection(kind)
            return sides.isEmpty || (!otherSides.isEmpty && otherSides.isSubset(of: sides))
        }
    }
}
