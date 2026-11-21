import EhModels
import EhPageTranslation
import Foundation

// What a reader sees of page translation: it opens a session for its gallery, says which
// pages it wants, and is told how each of them stands. Everything behind that (which models
// are loaded, what is in the cache, how many pages are in work) is the service's.

/// Page translation as the reader's model calls it, `\.pageTranslation`.
///
/// Nothing happens until a session is opened: no model is loaded and no file is read.
public struct PageTranslationClient: Sendable {
    /// Opens a session for one reader of the gallery `gid`. The reader keeps it for as long as
    /// it lives, also while Translate is switched off in it, and closes it when it goes away.
    public var openSession: @Sendable (_ gid: String) -> PageTranslationSession

    public init(openSession: @escaping @Sendable (_ gid: String) -> PageTranslationSession) {
        self.openSession = openSession
    }
}

/// One reader's use of page translation. Its calls return at once and take effect in the
/// order they were made.
public struct PageTranslationSession: Sendable {
    /// Every change of a wanted page's status, until the session is closed. A page with a
    /// stored translation is reported `.translated` before any model has loaded.
    public var events: AsyncStream<PageTranslationEvent>
    /// The pages wanted now, replacing those of the call before. A page that is no longer
    /// wanted is cancelled and writes nothing. `.empty` is Translate switched off: all work
    /// stops, what is waiting is written, and the models stay loaded.
    public var setWindow: @Sendable (PageTranslationWindow) -> Void
    /// Asks again for a wanted page: one that failed is tried again, and one that is
    /// translated is drawn again (its patch file could not be shown).
    public var retry: @Sendable (_ pageIndex: Int) -> Void
    /// The reader closed: cancels everything, writes what is waiting and, when no other
    /// session is open, lets every model go. `events` ends.
    public var close: @Sendable () -> Void

    public init(
        events: AsyncStream<PageTranslationEvent>,
        setWindow: @escaping @Sendable (PageTranslationWindow) -> Void,
        retry: @escaping @Sendable (_ pageIndex: Int) -> Void,
        close: @escaping @Sendable () -> Void
    ) {
        self.events = events
        self.setWindow = setWindow
        self.retry = retry
        self.close = close
    }
}

/// A page the reader wants translated: its number and where its image is.
public struct PageTranslationPage: Sendable, Hashable {
    /// Numbered as `GalleryPage.index` numbers it.
    public var index: Int
    /// The page's image as the reader shows it. The bytes come from the image cache, which
    /// has them once the page was shown or fetched ahead; a file URL is read from disk.
    public var imageURL: URL

    public init(index: Int, imageURL: URL) {
        self.index = index
        self.imageURL = imageURL
    }
}

/// The pages a reader wants, in the order they matter. A page whose image address is not
/// known yet is left out and sent with a later window.
///
/// The reader always sends what it would like; how much of `ahead` and `behind` is worked on
/// is the service's decision (`PageTranslationPolicy`: the translator, heat, Low Power Mode,
/// memory). A page with a stored translation is reported whatever the policy says.
public struct PageTranslationWindow: Sendable, Equatable {
    /// The pages on screen, nearest first: one, or two in a spread.
    public var onScreen: [PageTranslationPage]
    /// The next pages in reading order, nearest first.
    public var ahead: [PageTranslationPage]
    /// The page before.
    public var behind: [PageTranslationPage]

    public init(
        onScreen: [PageTranslationPage], ahead: [PageTranslationPage] = [], behind: [PageTranslationPage] = []
    ) {
        self.onScreen = onScreen
        self.ahead = ahead
        self.behind = behind
    }

    public static let empty = PageTranslationWindow(onScreen: [])

    /// Every page once, in order of priority.
    public var pages: [PageTranslationPage] {
        var seen = Set<Int>()
        return (onScreen + ahead + behind).filter { seen.insert($0.index).inserted }
    }

