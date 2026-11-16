import SwiftUI
import UIKit

// The colour tokens of `Design/designs/README.md` section 7. Each look's table is built once;
// a token read is a `switch` over the look and a stored property.

nonisolated extension Look {
    /// The screen's ground.
    var background: Color { palette.background.color }
    /// Cards and grouped backgrounds.
    var surface: Color { palette.surface.color }
    /// Cards on a surface.
    var raised: Color { palette.raised.color }
    var label: Color { palette.label.color }
    var secondaryLabel: Color { palette.secondaryLabel.color }
    var tertiaryLabel: Color { palette.tertiaryLabel.color }
    var separator: Color { palette.separator.color }
    var fill: Color { palette.fill.color }
    var fill2: Color { palette.fill2.color }
    var fill3: Color { palette.fill3.color }
    /// The tint when the user has not chosen an accent colour (`tint(for:)`).
    var defaultAccent: Color { palette.defaultAccent.color }
    /// Text and symbols on a fill of `defaultAccent`.
    var onAccent: Color { palette.onAccent.color }
    /// Stars, in every look.
    var rating: Color { LookPalette.rating.color }

    /// The separator of whichever look the trait collection carries (`LookTrait`), for a
    /// list's row separators: one colour for every look, which UIKit resolves again when the
    /// look changes, as it does when light and dark change.
    static let traitSeparator = Color(uiColor: UIColor { traits in
        traits[LookTrait.self].palette.separator.ui.resolvedColor(with: traits)
    })

    /// The same tokens for UIKit (window tints, `UISearchTextField`).
    var uiBackground: UIColor { palette.background.ui }
    var uiLabel: UIColor { palette.label.ui }
    var uiSecondaryLabel: UIColor { palette.secondaryLabel.ui }
    var uiDefaultAccent: UIColor { palette.defaultAccent.ui }

    fileprivate var palette: LookPalette {
        switch self {
        case .shelf: .shelf
        case .wall: .wall
        case .ledger: .ledger
        }
    }
}

/// One dynamic colour, as UIKit and SwiftUI each want it. Both are made once, when the table
/// is first read, so a token read allocates nothing.
nonisolated private struct LookColor: Sendable {
    let ui: UIColor
    let color: Color

    /// `light` and `dark` as sRGB components and alpha. With Increase Contrast a translucent
    /// colour (a secondary label, a separator, a fill) moves a third of the way to opaque, as
    /// the system's own label and separator colours do; opaque grounds stay as they are.
    init(light: (Double, Double, Double, Double), dark: (Double, Double, Double, Double)) {
        let ui = UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            let alpha = traits.accessibilityContrast == .high ? value.3 + (1 - value.3) / 3 : value.3
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: alpha)
        }
        self.ui = ui
        color = Color(uiColor: ui)
    }

    init(light: String, dark: String) {
        self.init(light: Self.rgb(light), dark: Self.rgb(dark))
    }

    /// `rgb` at `alpha` in both appearances.
    init(lightRGB: (Double, Double, Double), lightAlpha: Double, darkRGB: (Double, Double, Double), darkAlpha: Double) {
        self.init(
            light: (lightRGB.0 / 255, lightRGB.1 / 255, lightRGB.2 / 255, lightAlpha),
            dark: (darkRGB.0 / 255, darkRGB.1 / 255, darkRGB.2 / 255, darkAlpha)
        )
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double, Double) {
        let value = Int(hex, radix: 16) ?? 0
        return (
            Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255, 1
        )
    }
}

