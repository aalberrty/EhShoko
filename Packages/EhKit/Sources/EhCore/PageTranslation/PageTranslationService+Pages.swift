import EhModels
import EhPageTranslation
import Foundation

// The queue: how a wanted page moves from the cache or the models to its patch file.

extension PageTranslationService {
    // MARK: Entering and leaving

    /// Starts work on a page that was just asked for.
    func add(_ page: PageTranslationPage, to id: UUID) {
        guard let session = sessions[id] else { return }
        generation += 1
        let key = PageKey(session: id, index: page.index)
        var work = PageWork(page: page, phase: .needsText, generation: generation)
        if session.skipped.contains(page.index) {
            sessions[id]?.pages[page.index] = work
            finish(key, .skipped)
        } else if let setup, session.stored.contains(page.index) {
            work.phase = .lookingUp
            work.began = clock.now
            work.interval = PerformanceSignposts.begin(.pageTranslate, "stored")
            let (gid, generation) = (session.gid, work.generation)
            // Not model work, and what a press of Translate waits for: ahead of the queue.
            work.task = Task(priority: .userInitiated) { [environment] in
                let outcome = await Self.lookUp(gid: gid, pageIndex: page.index, setup: setup, environment: environment)
                self.lookupEnded(key, generation, outcome)
            }
            sessions[id]?.pages[page.index] = work
        } else if setup == nil {
            sessions[id]?.pages[page.index] = work
            finish(key, .failed(.modelsMissing))
        } else {
            sessions[id]?.pages[page.index] = work
            emit(key, waitingStatus)
        }
    }

    /// Stops a page's work. Its half stays taken until the model call under way returns.
    func cancel(_ work: PageWork) {
        work.task?.cancel()
        work.interval?.end("cancelled")
    }

    /// A page whose work was stopped and which waits again, as new work.
    func requeued(_ work: PageWork, phase: Phase) -> PageWork {
        generation += 1
        var again = PageWork(page: work.page, phase: phase, generation: generation)
        again.status = work.status
        return again
    }

    /// The page's work, if it is still the work `generation` names.
    func current(_ key: PageKey, _ generation: Int) -> PageWork? {
        guard let work = sessions[key.session]?.pages[key.index], work.generation == generation else { return nil }
        return work
    }

    func store(_ work: PageWork, _ key: PageKey) {
        sessions[key.session]?.pages[key.index] = work
    }

    /// What a page that waits for stages 1 to 4 is reported as.
    var waitingStatus: PageTranslationStatus {
        switch pipelineState {
        case .ready, .failed: .translating
        case .unloaded, .loading: setup?.pipeline == nil ? .translating : .loadingModels
        }
    }

    func emit(_ key: PageKey, _ status: PageTranslationStatus, report: PageTranslationReport? = nil) {
        guard var work = sessions[key.session]?.pages[key.index], work.status != status else { return }
        work.status = status
        store(work, key)
        sessions[key.session]?.events.yield(PageTranslationEvent(pageIndex: key.index, status: status, report: report))
    }

    /// Ends a page's work with `status`.
    func finish(_ key: PageKey, _ status: PageTranslationStatus) {
        guard var work = sessions[key.session]?.pages[key.index] else { return }
        work.phase = .finished
        work.task = nil
        if let began = work.began { work.report.total = clock.now - began }
        work.interval?.end(Self.outcome(status))
        work.interval = nil
        store(work, key)
        emit(key, status, report: work.report)
    }

    func fail(_ key: PageKey, _ failure: PageTranslationFailure, detail: String) {
        // A broken model fails every page alike: a few lines say so, not one a page.
        if loggedFailures < 5 {
            loggedFailures += 1
            environment.logger.error("A page was not translated (\(failure)): \(detail)", category: Self.logCategory)
        }
        finish(key, .failed(failure))
    }

