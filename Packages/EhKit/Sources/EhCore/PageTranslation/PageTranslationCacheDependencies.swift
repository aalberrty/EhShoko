import Dependencies
import EhDatabase
import Foundation

// The page cache's two shared objects as dependencies: models read them with
// `@Dependency(\.pageTranslationResultWriter)` and `@Dependency(\.pageTranslationPatchStore)`
// and never make their own, so the process has one of each. Each is made the first time it is
// read: by the translation service, Settings' Translation screen or Clear History, never at
// launch. Nothing is added at the root.
//
// Settings shows `patchStore.size()` and clears with `writer.removeAll(patchStore:)`, which
// Clear History also calls.

extension PageTranslationResultWriter: DependencyKey {
    /// The process's writer, on the app's database. Like `EhClient.liveValue` it reads no other
    /// dependency, so an override active when it is first read cannot stick to it.
    public static let liveValue: PageTranslationResultWriter = {
        guard let database = LiveDatabase.current else {
            preconditionFailure("\\.pageTranslationResultWriter was read before launch installed the database.")
        }
        return PageTranslationResultWriter(database: database, logger: .liveValue)
    }()

    /// A writer on the test's database (`\.database`: an empty in-memory one unless the test
    /// installs its own).
    public static var testValue: PageTranslationResultWriter {
        @Dependency(\.database) var database
        @Dependency(\.appLogger) var logger
        return PageTranslationResultWriter(database: database, logger: logger)
    }

    public static var previewValue: PageTranslationResultWriter { testValue }
}

extension PageTranslationPatchStore: DependencyKey {
    /// The process's store, `Library/Caches/PageTranslation`. Making it touches no file.
    public static let liveValue = PageTranslationPatchStore()

    /// A store over a folder of its own in the temporary directory, which exists only once
    /// something is written there.
    public static var testValue: PageTranslationPatchStore {
        PageTranslationPatchStore(
            directory: URL.temporaryDirectory.appending(
                path: "PageTranslationPatches-\(UUID().uuidString)", directoryHint: .isDirectory
            )
        )
    }

    public static var previewValue: PageTranslationPatchStore { testValue }
}

extension DependencyValues {
    /// The one batching writer of translated pages' text.
    public var pageTranslationResultWriter: PageTranslationResultWriter {
        get { self[PageTranslationResultWriter.self] }
        set { self[PageTranslationResultWriter.self] = newValue }
    }

    /// The one store of translated pages' patch files.
    public var pageTranslationPatchStore: PageTranslationPatchStore {
        get { self[PageTranslationPatchStore.self] }
        set { self[PageTranslationPatchStore.self] = newValue }
    }
}
