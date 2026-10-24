/// One setting as a settings page sees it: where its value comes from and where a change goes. The General and
/// Shortcuts pages keep their values through these, so snapshots read fixed values and write nowhere.
struct Setting<Value> {
    var read: @MainActor () -> Value
    var write: @MainActor (Value) -> Void

    /// A stand-in for snapshots: always `value`, and a change goes nowhere.
    static func fixed(_ value: Value) -> Self where Value: Sendable { Self(read: { value }, write: { _ in }) }
}
