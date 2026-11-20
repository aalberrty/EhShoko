import EhModels

/// What the closing page's rating shows (`closing-page.md`, item 4, and its states), from the
/// gallery page's model: which line stands under the stars, and how the stars take touches.
public nonisolated enum ReaderClosingRatingState: Equatable, Sendable {
    /// The detail is not known yet.
    case placeholder
    case signedOut
    /// Nothing is known and the load failed: "Couldn't load · Try again".
    case failed
    case rated(average: Float, count: Int)
    case unrated(average: Float, count: Int)

    /// How the stars take touches in this state.
    public enum StarsMode: Equatable, Sendable {
        /// A tap or a sideways drag rates.
        case rates
        /// Dimmed; a tap asks the user to sign in.
        case signsIn
        /// Dimmed, and touches pass through.
        case inactive
    }

    /// The state of `model`; a placeholder while the closing page has no gallery model.
    @MainActor
    public init(detail model: GalleryDetailModel?) {
        guard let model else {
            self = .placeholder
            return
        }
        self.init(
            isLoggedIn: model.isLoggedIn, detail: model.detail, loadFailed: model.loadingState.failed != nil,
            userRating: model.userRating
        )
    }

    /// A failed load counts only while nothing is known; a stored page keeps its numbers.
    /// Signed out, the line asks to sign in whatever is known.
    public init(isLoggedIn: Bool, detail: GalleryDetail?, loadFailed: Bool, userRating: Int) {
        if detail == nil, loadFailed {
            self = .failed
        } else if !isLoggedIn {
            self = .signedOut
        } else if let detail {
            self = userRating > 0
                ? .rated(average: detail.rating, count: detail.ratingCount)
                : .unrated(average: detail.rating, count: detail.ratingCount)
        } else {
            self = .placeholder
        }
    }

    public var starsMode: StarsMode {
        switch self {
        case .rated, .unrated: .rates
        case .signedOut: .signsIn
        case .placeholder, .failed: .inactive
        }
    }
}
