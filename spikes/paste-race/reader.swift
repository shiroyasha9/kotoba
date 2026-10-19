// Reader: for each line on stdin, reads the named pasteboard's string once and prints it (or NIL).
import AppKit

let board = NSPasteboard(name: NSPasteboard.Name(CommandLine.arguments[1]))
setvbuf(stdout, nil, _IOLBF, 0)
while readLine() != nil {
    let text = board.string(forType: .string)
    print("\(DispatchTime.now().uptimeNanoseconds) \(text ?? "NIL")")
}
