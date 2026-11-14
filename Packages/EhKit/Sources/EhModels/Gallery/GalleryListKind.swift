/// The gallery lists that are places of their own: each can be pushed as a screen, chosen in
/// the command bar's place menu, and remembered as Ledger's last place.
///
/// Stored by its raw value (`Setting.lastPlace`), so the raw values must not change.
public enum GalleryListKind: String, Codable, Sendable, Hashable, CaseIterable {
    case frontpage
    case popular
    case watched
    case toplists
    case history
    /// The favourites: the library part, not a plain list.
    case favorites
}
