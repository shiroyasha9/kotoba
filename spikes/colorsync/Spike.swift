// Which drawing makes ColorSync build the 272 KB curve tables (`CMMParaCurveTag::MakeInvertedTRC`) that the release
// app keeps (62 of them, 17 MB of heap, at 25 min), and what they and other SwiftUI views cost in footprint. Each
// phase draws a SwiftUI window that is never ordered in (layers still draw at the Core Animation commit), then prints
// phys_footprint and counts the 272 KB blocks with `heap`. SPIKE_CS=srgb|p3 draws in that color space instead of the
// screen's; SPIKE_OPEN=1 also prints the footprint while the window is open. Results: docs/research/memory-spike.md,
// "Memory after use". Usage: ./build.sh && build/ColorSpike.app/Contents/MacOS/ColorSpike [phase…]
import AppKit
import SwiftUI

@MainActor
func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return Double(info.phys_footprint) / 1_048_576
}

/// Runs `heap` on this process and returns the number of 272 KB blocks.
func tableBlocks() -> Int {
    let pipe = Pipe()
    let heap = Process()
    heap.executableURL = URL(fileURLWithPath: "/usr/bin/heap")
    heap.arguments = ["-q", String(getpid())]
    heap.standardOutput = pipe
    heap.standardError = FileHandle.nullDevice
    try? heap.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    heap.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard let match = text.firstMatch(of: /272KB\[(\d+)\]/) else { return 0 }
    return Int(match.1) ?? 0
}

@MainActor
func settle() {
    for _ in 0..<200 {
        CFRunLoopRunInMode(.defaultMode, 0.005, false)
    }
}

/// SPIKE_CS=srgb or p3 draws every window in that color space instead of the screen's.
nonisolated(unsafe) let forcedColorSpace: NSColorSpace? =
    switch ProcessInfo.processInfo.environment["SPIKE_CS"] {
    case "srgb": .sRGB
    case "p3": .displayP3
    default: nil
    }

@MainActor
func draw(_ view: some View, size: NSSize = NSSize(width: 600, height: 400), colorSpace: NSColorSpace? = forcedColorSpace) {
    autoreleasepool {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        if let colorSpace { window.colorSpace = colorSpace }
        window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        settle()
        if ProcessInfo.processInfo.environment["SPIKE_OPEN"] != nil {
            print(String(format: "  while open: footprint %6.1f MB", footprintMB()))
        }
        window.contentView = nil
        window.close()
    }
    settle()
}

@MainActor
func report(_ phase: String) {
    let footprint = footprintMB()
    print(String(format: "%-28@ footprint %6.1f MB  blocks %3d", phase, footprint, tableBlocks()))
}

struct Plain: View {
    var body: some View { VStack { ForEach(0..<20) { Text("Row \($0) of plain text") } } }
}

struct Styled: View {
    var body: some View {
        VStack {
            Text("primary").foregroundStyle(.primary)
            Text("secondary").foregroundStyle(.secondary)
            Text("tertiary").foregroundStyle(.tertiary)
            Text("pink").foregroundStyle(.pink)
            Text("teal").foregroundStyle(.teal)
            Text("tint").foregroundStyle(.tint)
        }
    }
}

struct Symbols: View {
    var body: some View {
        HStack {
            ForEach(["house.fill", "clock.fill", "chart.bar.fill", "gearshape.fill", "mic.fill"], id: \.self) {
                Image(systemName: $0).foregroundStyle(.white).padding(4)
                    .background(Color.indigo.gradient, in: .rect(cornerRadius: 5))
            }
        }
    }
}

struct Icons: View {
    let ids: [String]
    var body: some View {
        VStack {
            ForEach(ids, id: \.self) { id in
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                }
            }
        }
    }
}

