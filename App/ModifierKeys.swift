import CoreGraphics
import IOKit
import KotobaCore

extension ModifierKeys {
    /// From a CGEvent's or NSEvent's raw flags. The device bits (IOKit's `NX_DEVICE*KEYMASK`) tell left from
    /// right; a flag with no device bit (some synthetic events) counts as the left key. Constant-time.
    init(eventFlags flags: UInt64) {
        // A union chain, not an array literal: the tap callback does not allocate.
        self = Self.sides(
            flags, .maskControl, (NX_DEVICELCTLKEYMASK, .leftControl), (NX_DEVICERCTLKEYMASK, .rightControl))
        formUnion(
            Self.sides(flags, .maskAlternate, (NX_DEVICELALTKEYMASK, .leftOption), (NX_DEVICERALTKEYMASK, .rightOption))
        )
        formUnion(
            Self.sides(flags, .maskShift, (NX_DEVICELSHIFTKEYMASK, .leftShift), (NX_DEVICERSHIFTKEYMASK, .rightShift)))
        formUnion(
            Self.sides(flags, .maskCommand, (NX_DEVICELCMDKEYMASK, .leftCommand), (NX_DEVICERCMDKEYMASK, .rightCommand))
        )
        if flags & CGEventFlags.maskSecondaryFn.rawValue != 0 {
            insert(.function)
        }
    }

    /// `left` and `right` pair a device bit with its key.
    private static func sides(_ flags: UInt64, _ generic: CGEventFlags, _ left: (Int32, Self), _ right: (Int32, Self))
        -> Self
    {
        guard flags & generic.rawValue != 0 else { return [] }
        var keys: Self = []
        if flags & UInt64(right.0) != 0 {
            keys.insert(right.1)
        }
        if flags & UInt64(left.0) != 0 || keys.isEmpty {
            keys.insert(left.1)
        }
        return keys
    }
}
