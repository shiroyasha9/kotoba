/// The mic settings the first launch of 0.5.0 may change, once (docs/research/ui-redesign.md, "Microphone"). The app
/// keeps them in UserDefaults; this is the decision, so tests run it from each install's state.
public struct MicrophoneSettings: Sendable, Equatable {
    /// The owner's order by UID, first choice first.
    public var order: [String]
    /// The Microphone page's switch (`InputDevicePolicy.micInUse`).
    public var bluetoothOnlyWhenListed: Bool
    /// Set once the first launch has decided, never before.
    public var isFirstLaunchChecked: Bool

    public init(order: [String], bluetoothOnlyWhenListed: Bool, isFirstLaunchChecked: Bool) {
        self.order = order
        self.bluetoothOnlyWhenListed = bluetoothOnlyWhenListed
        self.isFirstLaunchChecked = isFirstLaunchChecked
    }

    /// The settings after the first launch's check. `isUpdate`: the Mac ran 0.4 (onboarding done, or an order saved).
    /// Only a Mac with no built-in mic changes. 0.4.6 recorded from its Bluetooth default, which is the switch off, so an
    /// update turns the switch off and leaves the order alone: the decision needs no Bluetooth mic connected at this
    /// launch (a login launch, a relaunch after an update). A new install lists the Bluetooth default it has now. An
    /// empty device list (CoreAudio could not be read) decides nothing, and the next launch checks again.
    public func afterFirstLaunch(isUpdate: Bool, defaultInput: AudioDevice?, devices: [AudioDevice]) -> Self {
        guard !isFirstLaunchChecked, !devices.isEmpty else { return self }
        var after = self
        after.isFirstLaunchChecked = true
        let inputs = devices.filter(\.hasInput)
        guard !inputs.contains(where: { $0.transport == .builtIn }) else { return after }
        if isUpdate {
            after.bluetoothOnlyWhenListed = false
        } else if order.isEmpty,
            let followed = inputs.first(where: { $0.uid == defaultInput?.uid }), followed.transport == .bluetooth
        {
            after.order = [followed.uid]
        }
        return after
    }
}
