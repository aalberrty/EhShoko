#if DEBUG || HARNESS
import Dependencies
import EhCore
import EhDatabase
import EhFeatures
import EhModels
import EhNetworking
import Foundation
import Synchronization
import UIKit

/// The closing page as the reader harness shows it in the engine's slot: a made-up gallery,
/// presented by nobody, so the page makes a detail model of its own when it first appears, as
/// it does for a reader opened from Continue or a list. That model runs on stand-in
/// dependencies: an empty database of its own, no cookies, and a transport that counts the
/// requests and answers each with "not connected" after a moment, so nothing reaches the site
/// and the page ends in its "Couldn't load · Retry" state.
///
/// `log` receives one line when the page is made, one when its detail model is made, and one
/// per request, which is how a check counts them.
enum ReaderClosingHarness {
    static func makeController(pageCount: Int, log: @escaping @Sendable (String) -> Void) -> UIViewController {
        log("closing page made (\(ReaderClosingProbe.pagesMade + 1) since launch)")
        let gallery = madeUpGallery(pageCount: pageCount)
        return ReaderClosingPage.makeController(gallery: gallery, pageCount: pageCount) { gallery in
            log("closing page: detail model made (\(ReaderClosingProbe.detailModelsMade + 1) since launch)")
            let requests = ReaderClosingHarnessRequests()
            return withDependencies {
                $0.ehClient = EhClient(
                    transport: ReaderClosingHarnessTransport { url in
                        log("closing page: detail request \(requests.next()) of this model, \(url)")
                    },
                    cookies: CookieStore(storage: HTTPCookieStorage()),
                    host: { .ehentai }
                )
                $0.database = inMemoryDatabase()
            } operation: {
                GalleryDetailModel(gallery: gallery)
            }
        }
    }

    /// A title in the site's convention, so the page shows a credit and "More by".
    private static func madeUpGallery(pageCount: Int) -> Gallery {
        Gallery(
            gid: "1", token: "harness",
            title: "(C105) [Harness Circle (Mizu Artist)] The Closing Page of a Made-up Gallery [English]",
            rating: 4.5, tags: [], category: .doujinshi, uploader: "harness", pageCount: pageCount,
            postedDate: Date(timeIntervalSince1970: 1_760_000_000), coverURL: nil,
            galleryURL: URL(string: "https://e-hentai.org/g/1/harness/")
        )
    }

    private static func inMemoryDatabase() -> AppDatabase {
        do {
            return try AppDatabase.makeInMemory()
        } catch {
            fatalError("The harness could not create an in-memory database: \(error)")
        }
    }
}

/// Numbers the requests of one detail model.
nonisolated private final class ReaderClosingHarnessRequests: Sendable {
    private let count = Mutex(0)

    func next() -> Int {
        count.withLock { value in
            value += 1
            return value
        }
    }
}

/// Answers every request with "not connected" after 0.4 s, having told `onRequest`.
nonisolated private struct ReaderClosingHarnessTransport: HTTPTransport {
    let onRequest: @Sendable (String) -> Void

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        onRequest(request.url?.absoluteString ?? "no URL")
        try await Task.sleep(for: .milliseconds(400))
        throw URLError(.notConnectedToInternet)
    }
}
#endif
