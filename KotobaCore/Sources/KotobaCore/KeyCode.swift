/// The macOS virtual key codes (Carbon's `kVK_*`) that the rules name; this module does not link Carbon.
public enum KeyCode {
    public static let ansiA: UInt16 = 0x00
    public static let ansiH: UInt16 = 0x04
    public static let ansiZ: UInt16 = 0x06
    public static let ansiX: UInt16 = 0x07
    public static let ansiC: UInt16 = 0x08
    public static let ansiV: UInt16 = 0x09
    public static let ansiF: UInt16 = 0x03
    public static let ansiQ: UInt16 = 0x0C
    public static let ansiW: UInt16 = 0x0D
    public static let ansi3: UInt16 = 0x14
    public static let ansi4: UInt16 = 0x15
    public static let ansi5: UInt16 = 0x17
    public static let ansi1: UInt16 = 0x12
    public static let ansiP: UInt16 = 0x23
    public static let ansiM: UInt16 = 0x2E
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    public static let grave: UInt16 = 0x32
    public static let `return`: UInt16 = 0x24
    public static let escape: UInt16 = 0x35

    /// Keys whose events macOS marks with the fn flag although fn is up: arrows, F1-F20, Help, Home, End, Page Up,
    /// Page Down and Forward Delete.
    static func carriesFunctionFlag(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 0x7B...0x7E, 0x72...0x79, 0x7A, 0x60...0x65, 0x67, 0x69...0x6B, 0x6D, 0x6F, 0x71, 0x40, 0x4F, 0x50, 0x5A:
            true
        default: false
        }
    }
}
