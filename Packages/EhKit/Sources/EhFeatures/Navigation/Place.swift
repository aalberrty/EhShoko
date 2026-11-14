import EhModels

/// Where browsing can be: the first screen, or one list (`Design/designs/README.md`
/// section 5.1). The command bar's place menu lists places.
///
/// Under Wall's first screen, whose root is itself a list, `start` is Front Page:
/// `AppRouter.go(to:start:)` stores `.list(.frontpage)` as `.start` there, so one value means
/// one place.
nonisolated public enum Place: Hashable, Sendable {
    case start
    case list(GalleryListKind)
}
