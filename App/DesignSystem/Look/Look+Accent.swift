import EhModels
import SwiftUI
import UIKit

/// The tint a look takes for the user's accent setting, and what reads on it.
struct LookTint {
    let tint: Color
    /// Text and symbols on a fill of `tint`.
    let onTint: Color
    /// `tint` for UIKit (window tints).
    let uiTint: UIColor
}

extension Look {
    /// The user's accent colour if they chose one, otherwise the look's `defaultAccent`
    /// (`Design/designs/README.md` section 7). "Chose one" means the stored colour is not any
    /// variant of system blue, the old default.
    ///
    /// On a chosen colour the label is black when the colour is light and white otherwise; on
    /// the look's own accent it is the look's `onAccent` (under Wall, the ground colour on a
    /// label-coloured tint).
    func tint(for accent: RGBColor) -> LookTint {
        guard !accent.isDefaultAccent else {
            return LookTint(tint: defaultAccent, onTint: onAccent, uiTint: uiDefaultAccent)
        }
        let ui = UIColor(red: accent.red, green: accent.green, blue: accent.blue, alpha: 1)
        return LookTint(tint: Color(uiColor: ui), onTint: accent.isLight ? .black : .white, uiTint: ui)
    }
}

extension RGBColor {
    /// Whether this is the setting's default, system blue, which means "no accent chosen".
    ///
    /// The old app stored its default (`Color.blue`) resolved for the appearance and system it
    /// ran on, so every variant counts: light, dark and high contrast, as iOS 18 and earlier
    /// drew them and as the running system does (iOS 26's light blue is 0088FF, not 007AFF).
    /// Within a step and a half of 8 bits, so a value that went through a hex string or the
    /// legacy import still counts. Choosing "Look's own" stores system blue again.
    var isDefaultAccent: Bool {
        let tolerance = 1.5 / 255
        return Self.defaultAccentVariants.contains { variant in
            abs(red - variant.red) < tolerance && abs(green - variant.green) < tolerance
                && abs(blue - variant.blue) < tolerance
        }
    }

    /// Resolved on the main actor, where the trait collections it reads are built.
    private static let defaultAccentVariants: [RGBColor] = {
        // System blue up to iOS 18: light, dark, and both with Increase Contrast.
        var variants: [RGBColor] = [
            .systemBlue, RGBColor(hex: "0A84FF"), RGBColor(hex: "0040DD"), RGBColor(hex: "409CFF"),
        ].compactMap(\.self)
        for style in [UIUserInterfaceStyle.light, .dark] {
            for contrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection { traits in
                    traits.userInterfaceStyle = style
                    traits.accessibilityContrast = contrast
                }
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                if UIColor.systemBlue.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                    variants.append(RGBColor(red: red, green: green, blue: blue))
                }
            }
        }
        return variants
    }()
}
