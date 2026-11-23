import Dependencies
import EhModels
import Foundation

// The model store as a dependency. Models reach it with
// `@Dependency(\.pageTranslationModelStore)`; nothing is added at the root, and nothing
// here runs before a screen first asks for the store.

extension PageTranslationModelStore: DependencyKey {
    /// The app's store: the folder in Application Support, a background session, Core ML,
    /// the Keychain, and the page translation settings.
    public nonisolated static let liveValue: PageTranslationModelStore = {
        @Dependency(\.appLogger) var logger
        let layout = ModelStoreLayout.applicationSupport
        let environment = ModelStoreEnvironment(
            layout: layout,
            transport: URLSessionModelTransport.background(identifier: backgroundSessionIdentifier, root: layout.root),
            compiler: .coreML,
            tokens: .keychain,
            freeSpace: ModelStoreEnvironment.volumeFreeSpace,
            connectivity: ModelStoreEnvironment.networkPath,
            log: { logger.info($0, category: "PageTranslationModels") }
        )
        return PageTranslationModelStore(environment: environment, choices: .settings(SettingsStoreKey.liveValue))
    }()

    /// A store over an empty temporary folder whose transport reports an issue for any
    /// request, so a test that forgets to install its own can never reach the network.
    public nonisolated static var testValue: PageTranslationModelStore {
        @Dependency(\.settings) var settings
        return PageTranslationModelStore(environment: .offline(), choices: .settings(settings))
    }

    public nonisolated static var previewValue: PageTranslationModelStore { testValue }

    /// The name of the app's background session, which the app delegate is handed when
    /// the system wakes the app for it.
    public nonisolated static var backgroundSessionIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "app.ehshoko") + ".page-translation-models"
    }
}

extension DependencyValues {
    public var pageTranslationModelStore: PageTranslationModelStore {
        get { self[PageTranslationModelStore.self] }
        set { self[PageTranslationModelStore.self] = newValue }
    }
}

extension ModelStoreChoices {
    /// The page translation settings of a settings store.
    public static func settings(_ settings: SettingsStore) -> ModelStoreChoices {
        ModelStoreChoices(
            modelSet: { settings.pageTranslationModelSet },
            repaint: { settings.pageTranslationRepaint },
            sourceAddress: { settings.pageTranslationSourceAddress }
        )
    }
}

extension ModelStoreEnvironment {
    /// Nothing real: an empty temporary folder, no network, no public store, no Core ML, a
    /// token in memory.
    public static func offline(
        catalog: ModelCatalog = .generated,
        root: URL = URL.temporaryDirectory.appending(path: "PageTranslationModels-\(UUID().uuidString)")
    ) -> ModelStoreEnvironment {
        ModelStoreEnvironment(
            catalog: catalog,
            layout: ModelStoreLayout(root: root),
            transport: UnimplementedModelTransport(),
            compiler: ModelCompiler(
                compile: unimplemented("ModelCompiler.compile", placeholder: URL(fileURLWithPath: "/dev/null")),
                prepare: unimplemented("ModelCompiler.prepare")
            ),
            tokens: .inMemory(),
            publicStore: nil,
            freeSpace: { _ in .max }
        )
    }
}

/// Reports an issue and refuses every request.
struct UnimplementedModelTransport: ModelTransport {
    func fetch(
        _ request: ModelChunkRequest, received: @escaping @Sendable (Int64) -> Void
    ) async throws -> ModelChunkOutcome {
        reportIssue(
            "Unimplemented: the model store asked for \(request.url.absoluteString). "
                + "Install a PageTranslationModelStore with a stub transport."
        )
        return .refused(status: 0, retryAfter: nil)
    }
}
