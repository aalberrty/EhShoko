import EhModels
import EhPageTranslation
import Foundation

// The work itself, off the service's actor: each step takes what it needs as values, does
// its work and hands an outcome back. None of them writes anything.

extension PageTranslationService {
    enum LookupOutcome: Sendable {
        /// No stored text after all.
        case missing
        /// Stored, with nothing to draw.
        case nothingToDraw
        /// Stored and drawn: the patch file is there.
        case drawn(URL)
        /// Stored, and its patch file is gone or was never made.
        case text(PageTranslation)
    }

    /// A page's bitmap with what getting it took.
    struct DecodedPage: Sendable {
        var bitmap: PageBitmap
        var fetching: Duration = .zero
        var decoding: Duration = .zero
    }

    /// Why a step ended without its result.
    enum StepEnd: Sendable {
        case skipped
        case cancelled
        case failed(PageTranslationFailure, detail: String)

        /// What an error thrown by a stage means for the page.
        init(_ error: any Error, as failure: PageTranslationFailure) {
            self = Task.isCancelled || error is CancellationError ? .cancelled : .failed(failure, detail: "\(error)")
        }
    }

    enum DecodeOutcome: Sendable {
        case page(DecodedPage)
        case ended(StepEnd)
    }

    enum TextOutcome: Sendable {
        case text(DecodedPage, PageText)
        case ended(StepEnd)
    }

    enum DrawOutcome: Sendable {
        case drawn(PageDrawing, DecodedPage)
        case ended(StepEnd)
    }

    /// One read of the page's stored text (through the writer, which also has results not yet
    /// written) and one look for its patch file. No model, no decoding.
    static func lookUp(
        gid: String, pageIndex: Int, setup: PageTranslationSetup, environment: PageTranslationEnvironment
    ) async -> LookupOutcome {
        let stored = try? await environment.writer.translation(
            gid: gid, pageIndex: pageIndex, modelSetKey: setup.modelSet.key
        )
        guard let translation = stored else { return .missing }
        guard translation.hasTranslatedText else { return .nothingToDraw }
        let url = environment.patchStore.fileURL(gid: gid, pageIndex: pageIndex, variant: setup.variant)
        // A file that turns out unreadable is the reader's to report (`retry`): reading and
        // decoding it here, only to check, would cost what showing it costs.
        return FileManager.default.fileExists(atPath: url.path) ? .drawn(url) : .text(translation)
    }

    /// Stage 0 and stages 1 to 4.
    static func text(
        _ page: PageTranslationPage, pipeline: PagePipeline, environment: PageTranslationEnvironment,
        interval: PerformanceInterval
    ) async -> TextOutcome {
        let decoded = await decodedPage(page, environment: environment)
        guard case let .page(image) = decoded else {
            if case let .ended(end) = decoded { return .ended(end) }
            return .ended(.cancelled)
        }
        let text: PageText
        do {
            text = try await pipeline.text(of: image.bitmap) { stage in
                switch stage {
                case let .found(blocks): interval.event("Found \(blocks)")
                case let .read(blocks): interval.event("Read \(blocks)")
                case let .translated(blocks): interval.event("Translated \(blocks)")
                }
            }
        } catch {
            return .ended(StepEnd(error, as: .pipelineFailed))
        }
        return Task.isCancelled ? .ended(.cancelled) : .text(image, text)
    }

    /// Stages 5 and 6, and stage 0 first for a stored page, which comes without its bitmap.
    static func draw(
        _ page: PageTranslationPage, translation: PageTranslation, bitmap: PageBitmap?, inpainter: (any Inpainter)?,
        environment: PageTranslationEnvironment
    ) async -> DrawOutcome {
        let image: DecodedPage
        if let bitmap {
            image = DecodedPage(bitmap: bitmap)
        } else {
            let decoded = await decodedPage(page, environment: environment)
            guard case let .page(fetched) = decoded else {
                if case let .ended(end) = decoded { return .ended(end) }
                return .ended(.cancelled)
            }
            image = fetched
        }
        let drawing: PageDrawing
        do {
            drawing = try await environment.draw(translation, image.bitmap, inpainter)
        } catch {
            return .ended(StepEnd(error, as: .pipelineFailed))
        }
        return Task.isCancelled ? .ended(.cancelled) : .drawn(drawing, image)
    }

    /// Fetches a page's bytes and decodes them: an animated page is skipped, bytes that are
    /// not an image fail.
    private static func decodedPage(
        _ page: PageTranslationPage, environment: PageTranslationEnvironment
    ) async -> DecodeOutcome {
        if Task.isCancelled { return .ended(.cancelled) }
        let clock = ContinuousClock()
        let fetchStart = clock.now
        let data: Data
        do {
            data = try await environment.imageData(page.imageURL)
        } catch {
            return .ended(StepEnd(error, as: .imageUnavailable))
        }
        let fetching = clock.now - fetchStart
        if Task.isCancelled { return .ended(.cancelled) }
        let decodeStart = clock.now
        let bitmap: PageBitmap
        do {
            bitmap = try await environment.decode(data)
        } catch {
            if let error = error as? PageBitmapError, error == .animated { return .ended(.skipped) }
            return .ended(StepEnd(error, as: .imageUnreadable))
        }
        return .page(DecodedPage(bitmap: bitmap, fetching: fetching, decoding: clock.now - decodeStart))
    }
}

/// The repaint model, asked for at the first tile: a page without text on artwork never
/// loads it.
struct LazyInpainter: Inpainter {
    let model: @Sendable () async throws -> any Inpainter

    init(_ model: @escaping @Sendable () async throws -> any Inpainter) {
        self.model = model
    }

    func repaint(tile: [UInt8], mask: [UInt8]) async throws -> [UInt8] {
        try await model().repaint(tile: tile, mask: mask)
    }
}
