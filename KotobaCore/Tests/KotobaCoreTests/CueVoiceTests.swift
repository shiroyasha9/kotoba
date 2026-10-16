import Testing

@testable import KotobaCore

struct CueVoiceTests {
    @Test func aNewInstallPlaysNylon() {
        #expect(CueVoice(storedValue: nil) == .nylon)
    }

    @Test(arguments: ["", "bell", "Nylon"])
    func aVoiceThisBuildDoesNotHaveFallsBackToNylon(_ stored: String) {
        #expect(CueVoice(storedValue: stored) == .nylon)
    }

    @Test(arguments: CueVoice.allCases)
    func aSavedVoiceReadsBack(_ voice: CueVoice) {
        #expect(CueVoice(storedValue: voice.rawValue) == voice)
    }

    /// The names `design/sounds/generator/cues.ts` writes into App/Sounds.
    @Test func eachVoiceNamesItsOwnPairOfSounds() {
        let names = CueVoice.allCases.flatMap { [$0.soundName(.start), $0.soundName(.stop)] }
        #expect(
            names == [
                "nylon-DictationStart", "nylon-DictationStop", "low-DictationStart", "low-DictationStop",
                "steel-DictationStart", "steel-DictationStop",
            ])
    }
}