    private static func outcome(_ status: PageTranslationStatus) -> String {
        switch status {
        case .loadingModels, .translating: "working"
        case .translated: "done"
        case .nothingToDraw: "nothing to draw"
        case .skipped: "skipped"
        case .failed: "failed"
        }
    }

    // MARK: The cache

    private func lookupEnded(_ key: PageKey, _ generation: Int, _ outcome: LookupOutcome) {
        guard var work = current(key, generation), case .lookingUp = work.phase, let setup else { return }
        work.task = nil
        work.report.source = .stored
        switch outcome {
        case .missing:
            // Expired or cleared since the gallery's pages were listed: translated as new.
            sessions[key.session]?.stored.remove(key.index)
            work.interval?.end("missing")
            work.interval = nil
            work.began = nil
            work.report.source = .translated
            work.phase = .needsText
            store(work, key)
            emit(key, waitingStatus)
        case .nothingToDraw:
            store(work, key)
            finish(key, .nothingToDraw)
        case let .drawn(url):
            store(work, key)
            finish(key, .translated(PageTranslationOverlay(patchFile: url, variant: setup.variant.folderName)))
        case let .text(translation):
            work.report.source = .redrawn
            work.phase = .needsDrawing(translation, nil)
            store(work, key)
            emit(key, .translating)
        }
        pump()
    }

    // MARK: The queue

    /// The pages that may be worked on now, in the order they are served: session by session,
    /// each session's window as far as the policy lets it go.
    private func workable(_ setup: PageTranslationSetup) -> [PageKey] {
        let heat = environment.heat(), isLowPower = environment.isLowPowerModeEnabled()
        var keys: [PageKey] = []
        for id in sessionOrder {
            guard let session = sessions[id] else { continue }
            let policy = PageTranslationPolicy.current(
                translator: setup.modelSet.translator, heat: heat, isLowPowerModeEnabled: isLowPower,
                isUnderMemoryPressure: session.isUnderMemoryPressure
            )
            keys += policy.pages(of: session.window).map { PageKey(session: id, index: $0.index) }
        }
        return keys
    }

    /// Gives each free half its next page. Called whenever something changed: a window, a
    /// half that ended, the models.
    func pump() {
        guard let setup else { return }
        let queue = workable(setup)
        let queued = Set(queue)
        // A page that is held back gives up the bitmap it kept for drawing: nothing may keep
        // the first half waiting for a page that is not drawn next.
        for id in sessionOrder {
            for (index, var work) in sessions[id]?.pages ?? [:] where !queued.contains(PageKey(session: id, index: index)) {
                guard case let .needsDrawing(translation, bitmap) = work.phase, bitmap != nil else { continue }
                work.phase = .needsDrawing(translation, nil)
                sessions[id]?.pages[index] = work
            }
        }
        startDrawing(queue, setup)
        startText(queue, setup)
    }

    private func startDrawing(_ queue: [PageKey], _ setup: PageTranslationSetup) {
        guard drawSlot == nil else { return }
        for key in queue {
            guard var work = sessions[key.session]?.pages[key.index],
                  case let .needsDrawing(translation, bitmap) = work.phase
            else { continue }
            work.phase = .inDrawing(translation)
            if work.began == nil { work.began = clock.now }
            if work.interval == nil { work.interval = PerformanceSignposts.begin(.pageTranslate, "redraw") }
            let (page, generation, token) = (work.page, work.generation, modelToken)
            // Only a page with text on artwork asks for the repaint model, and only then is
            // it loaded.
            let inpainter: (any Inpainter)? = setup.repaintModel == nil
                ? nil : LazyInpainter { try await self.repaintModel(token: token) }
            let task = Task(priority: .utility) { [environment] in
                let outcome = await Self.draw(
                    page, translation: translation, bitmap: bitmap, inpainter: inpainter, environment: environment
                )
                await self.drawEnded(key, generation, outcome)
            }
            work.task = task
            store(work, key)
            drawSlot = Slot(key: key, generation: generation, task: task)
            return
        }
    }

