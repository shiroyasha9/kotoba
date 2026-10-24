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
}
