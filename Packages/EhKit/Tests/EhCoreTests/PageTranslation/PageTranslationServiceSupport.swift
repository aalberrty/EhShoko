import CoreGraphics
import CoreML
import EhDatabase
import EhModels
import EhPageTranslation
import EhTestSupport
import Foundation
import ImageIO
import Synchronization
import Testing
@testable import EhCore

// A world for the translation service without a model in it: stub stages that say what they
// did and can be held half-way, pages made by the tests, a temporary cache, and the phone's
// states as the test sets them.

/// Holds a stub stage inside its call for a page until the test lets it go.
final class StageGates: Sendable {
    private struct State {
        var held: Set<Int> = []
        var waiting: [Int: [CheckedContinuation<Void, Never>]] = [:]
    }

    private let state = Mutex(State())

    func hold(_ page: Int) {
        state.withLock { _ = $0.held.insert(page) }
    }

    func release(_ page: Int) {
        let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.held.remove(page)
            return state.waiting.removeValue(forKey: page) ?? []
        }
        waiting.forEach { $0.resume() }
    }

    /// Returns at once for a page that is not held.
    func pass(_ page: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isHeld = state.withLock { state -> Bool in
                guard state.held.contains(page) else { return false }
                state.waiting[page, default: []].append(continuation)
                return true
            }
            if !isHeld { continuation.resume() }
        }
    }
}

/// What the stubs did and what the tests set.
final class TranslationWorld: Sendable {
    struct State {
        var setup: PageTranslationSetup?
        var heat = PageTranslationHeat.nominal
        var isLowPower = false
        /// "text 5" when page 5's detector call begins, "draw 5" when its drawing does.
        var log: [String] = []
        var pipelineLoads: [PipelineConfiguration] = []
        var inpainterLoads = 0
        var prepares = 0
        var fetches: [Int: Int] = [:]
        var unavailablePages: Set<Int> = []
        var animatedPages: Set<Int> = []
        var unreadablePages: Set<Int> = []
        var pagesWithoutText: Set<Int> = []
        var failsToLoadModels = false
        var drawingAsksForTheRepaintModel = false
        /// A drawing stage that does not notice it was cancelled and hands patches back.
        var drawingIgnoresCancellation = false
        var failedRepaints = 0
        var inText = 0, inDrawing = 0
        var mostInText = 0, mostInDrawing = 0
        /// Whether both halves were ever busy at the same moment.
        var bothHalvesWereBusy = false
    }

    static let gid = "4242"
    /// One moment for the whole run: results are stamped with it and the cache's expiry is
    /// reckoned from it.
    static let now = Date()

    let state: Mutex<State>
    let textGates = StageGates()
    let drawGates = StageGates()
    let database: AppDatabase
    let writer: PageTranslationResultWriter
    let patchStore: PageTranslationPatchStore
    let directory: URL

