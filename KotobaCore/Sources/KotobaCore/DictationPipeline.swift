/// A key event from the Ctrl+Opt+Cmd chord or Esc, as the app's event tap reports it.
public enum HotkeyEvent: Sendable, Equatable {
    case chordDown
    case chordUp
    case escape
}

/// What the indicator shows.
public enum DictationState: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case failed(DictationID)
}

/// The dictation pipeline core. Hotkey events go in; every effect goes out through a port.
public actor DictationPipeline {
    public struct Ports: Sendable {
        public let audio: any AudioSource
        public let provider: any TranscriptionProvider
        public let paster: any Paster
        public let pasteboard: any Pasteboard
        public let clock: any PipelineClock
        public let store: any Store

        public init(
            audio: any AudioSource,
            provider: any TranscriptionProvider,
            paster: any Paster,
            pasteboard: any Pasteboard,
            clock: any PipelineClock,
            store: any Store
        ) {
            self.audio = audio
            self.provider = provider
            self.paster = paster
            self.pasteboard = pasteboard
            self.clock = clock
            self.store = store
        }
    }

    private let ports: Ports
    public private(set) var state: DictationState = .idle

    public init(ports: Ports) {
        self.ports = ports
    }

    public func handle(_ event: HotkeyEvent) async {}
}
