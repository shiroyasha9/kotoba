import Foundation
import KotobaCore

// The request bodies `ProviderConnection.send` streams: the writer every route's body goes through, and the direct
// routes' multipart framing.

/// Writes a request body to a file piece by piece, so the audio is copied in chunks and never held whole in memory.
final class BodyWriter {
    /// Base64 turns 3 bytes into 4 characters, so chunks of a multiple of 3 bytes encode to pieces that join
    /// without padding in the middle.
    static let chunk = 48 * 1024

    private let output: FileHandle
    private let limit: Int?
    private var count = 0

    /// A write that takes the body past `limit` bytes throws `ProviderError.tooLong` instead, so a body over the cap
    /// is not written to the end.
    init(file: URL, limit: Int? = nil) throws {
        self.limit = limit
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
        try write(Data(text.utf8))
    }

    func write(_ data: Data) throws {
        if let limit, count + data.count > limit {
            throw ProviderError.tooLong(bytes: count + data.count, limit: limit)
        }
        try output.write(contentsOf: data)
        count += data.count
    }

    /// Copies `file` as is, or as base64 text. A file that is gone (the kept recording deleted outside kotoba) throws
    /// `ProviderError.audioMissing`.
    func write(contentsOf file: URL, base64: Bool = false) throws {
        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: file)
        } catch let error as CocoaError where [.fileNoSuchFile, .fileReadNoSuchFile].contains(error.code) {
            throw ProviderError.audioMissing
        }
        defer { try? input.close() }  // Read-only: closing cannot lose data.
        try write(contentsOf: input, base64: base64)
    }

    /// Copies the rest of `input`, as is or as base64 text.
    func write(contentsOf input: FileHandle, base64: Bool = false) throws {
        // FileHandle's autoreleased read buffers must drain per chunk, not after the whole upload body.
        while try autoreleasepool(invoking: {
            guard let chunk = try input.read(upToCount: Self.chunk), !chunk.isEmpty else { return false }
            try write(base64 ? chunk.base64EncodedData() : chunk)
            return true
        }) {}
    }
}

/// `multipart/form-data` framing (RFC 7578) for the direct routes. The file part goes last: xAI requires it.
struct Multipart {
    let boundary: String

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    func field(_ name: String, _ value: String, contentType: String? = nil) -> String {
        let type = contentType.map { "Content-Type: \($0)\r\n" } ?? ""
        return "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\(type)\r\n\(value)\r\n"
    }

    func fileHeader(_ name: String, filename: String, contentType: String) -> String {
        "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
            + "Content-Type: \(contentType)\r\n\r\n"
    }

    var end: String { "\r\n--\(boundary)--\r\n" }

    static func randomBoundary() -> String { "kotoba-\(UUID().uuidString)" }
}
