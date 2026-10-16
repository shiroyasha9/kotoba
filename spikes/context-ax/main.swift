// Context-awareness spike (docs/research/context-awareness.md, section 4): how long do the Accessibility reads that
// context needs take in one app, and how long does Vision OCR take on one window-sized image? Prints JSON lines with
// timings and lengths only, never the text read, so personal text stays out of the output.
//
// Usage:
//   probe ax PID [--repeat N] [--wake]   reads the app's focused window and field N times (default 5); --wake sets
//                                        AXManualAccessibility first (Electron) and times until a text field reads
//   probe ocr [--fast]                   renders a 1440x900 image of code-like text and times VNRecognizeTextRequest
//
// Point `ax` only at a process you started yourself (AGENTS.md, "Processes").
import AppKit
import ApplicationServices
import Foundation
import Vision

let clock = ContinuousClock()

func ms(_ duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
}

func timed<T>(_ work: () -> T) -> (T, Double) {
    var result: T?
    let duration = clock.measure { result = work() }
    return (result!, ms(duration))
}

func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

/// A bounded breadth-first walk of the window: the text an "on-screen names" source would see.
func visibleText(of window: AXUIElement, maxNodes: Int) -> (nodes: Int, characters: Int) {
    var queue = [window]
    var nodes = 0
    var characters = 0
    while !queue.isEmpty, nodes < maxNodes {
        let element = queue.removeFirst()
        nodes += 1
        let role = attribute(kAXRoleAttribute, of: element) as? String
        if role == kAXStaticTextRole || role == kAXTextAreaRole || role == kAXTextFieldRole {
            characters += (attribute(kAXValueAttribute, of: element) as? String)?.utf16.count ?? 0
        }
        if let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] {
            queue.append(contentsOf: children)
        }
    }
    return (nodes, characters)
}

/// The first text area in the window, for an app in the background that reports no focused element.
func firstTextArea(in window: AXUIElement) -> AXUIElement? {
    var queue = [window]
    var nodes = 0
    while !queue.isEmpty, nodes < 3_000 {
        let element = queue.removeFirst()
        nodes += 1
        if attribute(kAXRoleAttribute, of: element) as? String == kAXTextAreaRole { return element }
        queue.append(contentsOf: attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? [])
    }
    return nil
}

