import EhModels
import EhPageTranslation
import Foundation

/// Decides when the work of page translation runs.
///
/// Readers open sessions and say which pages they want (`PageTranslationSession`). The
/// service answers from the cache where it can, loads the models when a page first needs
/// them, runs one page at a time through each half of the work, and writes the results.
///
/// - **Two halves.** Finding, reading and translating (stages 1 to 4) is one half; repainting,
///   drawing and writing the patch file (stages 5 and 6) is the other. At most one page is in
///   each, because the models and the Neural Engine do not get faster when shared. One more
///   page may wait between them with its bitmap; the first half starts no page while one does.
/// - **The cache first.** A page whose text is stored is never found, read or translated
///   again: with its patch file it is reported at once, and without it only the second half
///   runs. Neither waits for the models, and neither loads one.
/// - **Cancelling.** A page that is no longer wanted is cancelled; a model call under way
///   cannot be interrupted, so its half stays taken until that call returns. A page cancelled
///   before its first half ended writes nothing; one cancelled before its drawing ended keeps
///   the text its first half finished and writes no patch file.
/// - **Loading.** The three models load when the first page needs them, the repaint model
///   when the first block on artwork does. Everything is let go when the last session closes.
/// - **A language model as the translator** is one of the three and follows the same rules:
///   loaded with the others when the first page needs text, one page ahead and not three
///   (`PageTranslationPolicy`), stopped within a token when its page is cancelled, and freed
///   when the pipeline is let go. A page it was stopped on writes nothing.
///
/// The process has one, reached through `\.pageTranslation`. Nothing here runs before a
/// session is opened.
public actor PageTranslationService {
    let environment: PageTranslationEnvironment
    let clock = ContinuousClock()

    // MARK: State

    struct PageKey: Hashable, Sendable {
        var session: UUID
        var index: Int
    }

    enum Phase {
        /// Its stored text and patch file are being looked for.
        case lookingUp
        /// Waiting for stages 1 to 4, and for the models if they are not loaded.
        case needsText
        case inText
        /// Its text is there; waiting for stages 5 and 6. A page whose text was just made
        /// keeps its bitmap for them; a stored page has none yet.
        case needsDrawing(PageTranslation, PageBitmap?)
        case inDrawing(PageTranslation)
        /// Drawn; its patch file is being written. Past cancelling.
        case writing
        case finished
    }

    struct PageWork {
        var page: PageTranslationPage
        var phase: Phase
        /// Tells this work from earlier work on the same page, whose late results are dropped.
        var generation: Int
        var task: Task<Void, Never>?
        /// The status last reported.
        var status: PageTranslationStatus?
        var report = PageTranslationReport(source: .translated)
        var began: ContinuousClock.Instant?
        var waitingForModelsSince: ContinuousClock.Instant?
        var interval: PerformanceInterval?
    }

    struct Session {
        let gid: String
        let events: AsyncStream<PageTranslationEvent>.Continuation
        var window = PageTranslationWindow.empty
        var pages: [Int: PageWork] = [:]
        /// The gallery's pages with stored text for the current models.
        var stored: Set<Int> = []
        /// Animated pages, so they are not fetched again each time they come back.
        var skipped: Set<Int> = []
        /// A memory warning arrived; cleared when the reader next moves.
        var isUnderMemoryPressure = false
    }

    /// The page in a half, and the task doing its work.
    struct Slot {
        var key: PageKey
        var generation: Int
        var task: Task<Void, Never>
    }

    enum PipelineState {
        case unloaded
        case loading(Task<Void, Never>, generation: Int)
        case ready(PagePipeline)
        case failed(LoadFailure)
    }

    enum InpainterState {
        case unloaded
        case loading(Task<any Inpainter, any Error>)
        case ready(any Inpainter)
        case failed
    }

    var sessions: [UUID: Session] = [:]
    /// Sessions in the order they were opened, which is the order their pages are served in.
    var sessionOrder: [UUID] = []
    var setup: PageTranslationSetup?
    var pipelineState = PipelineState.unloaded
    var inpainterState = InpainterState.unloaded
    /// Raised whenever the models are let go, so a repaint model asked for by a drawing that
    /// started before is not loaded for it.
    var modelToken = 0
    var generation = 0
    /// The page in stages 1 to 4.
    var textSlot: Slot?
    /// The page in stages 5 and 6.
    var drawSlot: Slot?
    var hasPrepared = false
    var hasExpired = false
    var loggedFailures = 0
    private var lastCommand: Task<Void, Never>?

    public init(environment: PageTranslationEnvironment) {
        self.environment = environment
    }

    // MARK: Commands

    /// What a reader, the system or the model store asks of the service.
    enum Command: Sendable {
        case open(UUID, gid: String, events: AsyncStream<PageTranslationEvent>.Continuation)
        case window(UUID, PageTranslationWindow)
        case retry(UUID, pageIndex: Int)
        case close(UUID)
        /// The system warned about memory.
        case memoryWarning
        /// These models are about to be deleted.
        case unload([ModelArtifactID])
    }

    /// Carries out `command` after every command before it, and returns when it is done. The
    /// work a command starts goes on afterwards.
    func perform(_ command: Command) async {
        let previous = lastCommand
        let task = Task {
            await previous?.value
            await self.run(command)
        }
        lastCommand = task
        await task.value
    }

    private func run(_ command: Command) async {
        switch command {
        case let .open(id, gid, events):
            guard sessions[id] == nil else { return }
            sessions[id] = Session(gid: gid, events: events)
            sessionOrder.append(id)
            if await !refreshSetup() { await readStoredPages(of: id) }
        case let .window(id, window):
            await setWindow(window, in: id)
        case let .retry(id, pageIndex):
            await retry(pageIndex, in: id)
        case let .close(id):
            await close(id)
        case .memoryWarning:
            handleMemoryWarning()
        case let .unload(artifacts):
            guard let setup, !setup.artifacts.isDisjoint(with: artifacts) else { return }
            let running = [textSlot?.task, drawSlot?.task].compactMap { $0 }
            await adopt(nil)
            // The files go next: let the model calls under way return first.
            for task in running { await task.value }
        }
    }

    private func setWindow(_ window: PageTranslationWindow, in id: UUID) async {
        guard sessions[id] != nil else { return }
        await refreshSetup()
        guard var session = sessions[id] else { return }
        session.window = window
        session.isUnderMemoryPressure = false
        var wanted: [Int: PageTranslationPage] = [:]
        for page in window.pages { wanted[page.index] = page }
        for (index, work) in session.pages where wanted[index] != work.page {
            cancel(work)
            session.pages[index] = nil
        }
        sessions[id] = session
        for page in window.pages where sessions[id]?.pages[page.index] == nil {
            add(page, to: id)
        }
        if window.isEmpty { await environment.writer.flush() }
        pump()
    }

    private func retry(_ pageIndex: Int, in id: UUID) async {
        await refreshSetup()
        guard let work = sessions[id]?.pages[pageIndex], case .finished = work.phase else { return }
        switch work.status {
        case .failed(.modelsFailedToLoad):
            if case .failed = pipelineState { pipelineState = .unloaded }
            // Every page that failed with the models is asked for again with them.
            for session in sessionOrder {
                for (index, other) in sessions[session]?.pages ?? [:] where other.status == .failed(.modelsFailedToLoad) {
                    sessions[session]?.pages[index] = nil
                    add(other.page, to: session)
                }
            }
        case .failed:
            sessions[id]?.pages[pageIndex] = nil
            add(work.page, to: id)
        case let .translated(overlay):
            // The reader could not show the file: it is drawn again from the stored text.
            try? FileManager.default.removeItem(at: overlay.patchFile)
            sessions[id]?.pages[pageIndex] = nil
            add(work.page, to: id)
        default:
            return
        }
        pump()
    }

    private func close(_ id: UUID) async {
        guard let session = sessions.removeValue(forKey: id) else { return }
        sessionOrder.removeAll { $0 == id }
        for work in session.pages.values { cancel(work) }
        session.events.finish()
        await environment.writer.flush()
        if sessions.isEmpty { unloadModels() }
        pump()
    }

    /// The repaint model goes first, and only the pages on screen stay in work until the
    /// reader moves. Work that is past cancelling (a patch file being written) ends by itself.
    private func handleMemoryWarning() {
        dropInpainter()
        for id in sessionOrder {
            guard var session = sessions[id] else { continue }
            session.isUnderMemoryPressure = true
            let onScreen = Set(session.window.onScreen.map(\.index))
            for (index, var work) in session.pages where !onScreen.contains(index) {
                switch work.phase {
                case .inText:
                    cancel(work)
                    work = requeued(work, phase: .needsText)
                case let .inDrawing(translation):
                    cancel(work)
                    work = requeued(work, phase: .needsDrawing(translation, nil))
                case let .needsDrawing(translation, bitmap) where bitmap != nil:
                    work.phase = .needsDrawing(translation, nil)
                default:
                    continue
                }
                session.pages[index] = work
            }
            sessions[id] = session
        }
        pump()
    }

    // MARK: Setup and models

    /// Reads what to translate with. When that changed since the work under way was started,
    /// all of it is dropped and begun again: nothing made with one set of models is ever
    /// stored or shown under another. Returns whether it changed.
    @discardableResult
    private func refreshSetup() async -> Bool {
        if !hasPrepared {
            hasPrepared = true
            await environment.prepare()
        }
        let current = await environment.setup()
        guard current != setup else { return false }
        await adopt(current)
        return true
    }

    private func adopt(_ new: PageTranslationSetup?) async {
        for id in sessionOrder {
            for work in sessions[id]?.pages.values.map({ $0 }) ?? [] { cancel(work) }
            sessions[id]?.pages = [:]
            sessions[id]?.stored = []
        }
        unloadModels()
        setup = new
        if let new, !hasExpired {
            // The cache's limits, the first time the service has models to keep results for.
            hasExpired = true
            await environment.writer.removeExpired(keepingModelSetKey: new.modelSet.key, now: environment.now())
            await environment.patchStore.removeExpired(keeping: new.variant, now: environment.now())
        }
        for id in sessionOrder {
            await readStoredPages(of: id)
            for page in sessions[id]?.window.pages ?? [] where sessions[id]?.pages[page.index] == nil {
                add(page, to: id)
            }
        }
        pump()
    }

    /// One read for the whole gallery: which of its pages have stored text.
    private func readStoredPages(of id: UUID) async {
        guard let gid = sessions[id]?.gid, let setup else { return }
        let indices = (try? await environment.writer.translatedPageIndices(gid: gid, modelSetKey: setup.modelSet.key)) ?? []
        guard sessions[id] != nil, self.setup == setup else { return }
        sessions[id]?.stored.formUnion(indices)
        // Eviction keeps the galleries being read.
        if !indices.isEmpty { await environment.patchStore.markUsed(gid: gid, at: environment.now()) }
    }

    func unloadModels() {
        releasePipeline()
        dropInpainter()
    }

    private func dropInpainter() {
        if case let .loading(task) = inpainterState { task.cancel() }
        inpainterState = .unloaded
        modelToken += 1
    }

    /// The repaint model, loaded the first time a block on artwork needs it.
    func repaintModel(token: Int) async throws -> any Inpainter {
        guard token == modelToken, let setup, let url = setup.repaintModel else { throw CancellationError() }
        switch inpainterState {
        case let .ready(model):
            return model
        case let .loading(task):
            return try await task.value
        case .failed:
            throw PageTranslationFailure.modelsFailedToLoad
        case .unloaded:
            let interval = PerformanceSignposts.begin(.pageTranslateLoad, "repaint")
            let units = setup.repaintUnits
            let task = Task(priority: .utility) { [environment] in try await environment.loadInpainter(url, units) }
            inpainterState = .loading(task)
            do {
                let model = try await task.value
                if case .loading(task) = inpainterState { inpainterState = .ready(model) }
                interval.end("done")
                return model
            } catch {
                if case .loading(task) = inpainterState {
                    inpainterState = error is CancellationError ? .unloaded : .failed
                    environment.logger.error("The repaint model did not load: \(error)", category: Self.logCategory)
                }
                interval.end("failed")
                throw error
            }
        }
    }

    /// Whether nothing is in work: no page in either half, no model loading, no stored page
    /// being looked up. Tests wait for it.
    var isIdle: Bool {
        guard textSlot == nil, drawSlot == nil else { return false }
        if case .loading = pipelineState { return false }
        return !sessions.values.contains { session in
            session.pages.values.contains { work in
                if case .lookingUp = work.phase { return true }
                return false
            }
        }
    }

    static let logCategory = "PageTranslation"
    static let seconds = Duration.UnitsFormatStyle(allowedUnits: [.seconds], width: .abbreviated, fractionalPart: .show(length: 1))
}