struct Controls: View {
    @State var on = true
    @State var text = "field"
    var body: some View {
        Form {
            Toggle("Toggle", isOn: $on)
            TextField("Field", text: $text)
            Picker("Pick", selection: $on) {
                Text("A").tag(true)
                Text("B").tag(false)
            }
            Button("Button") {}.buttonStyle(.borderedProminent)
        }.formStyle(.grouped)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let phases = CommandLine.arguments.dropFirst().isEmpty
    ? ["plain", "plain", "styled", "symbols", "icons", "controls", "repeat"] : Array(CommandLine.arguments.dropFirst())
MainActor.assumeIsolated {
    report("launch")
    let apps = [
        "com.apple.Safari", "com.apple.mail", "com.apple.Notes", "com.apple.TextEdit", "com.apple.Terminal",
        "com.apple.finder", "com.apple.Music", "com.apple.systempreferences", "com.apple.Preview",
        "com.apple.iCal",
    ]
    for phase in phases {
        switch phase {
        case "plain": draw(Plain())
        case "styled": draw(Styled())
        case "symbols": draw(Symbols())
        case "icons": draw(Icons(ids: apps))
        case "controls": draw(Controls())
        case "one": draw(Text("x"))
        case "srgb": draw(Plain(), colorSpace: .sRGB)
        case "screens":
            for screen in NSScreen.screens {
                draw(Plain(), colorSpace: screen.colorSpace)
                report(screen.colorSpace?.localizedName ?? "?")
            }
        case "p3": draw(Plain(), colorSpace: .displayP3)
        case "screen": print(NSScreen.main?.colorSpace?.localizedName ?? "none")
        case "appkit":
            autoreleasepool {
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered,
                    defer: false)
                window.isReleasedWhenClosed = false
                let label = NSTextField(labelWithString: "Plain AppKit label")
                label.frame = NSRect(x: 20, y: 20, width: 300, height: 30)
                window.contentView?.addSubview(label)
                window.displayIfNeeded()
                settle()
                window.close()
            }
            settle()
        case "relief":
            let released = malloc_zone_pressure_relief(nil, 0)
            print("released \(released / 1024) KB")
        case "toggle": draw(Form { Toggle("Switch", isOn: .constant(true)) }.formStyle(.grouped))
        case "toggleoff": draw(Form { Toggle("Switch", isOn: .constant(false)) }.formStyle(.grouped))
        case "checkbox": draw(Toggle("Check", isOn: .constant(true)).toggleStyle(.checkbox))
        case "picker": draw(Form { Picker("Pick", selection: .constant(1)) { Text("A").tag(1); Text("B").tag(2) } }.formStyle(.grouped))
        case "segmented": draw(Picker("Pick", selection: .constant(1)) { Text("A").tag(1); Text("B").tag(2) }.pickerStyle(.segmented))
        case "form": draw(Form { Text("Row"); Text("Row 2") }.formStyle(.grouped))
        case "field": draw(Form { TextField("Field", text: .constant("x")) }.formStyle(.grouped))
        case "prominent": draw(Button("Go") {}.buttonStyle(.borderedProminent))
        case "tallform": draw(Form { ForEach(0..<80) { Toggle("Switch \($0)", isOn: .constant($0 % 2 == 0)) } }.formStyle(.grouped))
        case "tallformtext": draw(Form { ForEach(0..<80) { Text("Row \($0)") } }.formStyle(.grouped))
        case "tallscroll": draw(ScrollView { VStack { ForEach(0..<200) { Text("Row \($0)") } } })
        case "talllist": draw(List { ForEach(0..<200) { Text("Row \($0)") } })
        case "fp":
            let tool = Process()
            tool.executableURL = URL(fileURLWithPath: "/usr/bin/footprint")
            tool.arguments = ["-p", String(getpid())]
            try? tool.run()
            tool.waitUntilExit()
        case "pause": sleep(40)
        case "wait":
            for _ in 0..<10 { settle() }
            sleep(10)
        case "all":
            draw(Plain())
            draw(Styled())
            draw(Symbols())
            draw(Icons(ids: apps))
            draw(Controls())
        case "dark": draw(Plain().environment(\.colorScheme, .dark))
        case "repeat":
            for _ in 0..<10 {
                draw(Plain())
                draw(Styled())
                draw(Symbols())
                draw(Icons(ids: apps))
            }
        default: print("unknown phase \(phase)")
        }
        report(phase)
    }
}
