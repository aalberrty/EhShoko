import Foundation
import Testing

/// The folder of model files and the research's references that only the development Mac has
/// (`PAGE_TRANSLATION_PRIVATE`). The models are gigabytes under non-commercial licences and
/// the references are translations of adult pages, so neither can be in the repository. Tests
/// that need the folder are the opt-in tier and are skipped without the variable:
///
///     PAGE_TRANSLATION_PRIVATE=/path/to/folder swift test --filter LlamaGenerationEnginePrivateTests
///
/// Translating all the compared pages with one model takes from minutes to an hour on a Mac's
/// CPU, so that test asks for a second variable naming the models to run, one or several of
/// `hymt2-q6k`, `hymt2-q4km`, `sakura`, `galtransl`, `qwen35`, or `all`:
///
///     PAGE_TRANSLATION_LANGUAGE_MODELS=sakura PAGE_TRANSLATION_PRIVATE=… swift test --filter …
enum PrivateTranslationFolder {
    static let variable = "PAGE_TRANSLATION_PRIVATE"
    static let modelsVariable = "PAGE_TRANSLATION_LANGUAGE_MODELS"

    private static func value(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    /// The folder this run was given, if any.
    static let root: URL? = value(variable).map {
        URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// The models the long comparison was asked to run; empty when it was not asked for.
    static let comparedModels: Set<String> = Set(
        (value(modelsVariable) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    )

    /// The file or folder at `path` inside the private folder. A missing one throws, so a
    /// variable that names the wrong folder fails the test instead of passing unnoticed.
    static func url(_ path: String) throws -> URL {
        let root = try #require(root, "Gate this test with .privateTranslationFolder")
        let url = root.appending(path: path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw Missing(path: path, root: root.path) }
        return url
    }

    /// Where a run's results are kept: the private reports folder beside the given one, never
    /// the repository.
    static func reports(_ name: String) throws -> URL {
        let root = try #require(root, "Gate this test with .privateTranslationFolder")
        let url = root.deletingLastPathComponent().appending(path: "reports/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct Missing: Error, CustomStringConvertible {
        let path: String
        let root: String
        var description: String {
            "\(path) is not in \(root); \(PrivateTranslationFolder.variable) must name the private translation folder"
        }
    }
}

extension Trait where Self == ConditionTrait {
    /// Runs a test only when the private folder is given.
    static var privateTranslationFolder: Self {
        .enabled(
            if: PrivateTranslationFolder.root != nil,
            "Set \(PrivateTranslationFolder.variable) to run the opt-in tests"
        )
    }

    /// Runs a test only when the private folder is given and models are named for the long
    /// comparison.
    static var languageModelComparison: Self {
        .enabled(
            if: PrivateTranslationFolder.root != nil && !PrivateTranslationFolder.comparedModels.isEmpty,
            "Set \(PrivateTranslationFolder.modelsVariable) to translate the compared pages"
        )
    }
}