func probe(pid: pid_t, round: Int) {
    var row: [String: Any] = ["pid": Int(pid), "round": round]
    let (app, appMs) = timed { () -> AXUIElement in
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        return app
    }
    row["appMs"] = appMs
    // A background app (launched with `open -g`) may report no focused window: fall back to its first window.
    let (window, windowMs) = timed {
        attribute(kAXFocusedWindowAttribute, of: app)
            ?? (attribute(kAXWindowsAttribute, of: app) as? [AXUIElement])?.first
    }
    row["focusedWindowMs"] = windowMs
    row["windows"] = (attribute(kAXWindowsAttribute, of: app) as? [AXUIElement])?.count ?? -1
    row["appRole"] = attribute(kAXRoleAttribute, of: app) as? String ?? "?"
    if let window {
        let window = window as! AXUIElement
        let (title, titleMs) = timed { attribute(kAXTitleAttribute, of: window) as? String }
        row["titleMs"] = titleMs
        row["titleChars"] = title?.count ?? -1
        let (document, documentMs) = timed { attribute(kAXDocumentAttribute, of: window) as? String }
        row["documentMs"] = documentMs
        row["hasDocument"] = document != nil
        let (walk, walkMs) = timed { visibleText(of: window, maxNodes: 3_000) }
        row["walkMs"] = walkMs
        row["walkNodes"] = walk.nodes
        row["walkChars"] = walk.characters
    }
    let (focused, focusedMs) = timed {
        attribute(kAXFocusedUIElementAttribute, of: app) ?? window.flatMap { firstTextArea(in: $0 as! AXUIElement) }
    }
    row["focusedMs"] = focusedMs
    guard let focused else {
        emit(row)
        return
    }
    let field = focused as! AXUIElement
    row["role"] = attribute(kAXRoleAttribute, of: field) as? String ?? "?"
    row["subrole"] = attribute(kAXSubroleAttribute, of: field) as? String ?? "-"
    let (selected, selectedMs) = timed { attribute(kAXSelectedTextAttribute, of: field) as? String }
    row["selectedMs"] = selectedMs
    row["selectedChars"] = selected?.utf16.count ?? -1
    let (count, countMs) = timed { attribute(kAXNumberOfCharactersAttribute, of: field) as? Int }
    row["countMs"] = countMs
    row["characters"] = count ?? -1
    let (range, rangeMs) = timed { () -> CFRange? in
        guard let value = attribute(kAXSelectedTextRangeAttribute, of: field) else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }
    row["rangeMs"] = rangeMs
    if let range, let count {
        // 1,000 UTF-16 units before the caret and 1,000 after: the "text near the cursor" read.
        let start = max(0, range.location - 1_000)
        var window = CFRange(location: start, length: min(count, range.location + range.length + 1_000) - start)
        let (near, nearMs) = timed { () -> String? in
            guard let value = AXValueCreate(.cfRange, &window) else { return nil }
            var text: CFTypeRef?
            let status = AXUIElementCopyParameterizedAttributeValue(
                field, kAXStringForRangeParameterizedAttribute as CFString, value, &text)
            return status == .success ? text as? String : nil
        }
        row["nearMs"] = nearMs
        row["nearChars"] = near?.utf16.count ?? -1
    }
    let (whole, wholeMs) = timed { attribute(kAXValueAttribute, of: field) as? String }
    row["wholeMs"] = wholeMs
    row["wholeChars"] = whole?.utf16.count ?? -1
    emit(row)
}

func wake(pid: pid_t) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.25)
    let start = clock.now
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    // Throwaway spike: a poll is fine here; kotoba itself would wait on AXFocusedUIElementChanged.
    while clock.now - start < .seconds(5) {
        if let focused = attribute(kAXFocusedUIElementAttribute, of: app),
            attribute(kAXNumberOfCharactersAttribute, of: focused as! AXUIElement) != nil
        {
            emit(["pid": Int(pid), "wakeToReadableMs": ms(clock.now - start)])
            return
        }
        usleep(10_000)
    }
    emit(["pid": Int(pid), "wakeToReadableMs": -1])
}

func ocr(fast: Bool) {
    let size = NSSize(width: 1_440, height: 900)
    let image = NSImage(size: size, flipped: true) { rect in
        NSColor.white.setFill()
        rect.fill()
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let line = "let session = URLSession(configuration: .ephemeral) // TranscriptionProvider.warmUp() --verbose"
        for row in 0..<52 {
            (line as NSString).draw(
                at: NSPoint(x: 16, y: 8 + Double(row) * 17),
                withAttributes: [.font: font, .foregroundColor: NSColor.black])
        }
        return true
    }
    var rect = NSRect(origin: .zero, size: size)
    let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    for round in 1...3 {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast
        let (words, elapsed) = timed { () -> Int in
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .reduce(0) { $0 + $1.split(separator: " ").count }
        }
        emit(["ocr": fast ? "fast" : "accurate", "round": round, "ms": elapsed, "words": words])
    }
}

let arguments = CommandLine.arguments
switch arguments.dropFirst().first {
case "ax":
    guard arguments.count >= 3, let pid = pid_t(arguments[2]) else { exit(2) }
    let repeats = arguments.firstIndex(of: "--repeat").flatMap { Int(arguments[$0 + 1]) } ?? 5
    if arguments.contains("--wake") { wake(pid: pid) }
    for round in 1...repeats { probe(pid: pid, round: round) }
case "ocr":
    ocr(fast: arguments.contains("--fast"))
default:
    FileHandle.standardError.write(Data("usage: probe ax PID [--repeat N] [--wake] | probe ocr [--fast]\n".utf8))
    exit(2)
}