    private func startText(_ queue: [PageKey], _ setup: PageTranslationSetup) {
        guard textSlot == nil, !isAPageWaitingWithItsBitmap else { return }
        let waiting = queue.first { key in
            if case .needsText = sessions[key.session]?.pages[key.index]?.phase { return true }
            return false
        }
        guard let key = waiting, var work = sessions[key.session]?.pages[key.index] else { return }
        guard let configuration = setup.pipeline else {
            failPagesWaitingForText(.modelsMissing)
            return
        }
        switch pipelineState {
        case .unloaded:
            startLoadingPipeline(configuration)
            markPagesWaitingForModels()
        case .loading:
            markPagesWaitingForModels()
        case .failed:
            failPagesWaitingForText(.modelsFailedToLoad)
        case let .ready(pipeline):
            work.phase = .inText
            let now = clock.now
            work.began = now
            if let since = work.waitingForModelsSince { work.report.waitingForModels = now - since }
            let interval = PerformanceSignposts.begin(.pageTranslate, "new")
            work.interval = interval
            let (page, generation) = (work.page, work.generation)
            let task = Task(priority: .utility) { [environment] in
                let outcome = await Self.text(page, pipeline: pipeline, environment: environment, interval: interval)
                await self.textEnded(key, generation, outcome)
            }
            work.task = task
            store(work, key)
            textSlot = Slot(key: key, generation: generation, task: task)
            emit(key, .translating)
        }
    }

    /// Whether a page whose text was just made waits for the second half with its bitmap.
    private var isAPageWaitingWithItsBitmap: Bool {
        sessions.values.contains { session in
            session.pages.values.contains { work in
                if case let .needsDrawing(_, bitmap) = work.phase { return bitmap != nil }
                return false
            }
        }
    }

    func pagesWaitingForText() -> [PageKey] {
        sessionOrder.flatMap { id in
            (sessions[id]?.pages ?? [:]).compactMap { index, work -> PageKey? in
                if case .needsText = work.phase { return PageKey(session: id, index: index) }
                return nil
            }
        }
    }

    private func markPagesWaitingForModels() {
        let now = clock.now
        for key in pagesWaitingForText() {
            guard var work = sessions[key.session]?.pages[key.index] else { continue }
            if work.waitingForModelsSince == nil {
                work.waitingForModelsSince = now
                store(work, key)
            }
            emit(key, .loadingModels)
        }
    }

    private func failPagesWaitingForText(_ failure: PageTranslationFailure) {
        for key in pagesWaitingForText() { finish(key, .failed(failure)) }
    }

    // MARK: The two halves ending

    private func textEnded(_ key: PageKey, _ generation: Int, _ outcome: TextOutcome) async {
        if textSlot?.generation == generation { textSlot = nil }
        await applyText(key, generation, outcome)
        pump()
    }

    private func applyText(_ key: PageKey, _ generation: Int, _ outcome: TextOutcome) async {
        guard var work = current(key, generation), case .inText = work.phase, let setup else { return }
        work.task = nil
        switch outcome {
        case .ended(.cancelled):
            // Its task was stopped while the page stayed wanted: it waits again.
            store(requeued(work, phase: .needsText), key)
        case .ended(.skipped):
            sessions[key.session]?.skipped.insert(key.index)
            store(work, key)
            finish(key, .skipped)
        case let .ended(.failed(failure, detail)):
            store(work, key)
            fail(key, failure, detail: detail)
        case let .text(image, text):
            guard let gid = sessions[key.session]?.gid else { return }
            let translation = text.translation(
                gid: gid, pageIndex: key.index, modelSetKey: setup.modelSet.key, createdAt: environment.now()
            )
            work.report.fetching = image.fetching
            work.report.decoding = image.decoding
            work.report.text = text.timings
            work.report.imageWidth = image.bitmap.width
            work.report.imageHeight = image.bitmap.height
            work.interval?.event("Text")
            // The page's first half ended uncancelled: its text is kept from here on, whatever
            // happens to its drawing.
            let hasText = translation.hasTranslatedText
            work.phase = hasText ? .needsDrawing(translation, image.bitmap) : .finished
            store(work, key)
            sessions[key.session]?.stored.insert(key.index)
            await environment.writer.add(translation)
            if !hasText, current(key, generation) != nil { finish(key, .nothingToDraw) }
        }
    }

