/// The tabs of the `tabs` bar. The `command` bar has no tabs; it uses the `home` stack alone.
nonisolated public enum AppTab: Hashable, Sendable, CaseIterable {
    case home
    case watched
    case top
    case library
    case search
}
