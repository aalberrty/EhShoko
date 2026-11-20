import EhFeatures
import EhModels
import Foundation
import Testing

/// The closing page's rating line and how its stars take touches, in each state of the
/// gallery page's model.
@MainActor
@Suite struct ReaderClosingRatingStateTests {
    private let detail = GalleryDetail(
        gid: "1", title: "Title", isFavorited: false, visibility: .yes, rating: 4.72, userRating: 0,
        ratingCount: 100, category: .manga, language: .japanese, uploader: "someone", postedDate: .now,
        coverURL: nil, favoritedCount: 1, pageCount: 24, sizeCount: 1, sizeType: "MiB", torrentCount: 0
    )

    @Test func withoutAGalleryModelItIsAPlaceholderWhoseStarsTakeNoTouch() {
        let state = ReaderClosingRatingState(detail: nil)
        #expect(state == .placeholder)
        #expect(state.starsMode == .inactive)
    }

    @Test func signedInBeforeThePageIsHereItIsAPlaceholder() {
        let state = ReaderClosingRatingState(isLoggedIn: true, detail: nil, loadFailed: false, userRating: 0)
        #expect(state == .placeholder)
        #expect(state.starsMode == .inactive)
    }

    @Test func aFailedLoadWithNothingKnownOffersARetryEvenSignedOut() {
        for isLoggedIn in [true, false] {
            let state = ReaderClosingRatingState(isLoggedIn: isLoggedIn, detail: nil, loadFailed: true, userRating: 0)
            #expect(state == .failed)
            #expect(state.starsMode == .inactive)
        }
    }

    @Test func aFailedReloadKeepsTheNumbersOfTheStoredPage() {
        let state = ReaderClosingRatingState(isLoggedIn: true, detail: detail, loadFailed: true, userRating: 0)
        #expect(state == .unrated(average: 4.72, count: 100))
    }

    @Test func signedOutTheStarsAskToSignInWhateverIsKnown() {
        for known in [nil, detail] {
            let state = ReaderClosingRatingState(isLoggedIn: false, detail: known, loadFailed: false, userRating: 6)
            #expect(state == .signedOut)
            #expect(state.starsMode == .signsIn)
        }
    }

    @Test func signedInTheLineSaysWhetherTheUserHasRated() {
        let unrated = ReaderClosingRatingState(isLoggedIn: true, detail: detail, loadFailed: false, userRating: 0)
        #expect(unrated == .unrated(average: 4.72, count: 100))
        #expect(unrated.starsMode == .rates)
        let rated = ReaderClosingRatingState(isLoggedIn: true, detail: detail, loadFailed: false, userRating: 7)
        #expect(rated == .rated(average: 4.72, count: 100))
        #expect(rated.starsMode == .rates)
    }
}
