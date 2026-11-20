import CryptoKit
import Foundation

/// SHA-256 of model files, read in blocks so a 2.5 GB file never sits in memory.
enum ModelChecksum {
    static let blockSize = 1 << 20

    /// The checksum of the file at `url` as lowercase hexadecimal. Always off the caller's
    /// actor: the largest file takes seconds.
    @concurrent
    static func sha256(of url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var blocks = 0
        while let block = try handle.read(upToCount: blockSize), !block.isEmpty {
            hasher.update(data: block)
            blocks += 1
            if blocks.isMultiple(of: 64) { try Task.checkCancellation() }
        }
        return hex(hasher.finalize())
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { byte in
            let text = String(byte, radix: 16)
            return byte < 16 ? "0" + text : text
        }.joined()
    }
}

/// A file being put together from its ranges, in order, hashed as it grows.
///
/// The part file is the state of a download: its length says which range comes next. It
/// only ever holds whole ranges, so after the app was killed the next range is known from
/// the length alone, and the hash is computed again from what is there.
///
/// Used by one task at a time, off the main actor.
final class ModelPartFile {
    let url: URL
    private(set) var length: Int64
    private var hasher = SHA256()
    private let handle: FileHandle

    /// Opens the part file, creating it when there is none. One that was cut off in the
    /// middle of a range is shortened to the last whole range.
    init(url: URL, chunkSize: Int64, fileSize: Int64) throws {
        self.url = url
        try ModelFiles.createFolder(url.deletingLastPathComponent())
        if !ModelFiles.exists(url) {
            guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        handle = try FileHandle(forUpdating: url)
        let existing = Int64(try handle.seekToEnd())
        let kept: Int64 = switch existing {
        case fileSize: fileSize
        case ..<fileSize: existing / chunkSize * chunkSize
        default: 0
        }
        if kept != existing { try handle.truncate(atOffset: UInt64(kept)) }
        length = kept
        try rehash()
    }

    private func rehash() throws {
        try handle.seek(toOffset: 0)
        var remaining = length
        while remaining > 0 {
            guard let block = try handle.read(upToCount: Int(min(Int64(ModelChecksum.blockSize), remaining))),
                  !block.isEmpty
            else { throw CocoaError(.fileReadCorruptFile) }
            hasher.update(data: block)
            remaining -= Int64(block.count)
        }
        try handle.seekToEnd()
    }

    /// Appends the range held by the file at `chunk`.
    func append(contentsOf chunk: URL) throws {
        let source = try FileHandle(forReadingFrom: chunk)
        defer { try? source.close() }
        while let block = try source.read(upToCount: ModelChecksum.blockSize), !block.isEmpty {
            try handle.write(contentsOf: block)
            hasher.update(data: block)
            length += Int64(block.count)
        }
    }

    /// Closes the file and returns the checksum of everything in it.
    func finish() throws -> String {
        try handle.close()
        return ModelChecksum.hex(hasher.finalize())
    }

    func close() {
        try? handle.close()
    }
}