    private func drawEnded(_ key: PageKey, _ generation: Int, _ outcome: DrawOutcome) async {
        await applyDrawing(key, generation, outcome)
        // The half stays taken until the patch file is written.
        if drawSlot?.generation == generation { drawSlot = nil }
        pump()
    }

    private func applyDrawing(_ key: PageKey, _ generation: Int, _ outcome: DrawOutcome) async {
        guard var work = current(key, generation), case let .inDrawing(translation) = work.phase, let setup,
              let gid = sessions[key.session]?.gid
        else { return }
        work.task = nil
        switch outcome {
        case .ended(.cancelled):
            store(requeued(work, phase: .needsDrawing(translation, nil)), key)
        case .ended(.skipped):
            sessions[key.session]?.skipped.insert(key.index)
            store(work, key)
            finish(key, .skipped)
        case let .ended(.failed(failure, detail)):
            store(work, key)
            fail(key, failure, detail: detail)
        case let .drawn(drawing, image):
            if work.report.source != .translated {
                work.report.fetching = image.fetching
                work.report.decoding = image.decoding
                work.report.imageWidth = image.bitmap.width
                work.report.imageHeight = image.bitmap.height
            }
            work.report.drawing = drawing.timings
            work.report.patches = drawing.patches.count
            work.report.repaintedBlocks = drawing.repaintedBlocks
            work.report.failedRepaints = drawing.failedRepaints
            work.interval?.event("Drawn")
            // Past cancelling: the file is written whole, also if the page stops being wanted
            // meanwhile. Until here a cancelled drawing has written nothing.
            work.phase = .writing
            store(work, key)
            let variant = drawing.failedRepaints > 0 ? setup.filledVariant : setup.variant
            let written = await writePatchFile(drawing.patches, of: image.bitmap, gid: gid, pageIndex: key.index, variant: variant)
            guard var done = current(key, generation) else { return }
            guard let written else {
                fail(key, .cacheUnwritable, detail: "the patch file could not be written")
                return
            }
            done.report.writing = written.took
            done.report.patchFileBytes = written.bytes
            store(done, key)
            finish(
                key, drawing.patches.isEmpty
                    ? .nothingToDraw
                    : .translated(PageTranslationOverlay(patchFile: written.url, variant: variant.folderName))
            )
        }
    }

    private struct WrittenPatchFile {
        var url: URL
        var bytes: Int
        var took: Duration
    }

    /// Writes a page's patches where the patch store keeps them; `nil` when that failed.
    private func writePatchFile(
        _ patches: [Patch], of bitmap: PageBitmap, gid: String, pageIndex: Int, variant: PageTranslationPatchVariant
    ) async -> WrittenPatchFile? {
        let start = clock.now
        do {
            let url = try await environment.patchStore.prepareToWrite(gid: gid, pageIndex: pageIndex, variant: variant)
            let bytes = try await PatchFile.write(
                patches, imageWidth: bitmap.width, imageHeight: bitmap.height, colorSpace: bitmap.colorSpace, to: url
            )
            await environment.patchStore.didWrite(url)
            return WrittenPatchFile(url: url, bytes: bytes, took: clock.now - start)
        } catch {
            if loggedFailures < 5 {
                loggedFailures += 1
                environment.logger.error("A page's patch file was not written: \(error)", category: Self.logCategory)
            }
            return nil
        }
    }
}
