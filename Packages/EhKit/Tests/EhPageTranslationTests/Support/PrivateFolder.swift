import Foundation
import Testing

/// The folder of real pages, model files and the research's references that only the
/// development Mac has. They cannot be in the repository: the pages are adult material and
/// the models are large and under non-commercial licences.
///
/// Tests that need it are the opt-in tier. They run only when `PAGE_TRANSLATION_PRIVATE` names
/// the folder and are skipped everywhere else, so a run without it (on GitHub, say) needs no
/// file from outside the repository:
///
///     PAGE_TRANSLATION_PRIVATE=/path/to/folder swift test --filter EhPageTranslationTests
///
/// Mark such a test `@Test(.privateFolder)` and reach its files with
/// `try PrivateFolder.required().url("relative/path")`.
struct PrivateFolder: Sendable {
    static let variable = "PAGE_TRANSLATION_PRIVATE"

    let root: URL

    /// The folder `environment` names, or `nil` when the variable is unset or blank.
    static func named(in environment: [String: String]) -> PrivateFolder? {
        guard let path = environment[variable]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty
        else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        return PrivateFolder(root: URL(fileURLWithPath: expanded, isDirectory: true))
    }

    /// The folder this test run was given, if any.
    static let current = named(in: ProcessInfo.processInfo.environment)

    /// The folder this run was given; throws in a test that was not gated with
    /// `.privateFolder`.
    static func required() throws -> PrivateFolder {
        try #require(current, "Gate this test with .privateFolder")
    }

    /// The file or folder at `path` inside the private folder. A missing file throws, so a
    /// variable that names the wrong folder fails the test instead of passing unnoticed.
    func url(_ path: String) throws -> URL {
        let url = root.appending(path: path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw Missing(path: path, root: root.path) }
        return url
    }

    /// The files of the folder at `path` whose extension is one of `extensions`, sorted by name.
    func files(in path: String, withExtensions extensions: Set<String>) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url(path), includingPropertiesForKeys: nil)
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    struct Missing: Error, CustomStringConvertible {
        let path: String
        let root: String
        var description: String {
            "\(path) is not in \(root); \(PrivateFolder.variable) must name the private translation folder"
        }
    }
}

extension Trait where Self == ConditionTrait {
    /// Runs a test only when the private folder is given (`PrivateFolder`).
    static var privateFolder: Self {
        .enabled(if: PrivateFolder.current != nil, "Set PAGE_TRANSLATION_PRIVATE to run the opt-in tests")
    }
}
