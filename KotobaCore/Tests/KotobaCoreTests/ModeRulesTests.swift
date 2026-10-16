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

    /// The JSON the first modes build saves in UserDefaults (`AppDefaults.modeRules`), as written there.
    static let firstBuild = """
        {"apps":{"com.tinyspeck.slackmacgap":"writing","com.example.notes":"writing","com.mitchellh.ghostty":"code"},\
        "otherApps":"code","cleansEveryDictation":["writing"]}
        """

    @Test func theFirstBuildsRulesDecodeWhole() throws {
        let rules = try JSONDecoder().decode(ModeRules.self, from: Data(Self.firstBuild.utf8))

        #expect(
            rules
                == ModeRules(
                    apps: [
                        "com.tinyspeck.slackmacgap": .writing, "com.example.notes": .writing,
                        "com.mitchellh.ghostty": .code,
                    ],
                    otherApps: .code, cleansEveryDictation: [.writing]))
    }

    /// A later build may add a mode or a field; going back to this build must not lose the owner's list.
    @Test func aLaterBuildsRulesDropOnlyWhatThisBuildCannotRead() throws {
        let later = """
            {"apps":{"com.example.notes":"writing","com.apple.Terminal":"shell"},"otherApps":"email",\
            "cleansEveryDictation":["writing","email"],"websites":{"mail.google.com":"writing"}}
            """

        let rules = try JSONDecoder().decode(ModeRules.self, from: Data(later.utf8))

        #expect(
            rules
                == ModeRules(apps: ["com.example.notes": .writing], otherApps: .code, cleansEveryDictation: [.writing]))
    }

    @Test func missingFieldsTakeTheirDefaults() throws {
        let rules = try JSONDecoder().decode(
            ModeRules.self, from: Data(#"{"apps":{"com.example.notes":"writing"}}"#.utf8))

        #expect(rules == ModeRules(apps: ["com.example.notes": .writing]))
    }

    @Test func rulesSurviveAJSONRoundTrip() throws {
        var rules = ModeRules.standard
        rules.apps["com.example.notes"] = .writing
        rules.otherApps = .writing
        rules.cleansEveryDictation = [.code]

        let decoded = try JSONDecoder().decode(ModeRules.self, from: JSONEncoder().encode(rules))

        #expect(decoded == rules)
    }
}
