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
public struct ModeRules: Sendable, Equatable, Codable {
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
