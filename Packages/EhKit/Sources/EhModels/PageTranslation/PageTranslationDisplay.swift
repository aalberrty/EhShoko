import Foundation

/// What the reader shows for a page that has a translation. One value for the whole reader,
/// sent to the engine as a command; switching it never reloads or decodes a page.
public enum PageTranslationDisplay: Sendable, Hashable {
    /// The page as the site sent it. Translation keeps running, so switching back is instant.
    case original
    /// The translation over the page.
    case translated
    /// The translation cut at a line the finger drags (the wipe). `fraction` is the line's
    /// position across the page, 0 at its left edge and 1 at its right.
    case compare(fraction: Double)

    /// `compare` with its fraction clamped to 0...1; a non-finite fraction becomes 0.5.
    public static func comparing(at fraction: Double) -> Self {
        .compare(fraction: fraction.isFinite ? min(max(fraction, 0), 1) : 0.5)
    }

    /// Whether any part of the translation is visible.
    public var showsTranslation: Bool {
        switch self {
        case .original: false
        case .translated, .compare: true
        }
    }
}
