import Foundation

/// A per-app mode (story 29, docs/research/per-app-modes.md): how a dictation into its apps is cleaned up. The app in
/// front at the stop picks it through `ModeRules`, the same app a submit Return goes to.
public enum AppMode: String, CaseIterable, Sendable, Codable {
    /// Terminals, editors and coding agents: cleanup writes a clean prompt and keeps commands, paths and flags.
    case code
    /// Messages, mail and notes: cleanup writes clear sentences in the speaker's words.
    case writing
}

/// Which mode each app uses, and which modes clean every dictation, not only the ones made with the cleanup chord.
public struct ModeRules: Sendable, Equatable {
    /// Bundle ID to mode. An app is in one mode at most; an app not here uses `otherApps`.
    public var apps: [String: AppMode]
    public var otherApps: AppMode
    public var cleansEveryDictation: Set<AppMode>

    public init(apps: [String: AppMode] = [:], otherApps: AppMode = .code, cleansEveryDictation: Set<AppMode> = []) {
        self.apps = apps
        self.otherApps = otherApps
        self.cleansEveryDictation = cleansEveryDictation
    }

    /// The mode of `app`; kotoba itself in front, or an app with no bundle ID, gets `otherApps`.
    public func mode(for app: DictationApp?) -> AppMode {
        app.flatMap { apps[$0.bundleID] } ?? otherApps
    }

    /// What a dictation into `app` does: cleanup in the app's mode when the cleanup chord made it or the mode cleans
    /// every dictation, else the transcript.
    public func output(for app: DictationApp?, isCleanupChord: Bool) -> DictationOutput {
        let mode = mode(for: app)
        return isCleanupChord || cleansEveryDictation.contains(mode) ? .cleanup(mode) : .transcript
    }

    /// A new install's rules: the common terminals, editors and coding agents in Code (they stay there when the owner
    /// sets other apps to Writing), the common chat, mail and notes apps in Writing, other apps in Code, and no mode
    /// cleaning every dictation. The bundle IDs follow Jot's tone map (Apache-2.0, `PromptV1.toneCategory`).
    public static let standard = Self(
        apps: Dictionary(uniqueKeysWithValues: codeApps.map { ($0, .code) } + writingApps.map { ($0, .writing) }))

    private static let codeApps = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.cmuxterm.app",
        "dev.warp.Warp-Stable", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode",
        "dev.zed.Zed", "com.exafunction.windsurf", "com.openai.codex", "com.anthropic.claudefordesktop",
    ]

    private static let writingApps = [
        "com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram",
        "com.hnc.Discord", "com.microsoft.teams2", "com.apple.mail", "com.microsoft.Outlook", "com.superhuman.electron",
        "com.apple.Notes", "notion.id",
    ]
}

/// What the owner changed in the standard rules, the form the app saves: apps a later build adds to the standard
/// lists then reach an owner who edited the list too.
public struct ModeChanges: Sendable, Equatable, Codable {
    /// Apps the owner added, or put in another mode than the base has.
    public var apps: [String: AppMode]
    /// Base apps the owner removed; they use the mode of other apps.
    public var removed: Set<String>
    public var otherApps: AppMode
    public var cleansEveryDictation: Set<AppMode>

    public init(
        apps: [String: AppMode] = [:], removed: Set<String> = [], otherApps: AppMode = .code,
        cleansEveryDictation: Set<AppMode> = []
    ) {
        self.apps = apps
        self.removed = removed
        self.otherApps = otherApps
        self.cleansEveryDictation = cleansEveryDictation
    }

    /// The changes that turn `base` into `rules`.
    public init(_ rules: ModeRules, over base: ModeRules) {
        self.init(
            apps: rules.apps.filter { id, mode in base.apps[id] != mode },
            removed: Set(base.apps.keys).subtracting(rules.apps.keys), otherApps: rules.otherApps,
            cleansEveryDictation: rules.cleansEveryDictation)
    }

    /// `base` with these changes; the owner's choice for an app wins over the base's.
    public func applied(to base: ModeRules) -> ModeRules {
        var apps = base.apps.filter { id, _ in !removed.contains(id) }
        apps.merge(self.apps) { _, owners in owners }
        return ModeRules(apps: apps, otherApps: otherApps, cleansEveryDictation: cleansEveryDictation)
    }

    private enum CodingKeys: String, CodingKey {
        case apps
        case removed
        case otherApps
        case cleansEveryDictation
    }

    /// Never loses the owner's changes: a missing field takes its default, and a mode this build does not know
    /// (written by a later build) drops only its own entry. Fields this build does not know are ignored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let apps = try container.decodeIfPresent([String: String].self, forKey: .apps) ?? [:]
        let removed = try container.decodeIfPresent(Set<String>.self, forKey: .removed) ?? []
        let otherApps = try container.decodeIfPresent(String.self, forKey: .otherApps)
        let cleaning = try container.decodeIfPresent([String].self, forKey: .cleansEveryDictation) ?? []
        self.init(
            apps: apps.compactMapValues(AppMode.init(rawValue:)), removed: removed,
            otherApps: otherApps.flatMap(AppMode.init(rawValue:)) ?? .code,
            cleansEveryDictation: Set(cleaning.compactMap(AppMode.init(rawValue:))))
    }
}
