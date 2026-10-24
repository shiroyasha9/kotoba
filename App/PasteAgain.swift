import AppKit
import KotobaCore
import SwiftUI

/// Paste Again from a kotoba window: History's rows and Home's last dictation. kotoba is the active app while its window
/// is key, so a Cmd-V would land in it: the last app the owner was in comes back to the front first.
@MainActor
struct PasteAgain {
    /// The longest Paste Again waits for the app the owner was in to come back to the front.
    private static let focusWait = Duration.milliseconds(500)

    let pipeline: DictationPipeline

    /// Pastes `text` as dictation `id` into the app the owner was in. False when that app did not come back, so
    /// nothing was pasted: the text is on the clipboard (`pasteFailureAlert` says so). While a dictation records or is
    /// sent, nothing happens: its paste would race this one.
    func callAsFunction(_ text: String, of id: DictationID) async -> Bool {
        guard await pipeline.isQuiet else { return true }
        guard await Self.returnFocus() else {
            // The paste would land in kotoba: the text waits on the clipboard instead.
            await pipeline.copyAgain(text)
            return false
        }
        await pipeline.pasteAgain(text, of: id)
        return true
    }

    /// The last app the owner was in comes back to the front (kotoba's windows stay as they are), and the paste waits
    /// for its activation, at most `focusWait`. False when there is no such app or it did not come to the front in time:
    /// the paste would land in kotoba.
    private static func returnFocus() async -> Bool {
        guard NSApp.isActive else { return true }
        guard let id = FrontAppObserver.lastOtherProcessID, let app = NSRunningApplication(processIdentifier: id),
            !app.isTerminated
        else { return false }
        // The sequence observes from its creation, so the activation is not missed.
        let activations = NSWorkspace.shared.notificationCenter.notifications(
            named: NSWorkspace.didActivateApplicationNotification)
        NSApp.yieldActivation(to: app)
        _ = app.activate(from: .current, options: [])
        let wait = Task {
            for await note in activations
            where (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == id
            {
                return true
            }
            return false
        }
        let bound = Task {
            try? await Task.sleep(for: focusWait)  // Cancelled once the switch came: nothing to do.
            wait.cancel()
        }
        let isActivated = await wait.value
        bound.cancel()
        return isActivated
    }
}

extension View {
    /// Paste Again could not bring back the app the owner was in.
    func pasteFailureAlert(isPresented: Binding<Bool>) -> some View {
        alert("Couldn’t Paste", isPresented: isPresented) {
            Button("OK") {}
        } message: {
            Text("kotoba couldn’t bring back the app you were in. The text is on the clipboard: press ⌘V there.")
        }
    }
}
