// Throwaway spike: first-show cost of the glass indicator panel, and the footprint it holds
// before creation, while hidden, and after release. Usage: open -g -n build/PanelCost.app --args <out-file>
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "/dev/null"
func log(_ line: String) {
    if let handle = FileHandle(forWritingAtPath: out) {
        handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close()
    } else { try? Data((line + "\n").utf8).write(to: URL(filePath: out)) }
}
func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return Double(info.phys_footprint) / 1_048_576
}

@MainActor func makePanel() -> NSPanel {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 40), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.isReleasedWhenClosed = false
    let label = NSTextField(labelWithString: "Listening")
    let row = NSStackView(views: [label])
    let glass = NSGlassEffectView(frame: panel.contentLayoutRect)
    glass.cornerRadius = 20; glass.contentView = row; panel.contentView = glass
    return panel
}

final class Delegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item?.button?.title = "P"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            log(String(format: "idle, no panel: %.1f MB", footprintMB()))
            var times: [Double] = []
            var panel: NSPanel? = nil
            for run in 1...5 {
                let t0 = ContinuousClock.now
                panel = makePanel()
                panel?.orderFrontRegardless()
                panel?.displayIfNeeded()
                let elapsed = ContinuousClock.now - t0
                times.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
                try? await Task.sleep(for: .seconds(1))
                panel?.orderOut(nil)
                if run == 1 {
                    try? await Task.sleep(for: .seconds(10))
                    log(String(format: "panel created, shown once, hidden: %.1f MB", footprintMB()))
                }
                panel = nil
                try? await Task.sleep(for: .seconds(1))
            }
            try? await Task.sleep(for: .seconds(15))
            log(String(format: "panel released 15 s: %.1f MB", footprintMB()))
            log("create+show ms: " + times.map { String(format: "%.1f", $0) }.joined(separator: " "))
            log("DONE")
            NSApplication.shared.terminate(nil)
        }
    }
}
let delegate = Delegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
