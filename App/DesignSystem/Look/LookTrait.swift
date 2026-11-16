import SwiftUI
import UIKit

/// The look as a UIKit trait of the window, for the one colour UIKit keeps and resolves on its
/// own: the separators of a `List`'s rows (`LookFormStyle`). A list keeps the separator tint its
/// rows were first given, so a tint that changed with the look stayed in the old look's colour
/// until the screen was built again; UIKit does resolve that colour again when a trait that
/// affects colours changes, as it does for light and dark. So the rows get one colour for every
/// look (`Look.traitSeparator`), which reads this trait, and changing the look changes the trait.
///
/// It is the window's: SwiftUI's environment does not reach the views a `List` is made of.
nonisolated struct LookTrait: UITraitDefinition {
    static let defaultValue = Look.shelf
    static let affectsColorAppearance = true
}

extension View {
    /// Puts `look` into the traits of this view's window. The root of a window calls it once,
    /// where it sets the look's environment: the shell, and a harness that stands in for it.
    func windowLook(_ look: Look) -> some View {
        background(WindowLookWriter(look: look))
    }
}

/// An empty view that writes the look into its window's traits.
private struct WindowLookWriter: UIViewRepresentable {
    let look: Look

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        view.look = look
    }

    final class Anchor: UIView {
        var look = Look.shelf {
            didSet { apply() }
        }
        /// The window's look before this view set it, given back when this view leaves the
        /// window: a harness opened over the app from Laboratory sets its own.
        private var replaced: Look?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            if newWindow == nil, let window, let replaced {
                window.traitOverrides[LookTrait.self] = replaced
                self.replaced = nil
            }
        }

        private func apply() {
            // An override that was never set cannot be read: compare with the window's traits.
            guard let window else { return }
            let current = window.traitCollection[LookTrait.self]
            guard current != look else { return }
            if replaced == nil { replaced = current }
            window.traitOverrides[LookTrait.self] = look
        }
    }
}
