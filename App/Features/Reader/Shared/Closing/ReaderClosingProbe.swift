import Dependencies
import EhCore
import QuartzCore

/// Proves that the closing page makes nothing and requests nothing before the reader reaches
/// it, and times its making. In debug and harness builds it counts, for the whole process, the
/// pages the engines asked for and the detail models the pages made (each of which sends the
/// one detail request), and writes a log line (category Reader) when the engine asks for a
/// page, when its column is first laid out, and when it makes its own detail model. Once per
/// reader each; elsewhere it does nothing.
enum ReaderClosingProbe {
    #if DEBUG || HARNESS
    /// Closing pages the engines asked for since launch.
    private(set) static var pagesMade = 0
    /// Detail models the closing pages made since launch.
    private(set) static var detailModelsMade = 0
    private static var askedAt: Double?
    /// The last page that said it shows the presenter's model, so that it says so once.
    private static var presenterModelPage = 0
    #endif

    static func asked() {
        #if DEBUG || HARNESS
        pagesMade += 1
        askedAt = CACurrentMediaTime()
        record("asked for by the engine (page \(pagesMade) since launch)")
        #endif
    }

    static func laidOut(height: CGFloat) {
        #if DEBUG || HARNESS
        guard let askedAt else { return }
        self.askedAt = nil
        let milliseconds = (CACurrentMediaTime() - askedAt) * 1_000
        let tall = Int(height.rounded())
        record("column laid out \(tall) pt tall, \(Int(milliseconds.rounded())) ms after it was asked for")
        #endif
    }

    static func detailMade() {
        #if DEBUG || HARNESS
        detailModelsMade += 1
        record("own detail model made, loading (model \(detailModelsMade) since launch)")
        #endif
    }

    static func presenterModelShown() {
        #if DEBUG || HARNESS
        guard presenterModelPage != pagesMade else { return }
        presenterModelPage = pagesMade
        record("shown with the presenting gallery page's model, nothing made")
        #endif
    }

    private static func record(_ event: String) {
        #if DEBUG || HARNESS
        @Dependency(\.appLogger) var logger
        logger.info("Closing page: \(event)", category: "Reader")
        #endif
    }
}
