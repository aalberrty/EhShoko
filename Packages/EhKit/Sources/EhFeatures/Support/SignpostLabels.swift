import EhCore
import EhModels

// What the feature models write into `PerformanceSignposts` intervals: which list, and how a
// load ended. Never a keyword or a title.

nonisolated extension GalleryListSource {
    /// The kind of list, without its keyword or folder.
    var signpostName: String {
        switch self {
        case .frontpage: "frontpage"
        case .popular: "popular"
        case .watched: "watched"
        case .favorites: "favorites"
        case .toplists: "toplists"
        case .search: "search"
        }
    }
}

nonisolated extension Outcome {
    /// How a load ended: `describe` of its value ("24 galleries"), "failed" or "cancelled".
    func signpostOutcome(_ describe: (Value) -> String = { _ in "done" }) -> String {
        switch self {
        case .success(let value): describe(value)
        case .failure: "failed"
        case .cancelled: "cancelled"
        }
    }
}
