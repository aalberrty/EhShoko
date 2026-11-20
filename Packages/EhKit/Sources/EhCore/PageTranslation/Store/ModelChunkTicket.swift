import Foundation

/// Names a chunk transfer by where its bytes go: the destination relative to the model
/// store's folder, and the range.
///
/// It is written into the session task's description, which the system keeps with the task
/// across launches. That is how a range that arrives after the app was killed still finds
/// its file, and how a request for a range that is already under way joins it. The path is
/// relative because the app's container moves when the app is updated.
struct ModelChunkTicket: Hashable, Sendable {
    var path: String
    var first: Int64
    var count: Int64

    init(path: String, first: Int64, count: Int64) {
        self.path = path
        self.first = first
        self.count = count
    }

    /// The ticket of `request`, or `nil` when its destination is not inside `root`.
    init?(_ request: ModelChunkRequest, root: URL) {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let filePath = request.destination.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix), filePath.count > prefix.count, !request.range.isEmpty else { return nil }
        self.init(
            path: String(filePath.dropFirst(prefix.count)), first: request.range.lowerBound,
            count: Int64(request.range.count)
        )
    }

    /// `v1:<first>:<count>:<path>`; the path comes last because it may hold a colon.
    var description: String {
        "v1:\(first):\(count):\(path)"
    }

    init?(description: String?) {
        guard let parts = description?.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false),
              parts.count == 4, parts[0] == "v1", let first = Int64(parts[1]), let count = Int64(parts[2]),
              first >= 0, count > 0, !parts[3].isEmpty, !parts[3].hasPrefix("/"),
              !parts[3].split(separator: "/").contains("..")
        else { return nil }
        self.init(path: String(parts[3]), first: first, count: count)
    }

    func destination(in root: URL) -> URL {
        root.appending(path: path, directoryHint: .notDirectory)
    }

    /// Whether the destination already holds the whole range.
    func isDelivered(in root: URL) -> Bool {
        ModelFiles.size(of: destination(in: root)) == count
    }
}

/// Small file helpers the store's pieces share.
enum ModelFiles {
    /// The size of the file at `url`, or `nil` when there is no regular file.
    static func size(of url: URL) -> Int64? {
        // Not `resourceValues`: a URL caches those, and these files change between looks.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              attributes[.type] as? FileAttributeType == .typeRegular, let size = attributes[.size] as? NSNumber
        else { return nil }
        return size.int64Value
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Removes a file or folder; a missing one is not an error.
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func createFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Moves `source` to `destination`, replacing what is there.
    static func move(_ source: URL, to destination: URL) throws {
        try createFolder(destination.deletingLastPathComponent())
        remove(destination)
        try FileManager.default.moveItem(at: source, to: destination)
    }

    /// The bytes a file or a folder's files take.
    static func totalSize(of url: URL) -> Int64 {
        if let size = size(of: url) { return size }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += size(of: file) ?? 0
        }
        return total
    }
}
