import Dependencies
import EhCore
import EhDatabase
@testable import EhFeatures
import EhModels
import Foundation
import Synchronization
import Testing

/// A page translation service that records what readers ask of it and reports what a test
/// yields. Each session it opens has its own stream of events.
nonisolated final class StubPageTranslation: Sendable {
    private struct State {
        var opened: [String] = []
        var windows: [PageTranslationWindow] = []
        var retries: [Int] = []
        var closes = 0
        var continuations: [AsyncStream<PageTranslationEvent>.Continuation] = []
    }

    private let state = Mutex(State())

    var opened: [String] { state.withLock { $0.opened } }
    var windows: [PageTranslationWindow] { state.withLock { $0.windows } }
    var lastWindow: PageTranslationWindow? { windows.last }
    var retries: [Int] { state.withLock { $0.retries } }
    var closes: Int { state.withLock { $0.closes } }

    var client: PageTranslationClient {
        PageTranslationClient(openSession: { [self] gid in
            let (events, continuation) = AsyncStream.makeStream(of: PageTranslationEvent.self)
            state.withLock {
                $0.opened.append(gid)
                $0.continuations.append(continuation)
            }
            return PageTranslationSession(
                events: events,
                setWindow: { [self] window in state.withLock { $0.windows.append(window) } },
                retry: { [self] page in state.withLock { $0.retries.append(page) } },
                close: { [self] in
                    state.withLock { $0.closes += 1 }
                    continuation.finish()
                }
            )
        })
    }

    /// Reports a status in the last session opened.
    func yield(_ page: Int, _ status: PageTranslationStatus) {
        let continuation = state.withLock { $0.continuations.last }
        continuation?.yield(PageTranslationEvent(pageIndex: page, status: status))
    }
}

/// A reader on `ReaderModelHarness`'s site and database, with a stub service, a model store
/// over a temporary folder (`TranslationStoreHarness`), and a log of the two translation
/// commands the engine is sent.
final class ReaderTranslationHarness {
    let reader: ReaderModelHarness
    let models = TranslationStoreHarness()
    let service = StubPageTranslation()
    /// `translation:<page>` and `display:<display>`, in order.
    private(set) var log: [String] = []

    init(site: ReaderTestSite = ReaderTestSite(pageCount: 10)) throws {
        reader = try ReaderModelHarness(site: site)
    }

    var gid: String { reader.gid }
    var database: AppDatabase { reader.database }

    /// The image address of a page as the engine would show it.
    func image(_ page: Int) -> URL { reader.site.image(page) }

    /// Stores every page's image address, so the reader knows them all without a request.
    func storeImageURLs() async throws {
        try await database.upsertPages((1...reader.site.pageCount).map {
            GalleryPage(gid: gid, index: $0, pageURL: reader.site.link($0), imageURL: image($0))
        })
    }

    func makeModel(initialPage: Int? = nil, gallery: Gallery? = nil) -> ReaderModel {
        let model = withDependencies {
            $0.pageTranslation = service.client
            $0.pageTranslationModelStore = models.store
        } operation: {
            reader.makeModel(initialPage: initialPage, gallery: gallery)
        }
        model.engine?.reloadTranslation = { [weak self] in self?.log.append("translation:\($0)") }
        model.engine?.setTranslationDisplay = { [weak self] in self?.log.append("display:\($0)") }
        return model
    }

    /// A started reader whose first page is on screen.
    func openedModel(initialPage: Int? = nil, gallery: Gallery? = nil) async -> ReaderModel {
        let model = makeModel(initialPage: initialPage, gallery: gallery)
        await model.start()
        model.imageDidLoad(page: model.currentPage, pixelSize: CGSize(width: 800, height: 1200))
        return model
    }

    /// Stored text for `pages` under the key of the models the store resolves to.
    func storeTranslations(of pages: [Int]) async throws {
        let key = try #require(models.store.resolvedModelSet?.key)
        try await database.savePageTranslations(pages.map {
            PageTranslation(
                gid: gid, pageIndex: $0, modelSetKey: key, imageWidth: 800, imageHeight: 1200, regions: [],
                createdAt: Date(timeIntervalSince1970: 0)
            )
        })
    }

    func clearLog() {
        log = []
    }

    /// An overlay as the service would report one.
    static func overlay(_ page: Int, _ variant: String = "v1") -> PageTranslationOverlay {
        PageTranslationOverlay(patchFile: URL(fileURLWithPath: "/patches/\(page).\(variant)"), variant: variant)
    }
}
