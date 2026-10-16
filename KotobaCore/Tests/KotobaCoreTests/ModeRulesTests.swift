import Foundation
import Testing

@testable import KotobaCore

/// The rules alone: which mode an app gets, and what a dictation into it does.
struct ModeRulesTests {
    let slack = DictationApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    let ghostty = DictationApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty")
    let unknown = DictationApp(bundleID: "com.example.unknown")

    @Test func aNewInstallPutsChatAppsInWritingAndTerminalsAndOtherAppsInCode() {
        let rules = ModeRules.standard

        #expect(rules.mode(for: slack) == .writing)
        #expect(rules.mode(for: ghostty) == .code)
        #expect(rules.mode(for: unknown) == .code)
        #expect(rules.mode(for: nil) == .code)
        #expect(rules.cleansEveryDictation.isEmpty)
    }

    @Test func terminalsStayInCodeWhenOtherAppsUseWriting() {
        var rules = ModeRules.standard
        rules.otherApps = .writing

        #expect(rules.mode(for: ghostty) == .code)
        #expect(rules.mode(for: unknown) == .writing)
    }

    @Test func outputIsCleanupOnlyWithTheChordOrAModeThatCleansEveryDictation() {
        var rules = ModeRules.standard

        #expect(rules.output(for: slack, isCleanupChord: false) == .transcript)
        #expect(rules.output(for: slack, isCleanupChord: true) == .cleanup(.writing))
        #expect(rules.output(for: ghostty, isCleanupChord: true) == .cleanup(.code))
        rules.cleansEveryDictation = [.writing]
        #expect(rules.output(for: slack, isCleanupChord: false) == .cleanup(.writing))
        #expect(rules.output(for: ghostty, isCleanupChord: false) == .transcript)
    }

    /// The owner's edits: an added app, a moved standard app, a removed standard app, and both settings.
    var edited: ModeRules {
        var rules = ModeRules.standard
        rules.apps["com.example.notes"] = .writing
        rules.apps["com.mitchellh.ghostty"] = .writing
        rules.apps["com.tinyspeck.slackmacgap"] = nil
        rules.otherApps = .writing
        rules.cleansEveryDictation = [.code]
        return rules
    }

    @Test func noChangesGiveTheStandardRules() {
        #expect(ModeChanges().applied(to: .standard) == .standard)
        #expect(ModeChanges(.standard, over: .standard) == ModeChanges())
    }

    @Test func theSavedFormHoldsOnlyTheOwnersChanges() {
        let changes = ModeChanges(edited, over: .standard)

        #expect(
            changes
                == ModeChanges(
                    apps: ["com.example.notes": .writing, "com.mitchellh.ghostty": .writing],
                    removed: ["com.tinyspeck.slackmacgap"], otherApps: .writing, cleansEveryDictation: [.code]))
        #expect(changes.applied(to: .standard) == edited)
    }

    @Test func appsALaterBuildAddsReachAnOwnerWhoEditedTheList() {
        let changes = ModeChanges(edited, over: .standard)
        var later = ModeRules.standard
        later.apps["com.example.newchat"] = .writing
        // The owner's own choice for an app wins over a later standard list.
        later.apps["com.example.notes"] = .code

        let rules = changes.applied(to: later)

        #expect(rules.mode(for: DictationApp(bundleID: "com.example.newchat")) == .writing)
        #expect(rules.apps["com.example.notes"] == .writing)
        #expect(rules.apps["com.tinyspeck.slackmacgap"] == nil)
        #expect(rules.apps["com.mitchellh.ghostty"] == .writing)
    }

    @Test func changesSurviveAJSONRoundTrip() throws {
        let changes = ModeChanges(edited, over: .standard)

        #expect(try JSONDecoder().decode(ModeChanges.self, from: JSONEncoder().encode(changes)) == changes)
    }

    /// A later build may add a mode or a field; going back to this build must not lose the owner's changes.
    @Test func aLaterBuildsChangesDropOnlyWhatThisBuildCannotRead() throws {
        let later = """
            {"apps":{"com.example.notes":"writing","com.apple.Terminal":"shell"},"removed":["com.apple.mail"],\
            "otherApps":"email","cleansEveryDictation":["writing","email"],"websites":{"mail.google.com":"writing"}}
            """

        let changes = try JSONDecoder().decode(ModeChanges.self, from: Data(later.utf8))

        #expect(
            changes
                == ModeChanges(
                    apps: ["com.example.notes": .writing], removed: ["com.apple.mail"], otherApps: .code,
                    cleansEveryDictation: [.writing]))
    }

    @Test func missingFieldsTakeTheirDefaults() throws {
        let changes = try JSONDecoder().decode(
            ModeChanges.self, from: Data(#"{"apps":{"com.example.notes":"writing"}}"#.utf8))

        #expect(changes == ModeChanges(apps: ["com.example.notes": .writing]))
    }
}
