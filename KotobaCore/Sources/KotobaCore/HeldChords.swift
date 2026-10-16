// MARK: - The chord a press follows

extension HotkeyClassifier {
    func isHeld(_ chord: Chord) -> Bool {
        chord.keyCode == nil ? chord.isHeld(by: modifiers) : heldKeyChord == chord
    }

    /// What the release of a held chord does, and how many keys the chord has (`Chord.rank`).
    struct RankedGesture {
        var gesture: ChordGesture
        var rank: Int
    }

    /// The chord held now with the most keys; on a tie the first in the order hands-free, push to talk, cleanup.
    func strongestHeld() -> RankedGesture? {
        var strongest: RankedGesture?
        let isSplit = pushToTalkChord.map { $0 != handsFreeChord } ?? false
        consider(handsFreeChord, isSplit ? .toggle : .tapOrHold, &strongest)
        if isSplit, let pushToTalkChord {
            consider(pushToTalkChord, .hold, &strongest)
        }
        if let cleanupChord {
            consider(cleanupChord, .tapOrHold, &strongest)
        }
        return strongest
    }

    private func consider(_ chord: Chord, _ gesture: ChordGesture, _ strongest: inout RankedGesture?) {
        guard isHeld(chord) else { return }
        let rank = chord.rank
        if rank > strongest?.rank ?? 0 {
            strongest = RankedGesture(gesture: gesture, rank: rank)
        }
    }
}
