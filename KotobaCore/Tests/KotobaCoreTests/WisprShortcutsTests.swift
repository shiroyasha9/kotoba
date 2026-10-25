import Testing

@testable import KotobaCore

/// Wispr Flow's `prefs.user.shortcuts` in, the chords onboarding saves out. The fixtures are made up, not anyone's file.
struct WisprShortcutsTests {
    private static func shortcuts(_ wispr: [String: String], handsFree: Chord = .defaultHandsFree) -> WisprShortcuts {
        WisprShortcuts(
            shortcuts: wispr, handsFree: handsFree, pushToTalk: nil, cleanup: .defaultCleanup, pasteLast: nil,
            polishLast: nil)
    }

    @Test func popoIsHandsFreeAndPttIsPushToTalk() {
        let found = Self.shortcuts([
            "61": "popo", "59+58": "ptt", "55+59+9": "paste_last_text", "53": "dismiss", "18+58": "polish",
        ])
        #expect(found.handsFree == .usable(Chord(modifiers: .rightOption)))
        #expect(found.pushToTalk == .usable(Chord(modifiers: [.control, .option])))
        #expect(found.chords.map(\.0) == [.handsFree, .pushToTalk])
    }

    @Test func leftModifierCodesAreEitherSideAndRightCodesStayRight() {
        #expect(WisprShortcuts.chord(wisprKeys: "55+58+59") == Chord(modifiers: [.command, .option, .control]))
        #expect(WisprShortcuts.chord(wisprKeys: "54+62") == Chord(modifiers: [.rightCommand, .rightControl]))
        #expect(WisprShortcuts.chord(wisprKeys: "63") == Chord(modifiers: .function))
    }

    @Test func aKeyAndAMouseButtonBecomeTheChordsTrigger() {
        #expect(WisprShortcuts.chord(wisprKeys: "1+56+58") == Chord(modifiers: [.shift, .option], keyCode: 1))
        #expect(WisprShortcuts.chord(wisprKeys: "4099") == Chord(mouseButton: 3))
        #expect(WisprShortcuts.chord(wisprKeys: "4098+58") == Chord(modifiers: .option, mouseButton: 2))
    }

    @Test(arguments: ["1+2+58", "179", "65535", "58+x", ""])
    func keysKotobaCannotHoldGiveNoChord(keys: String) {
        #expect(WisprShortcuts.chord(wisprKeys: keys) == nil)
    }

    @Test func aModeWithoutKeysInWisprFlowIsNil() {
        let found = Self.shortcuts(["61": "popo", "18+58": "polish"])
        #expect(found.pushToTalk == nil)
        #expect(found.chords.map(\.0) == [.handsFree])
    }

    @Test func aChordKotobaRefusesIsUnusableAndKeepsKotobasOwn() {
        // ⇧ alone is refused for push to talk; a double fn press is no chord at all.
        let found = Self.shortcuts(["179": "popo", "56": "ptt"])
        #expect(found.handsFree == .unusable)
        #expect(found.pushToTalk == .unusable)
        #expect(found.chords.isEmpty)
    }

    @Test func aRefusedChordInOneModeLeavesTheOtherMode() {
        // ⌃⌥⇧⌘ is kotoba's cleanup chord, so hands-free cannot take it; push to talk's right ⌥ still works.
        let found = Self.shortcuts(["55+58+59+56": "popo", "61": "ptt"])
        #expect(found.handsFree == .unusable)
        #expect(found.pushToTalk == .usable(Chord(modifiers: .rightOption)))
        #expect(found.chords.map(\.0) == [.pushToTalk])
    }

    @Test func theFirstReadableChordOfAnActionIsTaken() {
        let found = Self.shortcuts(["179": "popo", "61": "popo"])
        #expect(found.handsFree == .usable(Chord(modifiers: .rightOption)))
    }

    /// Welcome takes Wispr Flow's chords only for a way to dictate that still has kotoba's own: a chord the owner
    /// changed (onboarding resumed later) stays.
    @Test func welcomeTakesAChordOnlyWhereKotobasOwnIsStillSet() {
        let found = Self.shortcuts(["61": "popo", "49+58": "ptt"])
        let ptt = Chord(modifiers: .option, keyCode: 49)
        #expect(
            found.chordsToTake(handsFree: .defaultHandsFree, savedPushToTalk: nil).map(\.1) == [
                Chord(modifiers: .rightOption), ptt,
            ])
        let changed = Chord(modifiers: .function)
        #expect(found.chordsToTake(handsFree: changed, savedPushToTalk: nil).map(\.0) == [.pushToTalk])
        #expect(found.chordsToTake(handsFree: .defaultHandsFree, savedPushToTalk: changed).map(\.0) == [.handsFree])
    }

    /// "Imported from Wispr Flow" shows while a way to dictate has Wispr Flow's chord, also when it equals kotoba's
    /// default, and goes once the owner changes it. A mode that follows Wispr Flow's hands-free chord without its own
    /// Wispr Flow chord is not imported.
    @Test func aModeIsImportedWhileItsChordIsWisprFlows() {
        let rightOption = Chord(modifiers: .rightOption)
        let found = Self.shortcuts(["61": "popo"], handsFree: rightOption)
        #expect(found.isImported(.handsFree, chord: rightOption))
        #expect(!found.isImported(.handsFree, chord: .defaultHandsFree))
        #expect(!found.isImported(.pushToTalk, chord: rightOption))
        let same = Self.shortcuts(["55+58+59": "popo"])
        #expect(same.isImported(.handsFree, chord: .defaultHandsFree))
    }
}

/// The Done step's "Open at login" switch: what it shows after a turn, and what Done applies.
struct LoginItemChoiceTests {
    @Test func doneAppliesTheFirstValueWhenTheOwnerDidNotTurnIt() {
        #expect(LoginItemChoice(isOn: true).isAppliedAtDone)
        #expect(LoginItemChoice(isOn: true).isOn)
        #expect(!LoginItemChoice(isOn: false).isOn)
    }

    @Test func aFailedTurnPutsTheSwitchBackAndDoneAppliesNothing() {
        var choice = LoginItemChoice(isOn: false)
        choice.ownerTurned(systemIsOn: false)
        #expect(!choice.isOn)
        #expect(!choice.isAppliedAtDone)
    }

    @Test func aTurnThatWaitsForApprovalStaysOn() {
        var choice = LoginItemChoice(isOn: false)
        choice.ownerTurned(systemIsOn: true)
        #expect(choice.isOn)
        #expect(!choice.isAppliedAtDone)
    }
}
