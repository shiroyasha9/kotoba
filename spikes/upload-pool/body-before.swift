import Darwin
import Foundation

final class BodyWriter {
    /// Base64 turns 3 bytes into 4 characters, so chunks of a multiple of 3 bytes encode to pieces that join
    /// without padding in the middle.
    static let chunk = 48 * 1024

    private let output: FileHandle

    init(file: URL) throws {
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
        }
        output = try FileHandle(forWritingTo: file)
    }

    deinit {
        // Every write throws its own error first; closing a file that is already complete cannot lose data.
        try? output.close()
    }

    func write(_ text: String) throws {
        try output.write(contentsOf: Data(text.utf8))
    }

    func write(_ data: Data) throws {
        try output.write(contentsOf: data)
    }

    /// Copies `file` as is, or as base64 text.
    func write(contentsOf file: URL, base64: Bool = false) throws {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }  // Read-only: closing cannot lose data.
        while let chunk = try input.read(upToCount: Self.chunk), !chunk.isEmpty {
            try output.write(contentsOf: base64 ? chunk.base64EncodedData() : chunk)
        }
    }
}

func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    precondition(result == KERN_SUCCESS)
    return info.phys_footprint
}
guard let size = CommandLine.arguments.dropFirst().first.flatMap({ Int($0) }) else { fatalError("usage: <MiB>") }
let input = FileManager.default.temporaryDirectory.appending(path: "upload-pool-input-\(size)")
let output = FileManager.default.temporaryDirectory.appending(path: "upload-pool-output-\(size)")
try autoreleasepool {
    if !FileManager.default.fileExists(atPath: input.path) {
        let data = Data(repeating: 123, count: size * 1024 * 1024 + 1)
        try data.write(to: input)
    }
}
try autoreleasepool {
    let before = footprint()
    let start = ContinuousClock.now
    try BodyWriter(file: output).write(contentsOf: input, base64: true)
    let elapsed = ContinuousClock.now - start
    emit("sizeMiB=\(size) before=\(before) after=\(footprint()) elapsed=\(elapsed)")
}
emit("drained=\(footprint())")

/// Writes one result line; a probe prints to stdout, and the house lint bans print.
func emit(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}
