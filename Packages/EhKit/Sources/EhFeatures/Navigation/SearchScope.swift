/// What a search covers. The search surface starts on the scope of where it was entered from,
/// and results for the narrower two are pushed as `Route.listSearch`.
nonisolated public enum SearchScope: String, Hashable, Sendable, CaseIterable {
    case everywhere
    case favorites
    case watched
}
