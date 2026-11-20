import Foundation
import Testing

/// The language-model files that only the development Mac has, in `models/llm/` of the folder
/// `PAGE_TRANSLATION_PRIVATE` names. They are far too large for the repository, and most are
/// under non-commercial licences. Tests that need one are the opt-in tier: without the
/// variable they are skipped, so a run on GitHub needs no file from outside the repository.
///
///     PAGE_TRANSLATION_PRIVATE=/path/to/folder swift test --filter EhLlamaTests
enum PrivateModels {
    static let variable = "PAGE_TRANSLATION_PRIVATE"

    /// The folder of model files, or `nil` when the variable is unset or blank.
    static let folder: URL? = {
        guard let path = ProcessInfo.processInfo.environment[variable]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty
        else { return nil }
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        return root.appending(path: "models/llm", directoryHint: .isDirectory)
    }()

    /// The smallest model file in the folder or a folder inside it. A folder without one
    /// throws, so a variable that names the wrong place fails the test instead of passing.
    static func smallest() throws -> (url: URL, bytes: Int) {
        let folder = try #require(folder, "Gate this test with .privateModels")
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys))?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "gguf" } ?? []
        let sized = files.compactMap { url -> (url: URL, bytes: Int)? in
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let bytes = values.fileSize
            else { return nil }
            return (url, bytes)
        }
        return try #require(sized.min { $0.bytes < $1.bytes }, "No .gguf file under \(folder.path)")
    }
}

extension Trait where Self == ConditionTrait {
    /// Runs a test only when the private folder is given (`PrivateModels`).
    static var privateModels: Self {
        .enabled(if: PrivateModels.folder != nil, "Set PAGE_TRANSLATION_PRIVATE to run the opt-in tests")
    }
}
