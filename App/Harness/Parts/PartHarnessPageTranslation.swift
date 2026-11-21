#if DEBUG || HARNESS
import Dependencies
import EhCore
import EhDatabase
import EhModels
import Foundation
import Synchronization

/// Page translation in the part harness, for the reader designs' Translate controls:
/// `-Harness part -HarnessPart shell -HarnessTranslation <script> -PageTranslationSample ready`,
/// then "Continue reading".
///
/// - The Continue gallery is in Japanese, and its pages are the reader harness's made-up
///   images (`ReaderHarnessURLProtocol`), so the reader shows a first page and reads the
///   mark's count. Nothing reaches the site.
/// - Twelve pages around where it was left (from page 100) were translated before.
/// - The model store is the sample's (`PageTranslationSample`), ready without a download.
/// - The service follows the script; its patch files are the reader harness's
///   (`ReaderHarnessPatches`), written when a page is "done".
///
/// | Script | A page in the window |
/// |---|---|
/// | `translates` | In work for a second, then translated; a page translated before at once |
/// | `working` | In work, for good |
/// | `preparing` | Waiting for the models, for good |
/// | `fails` | In work, then failed; Retry fails again a second later |
enum PartHarnessPageTranslation: String {
    case translates, working, preparing, fails

    static let atLaunch = UserDefaults.standard.string(forKey: "HarnessTranslation").flatMap(Self.init)

    /// The pages translated before.
    nonisolated static let storedPages = Array(100..<112)

    /// The language of the Continue gallery's stored page.
    static var continueLanguage: Language { atLaunch == nil ? .english : .japanese }

    static func install(in values: inout DependencyValues) {
        guard let atLaunch else { return }
        if let store = PageTranslationSample.sampleStore {
            values.pageTranslationModelStore = store
        }
        values.pageTranslation = PartHarnessTranslationService(script: atLaunch).client
    }

    /// The Continue gallery's page addresses and stored translations, after the sample's
    /// folder is written.
    static func seed(_ gallery: Gallery) async {
        guard atLaunch != nil else { return }
        ReaderHarnessURLProtocol.install()
        await PageTranslationSample.prepare()
        @Dependency(\.database) var database
        let pages = (1...max(gallery.pageCount, 1)).map { page in
            EhDatabase.GalleryPage(
                gid: gallery.gid, index: page,
                imageURL: ReaderHarnessURLProtocol.url(forPage: page, session: "part", attempt: 0, latency: 0.15, fails: false)
            )
        }
        try? await database.upsertPages(pages)
        guard let key = PageTranslationSample.sampleStore?.resolvedModelSet?.key else { return }
        try? await database.savePageTranslations(storedPages.map {
            PageTranslation(
                gid: gallery.gid, pageIndex: $0, modelSetKey: key, imageWidth: 1_280, imageHeight: 1_810,
                regions: [], createdAt: .now
            )
        })
    }
}

/// The scripted service. Each session works on every page of its window once, and a retry
/// works on the page again.
nonisolated private final class PartHarnessTranslationService: Sendable {
    private let script: PartHarnessPageTranslation
    private let folder = URL.temporaryDirectory.appending(path: "PartHarnessPageTranslation", directoryHint: .isDirectory)

    init(script: PartHarnessPageTranslation) {
        self.script = script
    }

    var client: PageTranslationClient {
        PageTranslationClient(openSession: { [self] _ in openSession() })
    }

    private final class Session: Sendable {
        let events: AsyncStream<PageTranslationEvent>.Continuation
        let state = Mutex((started: Set<Int>(), tasks: [Task<Void, Never>]()))

        init(events: AsyncStream<PageTranslationEvent>.Continuation) {
            self.events = events
        }
    }

    private func openSession() -> PageTranslationSession {
        let (events, continuation) = AsyncStream.makeStream(of: PageTranslationEvent.self)
        let session = Session(events: continuation)
        return PageTranslationSession(
            events: events,
            setWindow: { [self] window in
                for page in window.pages.map(\.index) {
                    let isNew = session.state.withLock { $0.started.insert(page).inserted }
                    if isNew { work(on: page, in: session, isRetry: false) }
                }
            },
            retry: { [self] page in work(on: page, in: session, isRetry: true) },
            close: {
                session.state.withLock { $0.tasks.forEach { $0.cancel() } }
                continuation.finish()
            }
        )
    }

    private func work(on page: Int, in session: Session, isRetry: Bool) {
        let script = script
        let folder = folder
        let task = Task {
            func yield(_ status: PageTranslationStatus) {
                session.events.yield(PageTranslationEvent(pageIndex: page, status: status))
            }
            let isStored = PartHarnessPageTranslation.storedPages.contains(page) && !isRetry
            switch script {
            case .preparing:
                yield(.loadingModels)
                return
            case .working:
                yield(.translating)
                return
            case .fails:
                yield(.translating)
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                yield(.failed(.pipelineFailed))
                return
            case .translates:
                if !isStored {
                    yield(.translating)
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            let url = folder.appending(path: "\(page).patch")
            guard !Task.isCancelled else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if await ReaderHarnessPatches.write(page: page, to: url, isDamaged: false) {
                yield(.translated(PageTranslationOverlay(patchFile: url, variant: "part-harness")))
            } else {
                yield(.skipped)
            }
        }
        session.state.withLock { $0.tasks.append(task) }
    }
}
#endif
