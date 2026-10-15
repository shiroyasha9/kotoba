import AppKit
import KotobaCore

/// Owns the menu bar item. Windows (Settings, History) are built on demand and released on close.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "kotoba")
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: "Quit kotoba", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
        item.menu = menu
        statusItem = item
    }
}
