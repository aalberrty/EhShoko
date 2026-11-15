import EhFeatures
import SwiftUI
import UIKit

/// What the presenter gives the closing page (`Design/designs/closing-page.md`, "Where its
/// data comes from"): its gallery page's model when a gallery page presented the reader, and
/// the way out through the presenter. `readerCover` makes one per presented reader.
///
/// The closing page lives inside the reading engine, which is UIKit, so SwiftUI's environment
/// does not reach it. The context travels as a trait instead, as the page style does
/// (`ReaderPageStyle`): `readerCover` puts it in the environment, SwiftUI hands it to the
/// engine's views as a trait, and the closing page's hosting controller reads it back. It is
/// compared by identity, so it changes only when another reader is presented.
nonisolated final class ReaderClosingContext: Equatable, Sendable {
    /// The presenting gallery page's model; `nil` when a list or the shell presented the reader.
    let detail: GalleryDetailModel?
    private let exit: @MainActor (ReaderExit) -> Void

    init(detail: GalleryDetailModel?, exit: @escaping @MainActor (ReaderExit) -> Void) {
        self.detail = detail
        self.exit = exit
    }

    /// Closes the reader; the presenter then goes to `destination`.
    @MainActor
    func leave(to destination: ReaderExit) {
        exit(destination)
    }

    static func == (lhs: ReaderClosingContext, rhs: ReaderClosingContext) -> Bool {
        lhs === rhs
    }
}

extension View {
    /// Hands the closing page of the reader below its context. `readerCover` applies it to the
    /// reader it presents.
    func readerClosingContext(detail: GalleryDetailModel?, exit: @escaping @MainActor (ReaderExit) -> Void) -> some View {
        modifier(ReaderClosingScope(detail: detail, exit: exit))
    }
}

/// Keeps one context for the life of the presented reader: a new one on every update of the
/// presenter would be a new trait for every view of the engine.
private struct ReaderClosingScope: ViewModifier {
    @State private var context: ReaderClosingContext

    init(detail: GalleryDetailModel?, exit: @escaping @MainActor (ReaderExit) -> Void) {
        _context = State(initialValue: ReaderClosingContext(detail: detail, exit: exit))
    }

    func body(content: Content) -> some View {
        content.environment(\.readerClosingContext, context)
    }
}

// MARK: - From SwiftUI through the engine to the closing page

nonisolated struct ReaderClosingContextTrait: UITraitDefinition {
    static let defaultValue: ReaderClosingContext? = nil
}

extension UITraitCollection {
    nonisolated var readerClosingContext: ReaderClosingContext? { self[ReaderClosingContextTrait.self] }
}

extension UIMutableTraits {
    nonisolated var readerClosingContext: ReaderClosingContext? {
        get { self[ReaderClosingContextTrait.self] }
        set { self[ReaderClosingContextTrait.self] = newValue }
    }
}

nonisolated private struct ReaderClosingContextKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue: ReaderClosingContext? = nil

    static func read(from traitCollection: UITraitCollection) -> ReaderClosingContext? {
        traitCollection.readerClosingContext
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: ReaderClosingContext?) {
        mutableTraits.readerClosingContext = value
    }
}

extension EnvironmentValues {
    /// Set by `readerCover` on the reader it presents; `nil` for a reader presented without it.
    nonisolated var readerClosingContext: ReaderClosingContext? {
        get { self[ReaderClosingContextKey.self] }
        set { self[ReaderClosingContextKey.self] = newValue }
    }
}