    init(setup: PageTranslationSetup? = TranslationWorld.setup()) async throws {
        state = Mutex(State(setup: setup))
        database = try await TestDatabase.inMemory()
        // Batches are written by `flush()` only: the delay outlasts any test.
        writer = PageTranslationResultWriter(database: database, logger: .console(), delay: .seconds(3_600))
        directory = try TestDatabase.makeTemporaryDirectory()
        patchStore = PageTranslationPatchStore(directory: directory.appending(path: "Patches", directoryHint: .isDirectory))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Setups

    static let nowhere = URL(fileURLWithPath: "/nowhere", isDirectory: true)

    /// A setup whose files do not exist: the stub loader never opens them.
    static func setup(
        _ modelSet: PageTranslationModelSet = .default, repaint: RepaintChoice = .off, installed: Bool = true
    ) -> PageTranslationSetup {
        let pipeline = PipelineConfiguration(
            modelSet: modelSet, detector: nowhere.appending(path: modelSet.detector.key),
            reader: .cpt2(encoder: nowhere, decoder: nowhere, vocabulary: nowhere),
            translator: nowhere.appending(path: modelSet.translator.key)
        )
        return PageTranslationSetup(
            modelSet: modelSet, repaint: repaint, pipeline: installed ? pipeline : nil,
            repaintModel: repaint == .off ? nil : nowhere.appending(path: repaint.key),
            artifacts: Set(modelSet.artifacts + [repaint.artifact].compactMap { $0 })
        )
    }

    // MARK: Reading what happened

    var log: [String] { state.withLock { $0.log } }
    var pipelineLoads: [PipelineConfiguration] { state.withLock { $0.pipelineLoads } }

    func set(_ change: (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    func value<Value>(_ read: (State) -> Value) -> Value {
        state.withLock { read($0) }
    }

    func fetches(of page: Int) -> Int { state.withLock { $0.fetches[page] ?? 0 } }

    var variant: PageTranslationPatchVariant {
        state.withLock { $0.setup }?.variant
            ?? PageTranslationPatchVariant(modelSet: .default, repaint: .off, renderVersion: 1)
    }

    func patchFile(of page: Int, variant: PageTranslationPatchVariant? = nil) -> URL {
        patchStore.fileURL(gid: Self.gid, pageIndex: page, variant: variant ?? self.variant)
    }

    func hasPatchFile(of page: Int) -> Bool {
        FileManager.default.fileExists(atPath: patchFile(of: page).path)
    }

    /// The page's stored text, written or still waiting in the writer.
    func storedText(of page: Int, modelSet: PageTranslationModelSet = .default) async throws -> PageTranslation? {
        try await writer.translation(gid: Self.gid, pageIndex: page, modelSetKey: modelSet.key)
    }

    // MARK: Pages

    static func url(_ page: Int) -> URL {
        URL(string: "https://pages.example/\(page).png") ?? nowhere
    }

    static func page(_ index: Int) -> PageTranslationPage {
        PageTranslationPage(index: index, imageURL: url(index))
    }

    static func window(onScreen: [Int], ahead: [Int] = [], behind: [Int] = []) -> PageTranslationWindow {
        PageTranslationWindow(onScreen: onScreen.map(page), ahead: ahead.map(page), behind: behind.map(page))
    }

    /// Each page's bitmap is as wide as 40 plus its number, which is how the stub detector
    /// knows which page it was handed.
    static func width(of page: Int) -> Int { 40 + page }
    static let height = 64

    static func png(of page: Int) -> Data {
        encoded([paper(width: width(of: page))], as: "public.png")
    }

    /// An animated page: two frames.
    static let gif = encoded([paper(width: 40), paper(width: 40)], as: "com.compuserve.gif")

    private static func paper(width: Int) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.setFillColor(gray: 1, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }

    private static func encoded(_ frames: [CGImage?], as type: String) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, frames.count, nil) else { return Data() }
        for case let frame? in frames { CGImageDestinationAddImage(destination, frame, nil) }
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// A stored page as the first half leaves it: one line of dialogue and a sound effect.
    static func storedPage(_ page: Int, modelSet: PageTranslationModelSet = .default, translated: Bool = true) -> PageTranslation {
        var regions = [TranslatedRegion(
            box: FractionalRect(x: 0.5, y: 0.5, width: 0.2, height: 0.3), kind: .soundEffect, isVertical: true, score: 0.8
        )]
        if translated {
            regions.insert(TranslatedRegion(
                box: FractionalRect(x: 0.1, y: 0.1, width: 0.2, height: 0.4), kind: .dialogue, isVertical: true,
                score: 0.9, source: "こんにちは", translation: "你好"
            ), at: 0)
        }
        return PageTranslation(
            gid: gid, pageIndex: page, modelSetKey: modelSet.key, imageWidth: width(of: page), imageHeight: height,
            regions: regions, createdAt: now
        )
    }

    // MARK: The environment

    func environment() -> PageTranslationEnvironment {
        PageTranslationEnvironment(
            prepare: { [self] in set { $0.prepares += 1 } },
            setup: { [self] in value(\.setup) },
            imageData: { [self] url in
                let page = Int(url.deletingPathExtension().lastPathComponent) ?? -1
                let kind = state.withLock { state -> Int in
                    state.fetches[page, default: 0] += 1
                    if state.unavailablePages.contains(page) { return 1 }
                    if state.unreadablePages.contains(page) { return 2 }
                    return state.animatedPages.contains(page) ? 3 : 0
                }
                switch kind {
                case 1: throw URLError(.notConnectedToInternet)
                case 2: return Data("not an image".utf8)
                case 3: return Self.gif
                default: return Self.png(of: page)
                }
            },
            loadPipeline: { [self] configuration in
                let fails = state.withLock { state -> Bool in
                    state.pipelineLoads.append(configuration)
                    return state.failsToLoadModels
                }
                if fails { throw ModelSignatureError.noImageInput }
                return PagePipeline(
                    detector: WorldDetector(world: self), reader: WorldReader(world: self),
                    translator: WorldTranslator(world: self)
                )
            },
            loadInpainter: { [self] _, _ in
                set { $0.inpainterLoads += 1 }
                return WorldInpainter()
            },
            draw: { [self] translation, _, inpainter in try await draw(translation, inpainter: inpainter) },
            writer: writer, patchStore: patchStore,
            heat: { [self] in value(\.heat) },
            isLowPowerModeEnabled: { [self] in value(\.isLowPower) },
            now: { Self.now },
            logger: .console()
        )
    }

    func service() -> PageTranslationService {
        PageTranslationService(environment: environment())
    }

    // MARK: The stub stages

    func enterText() {
        state.withLock { state in
            state.inText += 1
            state.mostInText = max(state.mostInText, state.inText)
            if state.inDrawing > 0 { state.bothHalvesWereBusy = true }
        }
    }

    func leaveText() {
        state.withLock { $0.inText -= 1 }
    }

    private func draw(_ translation: PageTranslation, inpainter: (any Inpainter)?) async throws -> PageDrawing {
        let page = translation.pageIndex
        let (asksForRepaint, failedRepaints, ignoresCancellation) = state.withLock { state -> (Bool, Int, Bool) in
            state.log.append("draw \(page)")
            state.inDrawing += 1
            state.mostInDrawing = max(state.mostInDrawing, state.inDrawing)
            if state.inText > 0 { state.bothHalvesWereBusy = true }
            return (state.drawingAsksForTheRepaintModel, state.failedRepaints, state.drawingIgnoresCancellation)
        }
        defer { state.withLock { $0.inDrawing -= 1 } }
        await drawGates.pass(page)
        if !ignoresCancellation { try Task.checkCancellation() }
        if asksForRepaint, let inpainter {
            _ = try await inpainter.repaint(tile: [], mask: [])
        }
        let patch = Patch(rect: PixelRect(x: 2, y: 3, width: 4, height: 5), pixels: Data(repeating: 255, count: 80))
        return PageDrawing(
            patches: translation.regions.filter(\.isTranslated).map { _ in patch },
            repaintedBlocks: asksForRepaint ? 1 : 0, failedRepaints: failedRepaints
        )
    }
}

private struct WorldDetector: TextDetector {
    let world: TranslationWorld
    var choice: TextDetectorChoice { .k2xl }

    func detect(_ page: PageBitmap, in region: PixelRect) async throws -> DetectedText {
        let index = page.width - 40
        world.set { $0.log.append("text \(index)") }
        world.enterText()
        defer { world.leaveText() }
        // A model call cannot be interrupted: it returns when the gate lets it, cancelled or not.
        await world.textGates.pass(index)
        var blocks = [TextBlock(box: CGRect(x: 20, y: 30, width: 12, height: 20), kind: .soundEffect, isVertical: true, score: 0.8)]
        if !world.value({ $0.pagesWithoutText.contains(index) }) {
            blocks.insert(TextBlock(
                box: CGRect(x: 6, y: 6, width: 10, height: 30), kind: .dialogue, isVertical: true, score: 0.9,
                balloon: Balloon(box: CGRect(x: 2, y: 2, width: 18, height: 40))
            ), at: 0)
        }
        return DetectedText(blocks: blocks)
    }
}

private struct WorldReader: TextReader {
    let world: TranslationWorld
    var choice: TextReaderChoice { .cpt2 }

    func read(_ crop: CGImage) async throws -> String {
        world.enterText()
        defer { world.leaveText() }
        return "こんにちは"
    }
}

private struct WorldTranslator: PageTranslator {
    let world: TranslationWorld

    func translate(_ lines: [String]) async throws -> [String?] {
        world.enterText()
        defer { world.leaveText() }
        return lines.map { _ in "你好" }
    }
}

private struct WorldInpainter: Inpainter {
    func repaint(tile: [UInt8], mask: [UInt8]) async throws -> [UInt8] { tile }
}

// MARK: - Sessions and waiting

/// The events of one session, collected as they come.
final class SessionEvents: Sendable {
    private let events = Mutex<[PageTranslationEvent]>([])
    private let ended = Mutex(false)

    init() {}

    func collect(_ stream: AsyncStream<PageTranslationEvent>) {
        Task {
            for await event in stream { events.withLock { $0.append(event) } }
            ended.withLock { $0 = true }
        }
    }

    var all: [PageTranslationEvent] { events.withLock { $0 } }
    var hasEnded: Bool { ended.withLock { $0 } }

    func statuses(of page: Int) -> [PageTranslationStatus] {
        all.filter { $0.pageIndex == page }.map(\.status)
    }

    func status(of page: Int) -> PageTranslationStatus? { statuses(of: page).last }

    func report(of page: Int) -> PageTranslationReport? {
        all.last { $0.pageIndex == page && $0.report != nil }?.report
    }

    /// Whether the page's latest status is a patch file to show.
    func isTranslated(_ page: Int) -> Bool {
        if case .translated = status(of: page) { return true }
        return false
    }
}

struct OpenSession {
    let id = UUID()
    let events = SessionEvents()
}

extension PageTranslationService {
    /// Opens a session straight on the service, so each call is done when it returns.
    func open(gid: String = TranslationWorld.gid) async -> OpenSession {
        let session = OpenSession()
        let (stream, continuation) = AsyncStream.makeStream(of: PageTranslationEvent.self)
        session.events.collect(stream)
        await perform(.open(session.id, gid: gid, events: continuation))
        return session
    }

    func show(_ session: OpenSession, onScreen: [Int], ahead: [Int] = [], behind: [Int] = []) async {
        await perform(.window(session.id, TranslationWorld.window(onScreen: onScreen, ahead: ahead, behind: behind)))
    }
}

struct TimedOut: Error {}

/// Waits until `condition` holds; a busy machine gets a minute.
func eventually(
    _ what: String, sourceLocation: SourceLocation = #_sourceLocation, _ condition: @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + .seconds(60)
    while await !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting for \(what)", sourceLocation: sourceLocation)
            throw TimedOut()
        }
        try await Task.sleep(for: .milliseconds(2))
    }
}

/// Waits until the service has nothing in work and the session's events have caught up.
func settled(_ service: PageTranslationService, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    try await eventually("the service to be idle", sourceLocation: sourceLocation) { await service.isIdle }
    // The collector's task drains what was yielded before the service went idle.
    try await Task.sleep(for: .milliseconds(20))
}