    public var isEmpty: Bool { onScreen.isEmpty && ahead.isEmpty && behind.isEmpty }
}

/// A wanted page's status changed.
public struct PageTranslationEvent: Sendable, Equatable {
    public var pageIndex: Int
    public var status: PageTranslationStatus
    /// What the page took, with the status that ends its work. For measuring; the reader's
    /// model ignores it.
    public var report: PageTranslationReport?

    public init(pageIndex: Int, status: PageTranslationStatus, report: PageTranslationReport? = nil) {
        self.pageIndex = pageIndex
        self.status = status
        self.report = report
    }
}

/// Where a wanted page stands. A page that is not wanted has no status.
public enum PageTranslationStatus: Sendable, Equatable {
    /// The page waits for the models, which are loading ("Getting translation ready…").
    case loadingModels
    /// Waiting for its turn or in work ("Translating page 23…").
    case translating
    /// Done: the patch file to lay over the page.
    case translated(PageTranslationOverlay)
    /// Done, and there is nothing to draw: no text was found, or only sound effects.
    case nothingToDraw
    /// An animated page, which is never translated.
    case skipped
    case failed(PageTranslationFailure)

    /// Whether the page's work has ended.
    public var isFinal: Bool {
        switch self {
        case .loadingModels, .translating: false
        case .translated, .nothingToDraw, .skipped, .failed: true
        }
    }
}

/// A page's translation, drawn: one file of patches to lay over the page's image.
public struct PageTranslationOverlay: Sendable, Hashable {
    /// `PatchFile.read(from:)` reads it.
    public var patchFile: URL
    /// Names the drawing: the models, the repaint choice and the drawing rules it was made
    /// with. Two overlays of a page with the same variant show the same picture.
    public var variant: String

    public init(patchFile: URL, variant: String) {
        self.patchFile = patchFile
        self.variant = variant
    }
}

/// Why a page was not translated. None of these is shown as an alert: the page stays
/// readable and the reader offers Retry.
public enum PageTranslationFailure: Error, Sendable, Equatable {
    /// One of the three kinds has no model this user can have, or a chosen model is not
    /// installed. The reader's model keeps Translate from being pressed in that state, so
    /// this is seen only when models were removed while a reader was open.
    case modelsMissing
    /// A model could not be loaded: a broken file, or no memory for it.
    case modelsFailedToLoad
    /// The page's image could not be fetched.
    case imageUnavailable
    /// The page's bytes are not an image.
    case imageUnreadable
    /// A model failed on this page.
    case pipelineFailed
    /// The result could not be written to the cache.
    case cacheUnwritable
}

/// What a page took, for the translation harness and the budgets.
public struct PageTranslationReport: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// The stored text and its patch file were both there: nothing was computed.
        case stored
        /// The stored text was drawn again; no detector, reader or translator ran.
        case redrawn
        /// Found, read, translated and drawn now.
        case translated
    }

    public var source: Source
    /// From the moment the page's work began to its end, waits between the halves included.
    public var total: Duration
    /// How long the page waited for the models to load.
    public var waitingForModels: Duration
    /// Fetching the page's bytes.
    public var fetching: Duration
    public var decoding: Duration
    /// Stages 1 to 4, for a page translated now.
    public var text: PageTextTimings?
    /// Stages 5 and 6, for a page that was drawn.
    public var drawing: PageDrawingTimings?
    /// Encoding and writing the patch file.
    public var writing: Duration
    public var patches: Int
    public var patchFileBytes: Int
    public var repaintedBlocks: Int
    public var failedRepaints: Int
    /// The working bitmap's size.
    public var imageWidth: Int
    public var imageHeight: Int

    public init(source: Source) {
        self.source = source
        total = .zero
        waitingForModels = .zero
        fetching = .zero
        decoding = .zero
        writing = .zero
        patches = 0
        patchFileBytes = 0
        repaintedBlocks = 0
        failedRepaints = 0
        imageWidth = 0
        imageHeight = 0
    }
}