nonisolated private struct LookPalette: Sendable {
    let background: LookColor
    let surface: LookColor
    let raised: LookColor
    let label: LookColor
    let secondaryLabel: LookColor
    let tertiaryLabel: LookColor
    let separator: LookColor
    let fill: LookColor
    let fill2: LookColor
    let fill3: LookColor
    let defaultAccent: LookColor
    let onAccent: LookColor

    static let rating = LookColor(light: "F0A000", dark: "FFD60A")

    // Shelf and Wall share the system's labels, separators and fills; Ledger's are warm.
    private static let coolGrey = (60.0, 60.0, 67.0)
    private static let coolGreyDark = (235.0, 235.0, 245.0)
    private static let coolSeparatorDark = (120.0, 120.0, 128.0)
    private static let warmGrey = (46.0, 40.0, 32.0)
    private static let warmGreyDark = (240.0, 232.0, 220.0)

    private static func coolFills() -> (LookColor, LookColor, LookColor) {
        let grey = (120.0, 120.0, 128.0)
        return (
            LookColor(lightRGB: grey, lightAlpha: 0.20, darkRGB: grey, darkAlpha: 0.32),
            LookColor(lightRGB: grey, lightAlpha: 0.13, darkRGB: grey, darkAlpha: 0.22),
            LookColor(lightRGB: grey, lightAlpha: 0.075, darkRGB: grey, darkAlpha: 0.13)
        )
    }

    static let shelf: LookPalette = {
        let fills = coolFills()
        return LookPalette(
            background: LookColor(light: "FFFFFF", dark: "000000"),
            surface: LookColor(light: "F2F2F7", dark: "1C1C1E"),
            raised: LookColor(light: "FFFFFF", dark: "2C2C2E"),
            label: LookColor(light: "000000", dark: "FFFFFF"),
            secondaryLabel: LookColor(lightRGB: coolGrey, lightAlpha: 0.68, darkRGB: coolGreyDark, darkAlpha: 0.66),
            tertiaryLabel: LookColor(lightRGB: coolGrey, lightAlpha: 0.42, darkRGB: coolGreyDark, darkAlpha: 0.40),
            separator: LookColor(lightRGB: coolGrey, lightAlpha: 0.17, darkRGB: coolSeparatorDark, darkAlpha: 0.38),
            fill: fills.0, fill2: fills.1, fill3: fills.2,
            defaultAccent: LookColor(light: "5856D6", dark: "807DFF"),
            onAccent: LookColor(light: "FFFFFF", dark: "FFFFFF")
        )
    }()

    /// Monochrome chrome: the tint is the label colour and text on it the ground's.
    static let wall: LookPalette = {
        let fills = coolFills()
        return LookPalette(
            background: LookColor(light: "FFFFFF", dark: "000000"),
            surface: LookColor(light: "F0F0F3", dark: "18181A"),
            raised: LookColor(light: "FFFFFF", dark: "2A2A2D"),
            label: LookColor(light: "000000", dark: "FFFFFF"),
            secondaryLabel: LookColor(lightRGB: coolGrey, lightAlpha: 0.68, darkRGB: coolGreyDark, darkAlpha: 0.66),
            tertiaryLabel: LookColor(lightRGB: coolGrey, lightAlpha: 0.42, darkRGB: coolGreyDark, darkAlpha: 0.40),
            separator: LookColor(lightRGB: coolGrey, lightAlpha: 0.17, darkRGB: coolSeparatorDark, darkAlpha: 0.38),
            fill: fills.0, fill2: fills.1, fill3: fills.2,
            defaultAccent: LookColor(light: "000000", dark: "FFFFFF"),
            onAccent: LookColor(light: "FFFFFF", dark: "000000")
        )
    }()

    /// Warm paper and warm near-black, vermilion tint.
    static let ledger: LookPalette = {
        let fill = (110.0, 100.0, 84.0)
        let fillDark = (150.0, 140.0, 125.0)
        return LookPalette(
            background: LookColor(light: "F7F4EE", dark: "121110"),
            surface: LookColor(light: "EFEBE3", dark: "1C1B19"),
            raised: LookColor(light: "FFFDF8", dark: "262422"),
            label: LookColor(light: "1B1A18", dark: "F3EFE8"),
            secondaryLabel: LookColor(lightRGB: warmGrey, lightAlpha: 0.70, darkRGB: warmGreyDark, darkAlpha: 0.68),
            tertiaryLabel: LookColor(lightRGB: warmGrey, lightAlpha: 0.44, darkRGB: warmGreyDark, darkAlpha: 0.42),
            separator: LookColor(lightRGB: warmGrey, lightAlpha: 0.16, darkRGB: warmGreyDark, darkAlpha: 0.14),
            fill: LookColor(lightRGB: fill, lightAlpha: 0.20, darkRGB: fillDark, darkAlpha: 0.30),
            fill2: LookColor(lightRGB: fill, lightAlpha: 0.13, darkRGB: fillDark, darkAlpha: 0.20),
            fill3: LookColor(lightRGB: fill, lightAlpha: 0.08, darkRGB: fillDark, darkAlpha: 0.12),
            defaultAccent: LookColor(light: "C2371F", dark: "FF7256"),
            onAccent: LookColor(light: "FFFFFF", dark: "1F0B06")
        )
    }()
}
