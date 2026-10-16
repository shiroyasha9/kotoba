/// The instrument of the start and stop sound cues (owner, 2026-10-16). The App bundles one pair of sounds per voice,
/// made by `design/sounds`.
public enum CueVoice: String, CaseIterable, Sendable {
    /// A soft nylon string, E3 to B3. The default.
    case nylon
    /// The nylon string a fifth lower, A2 to E3.
    case low
    /// A brighter steel string, E3 to B3.
    case steel

    public enum Cue: String, Sendable {
        /// Two notes up: recording started, speak now.
        case start = "DictationStart"
        /// Two notes down: recording stopped.
        case stop = "DictationStop"
    }

    /// The saved voice. A missing value, or one this build does not have, gives nylon.
    public init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .nylon
    }

    /// The sound's resource name in the App bundle: "nylon-DictationStart".
    public func soundName(_ cue: Cue) -> String {
        "\(rawValue)-\(cue.rawValue)"
    }
}
