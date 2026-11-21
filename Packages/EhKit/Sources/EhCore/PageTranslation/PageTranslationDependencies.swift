import Dependencies
import EhModels
import EhPageTranslation
import Foundation
import Synchronization

// Page translation as a dependency. A reader's model reads `@Dependency(\.pageTranslation)`
// when Translate is first pressed and opens a session; nothing is added at the root, and
// nothing here is made before that first read: no service, no model store, no writer.

extension PageTranslationClient: DependencyKey {
    /// Sessions of the process's one service.
    public static let liveValue = PageTranslationService.live.client

    /// Reports an issue: a test that reaches page translation installs its own client.
    public static var testValue: PageTranslationClient {
        PageTranslationClient(
            openSession: unimplemented("PageTranslationClient.openSession", placeholder: .ended)
        )
    }

    /// Sessions in which nothing ever happens.
    public static var previewValue: PageTranslationClient {
        PageTranslationClient(openSession: { _ in .ended })
    }
}

extension DependencyValues {
    /// Page translation, as a reader's model uses it.
    public var pageTranslation: PageTranslationClient {
        get { self[PageTranslationClient.self] }
        set { self[PageTranslationClient.self] = newValue }
    }
}

extension PageTranslationSession {
    /// A session whose events have ended and whose calls do nothing: a placeholder.
    public static var ended: PageTranslationSession {
        PageTranslationSession(
            events: AsyncStream { $0.finish() }, setWindow: { _ in }, retry: { _ in }, close: {}
        )
    }
}

// MARK: - Sessions of a service

extension PageTranslationService {
    /// The reader's side of this service.
    public nonisolated var client: PageTranslationClient {
        PageTranslationClient(openSession: { gid in self.openSession(gid: gid) })
    }

    /// Opens a session. Its calls are carried out one after the other, in the order they were
    /// made, by a task of its own; a session that is let go without `close` is closed.
    nonisolated func openSession(gid: String) -> PageTranslationSession {
        let id = UUID()
        let (events, eventContinuation) = AsyncStream.makeStream(of: PageTranslationEvent.self)
        let (calls, callContinuation) = AsyncStream.makeStream(of: SessionCall.self)
        let handle = SessionHandle(calls: callContinuation)
        Task {
            await self.perform(.open(id, gid: gid, events: eventContinuation))
            calls: for await call in calls {
                switch call {
                case let .window(window): await self.perform(.window(id, window))
                case let .retry(pageIndex): await self.perform(.retry(id, pageIndex: pageIndex))
                case .close: break calls
                }
            }
            await self.perform(.close(id))
        }
        return PageTranslationSession(
            events: events,
            setWindow: { handle.calls.yield(.window($0)) },
            retry: { handle.calls.yield(.retry($0)) },
            close: { handle.close() }
        )
    }

    private enum SessionCall: Sendable {
        case window(PageTranslationWindow)
        case retry(Int)
        case close
    }

    /// Held by a session's closures: when the last copy of the session is let go, so is this,
    /// and the session closes.
    private final class SessionHandle: Sendable {
        let calls: AsyncStream<SessionCall>.Continuation

        init(calls: AsyncStream<SessionCall>.Continuation) {
            self.calls = calls
        }

        func close() {
            calls.yield(.close)
            calls.finish()
        }

        deinit { close() }
    }
}

// MARK: - The app's service

extension PageTranslationService {
    /// The process's one service, made the first time `\.pageTranslation` is read.
    static let live: PageTranslationService = {
        let service = PageTranslationService(environment: .live)
        used.withLock { $0 = service }
        return service
    }()

    /// The live service once it exists, so a memory warning never creates it.
    private static let used = Mutex<PageTranslationService?>(nil)

    /// The app calls this when the system warns about memory. While page translation has not
    /// been used in this process it does nothing at all.
    public static func memoryWarningReceived() {
        guard let service = used.withLock({ $0 }) else { return }
        Task { await service.perform(.memoryWarning) }
    }

    /// How a language model becomes a translator: its one file loaded through llama.cpp,
    /// under the translator of the choice. A choice is offered only once the catalog has its
    /// file, so until then nothing reaches this.
    public static let languageModelLoader: PageTranslatorLoader.LanguageModelLoader? =
        PageTranslatorLoader.llamaLanguageModel
}

extension PageTranslationEnvironment {
    /// The app's: the model store's installed files, the image cache's bytes, the real models,
    /// the process's one writer and one patch store. Their live values are taken directly, as
    /// the writer takes the database, so an override that happens to be active when the
    /// service is first reached cannot stick to it.
    static var live: PageTranslationEnvironment {
        let store = PageTranslationModelStore.liveValue
        let settings = SettingsStoreKey.liveValue
        return PageTranslationEnvironment(
            prepare: {
                // Not part of launch: the store reads its folder, adopts files, goes on with
                // a download. Whoever deletes a model lets the service drop it first.
                await MainActor.run {
                    store.unloadBeforeDeleting = { artifacts in await PageTranslationService.live.perform(.unload(artifacts)) }
                }
                await store.refresh()
            },
            setup: {
                await MainActor.run { () -> PageTranslationSetup? in
                    // A model chosen while it was downloading becomes the choice once it is
                    // installed, also when the Translation screen was never opened again.
                    store.applyPendingChoices(in: settings)
                    guard let modelSet = store.resolvedModelSet else { return nil }
                    return PageTranslationSetup.resolve(modelSet: modelSet, repaint: store.resolvedRepaint) {
                        store.installedFiles(of: $0)
                    }
                }
            },
            imageData: { url in
                if url.isFileURL { return try await readFile(url) }
                // The reader's own source of a page's bytes: its disk cache first, the network
                // otherwise, so a page is never downloaded twice. Its live value is the app's.
                @Dependency(\.imageCacheClient) var imageCache
                return try await imageCache.imageData(url)
            },
            loadPipeline: { configuration in
                // The fonts' first use costs tens of milliseconds: paid while the models load.
                Task.detached(priority: .utility) { _ = FontLibrary.bundled }
                return try await PagePipeline.load(configuration, languageModel: PageTranslationService.languageModelLoader)
            },
            writer: .liveValue,
            patchStore: .liveValue,
            logger: .liveValue
        )
    }

    @concurrent
    private static func readFile(_ url: URL) async throws -> Data {
        try Data(contentsOf: url, options: .mappedIfSafe)
    }
}
