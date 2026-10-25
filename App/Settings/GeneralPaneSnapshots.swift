import SwiftUI

// MARK: - Snapshots

@MainActor
extension Pane {
    static func generalSnapshots() -> [Snapshot] {
        [
            MainWindow.snapshot(of: .general(.sample()), named: "settings-general", height: 1_200),
            MainWindow.snapshot(
                of: .general(.sample(showsInDock: false)), named: "settings-general-dock-off", height: 1_240),
            loginFailureSnapshot(),
            positionCheck(),
        ]
    }

    /// Review B1: a failed launch-at-login change makes one system call and keeps its note. The toggle stays
    /// off, and the run fails if a second call (the old didSet loop) clears the note.
    private static func loginFailureSnapshot() -> Snapshot {
        var changes = 0
        let model = GeneralModel.sample(
            loginItem: .init(
                isOn: { false }, problem: { nil },
                change: { _ in
                    changes += 1
                    return .failed
                }))
        model.setLaunchAtLogin(true)
        var snapshot = MainWindow.snapshot(
            of: .general(model), named: "settings-general-login-failed", height: 1_260)
        snapshot.check = { _ in
            guard changes == 1, model.loginProblem == .failed, !model.isLaunchAtLoginOn else {
                return "A failed launch-at-login change made \(changes) calls and kept no note"
            }
            return nil
        }
        return snapshot
    }

    /// Audit-1 A1: the Position picker shows the indicator's position as it is now. A drop of the pill writes the
    /// position, not the page, so a page that kept its own copy said "Bottom Center" after a drop to Left.
    private static func positionCheck() -> Snapshot {
        let position = IndicatorPosition(sample: .bottomCenter)
        let model = GeneralModel.sample(
            indicatorAnchor: Setting(read: { position.anchor }, write: { position.anchor = $0 }))
        var snapshot = MainWindow.snapshot(of: .general(model), named: "settings-general-position", height: 1_200)
        snapshot.hasImage = false
        snapshot.check = { _ in
            position.anchor = .left
            return model.indicatorAnchor == .left
                ? nil : "General's Position says \(model.indicatorAnchor.title) after a drop to Left"
        }
        return snapshot
    }
}
