import EhModels
import SwiftUI
import UIKit

/// The look and accent the page status views draw in. The engine is UIKit and cannot read
/// SwiftUI's environment, so the reader sets this environment value and SwiftUI hands it to
/// the engine's views as a trait.
nonisolated struct ReaderPageStyle: Equatable, Sendable {
    var look: Look = .shelf
    /// `nil`: the look's own tint.
    var accent: RGBColor?
}

nonisolated struct ReaderPageStyleTrait: UITraitDefinition {
    static let defaultValue = ReaderPageStyle()
    static let affectsColorAppearance = true
}

extension UITraitCollection {
    nonisolated var readerPageStyle: ReaderPageStyle { self[ReaderPageStyleTrait.self] }
}

extension UIMutableTraits {
    nonisolated var readerPageStyle: ReaderPageStyle {
        get { self[ReaderPageStyleTrait.self] }
        set { self[ReaderPageStyleTrait.self] = newValue }
    }
}

nonisolated private struct ReaderPageStyleKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue = ReaderPageStyle()

    static func read(from traitCollection: UITraitCollection) -> ReaderPageStyle {
        traitCollection.readerPageStyle
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: ReaderPageStyle) {
        mutableTraits.readerPageStyle = value
    }
}

extension EnvironmentValues {
    /// Set by the reader around its engine (`ReaderScreen`).
    nonisolated var readerPageStyle: ReaderPageStyle {
        get { self[ReaderPageStyleKey.self] }
        set { self[ReaderPageStyleKey.self] = newValue }
    }
}

extension Look {
    /// The tint of the page status views: the accent the user chose, else the look's own.
    func pageTint(for accent: RGBColor?) -> LookTint {
        if let accent { tint(for: accent) } else { LookTint(tint: defaultAccent, onTint: onAccent, uiTint: uiDefaultAccent) }
    }
}
