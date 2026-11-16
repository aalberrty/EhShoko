import UIKit

/// The band behind a row on top of the keyboard (a field's input accessory, Ledger's keys).
///
/// iOS 18: the keyboard's backdrop stops at the keys, so a row above it stands on whatever is
/// under the keyboard (the tab bar, the list) unless it draws the band itself. A `UIInputView`
/// with the keyboard's style would draw it, but UIKit keeps every `UIInputView` it has shown
/// alive after its field has gone, also one used only as a backdrop inside the row, so the
/// accessory stays a plain view and takes this colour as its background. The keyboard's
/// backdrop is opaque there, the same grey over any ground (light 209, 211, 216 and dark 44
/// to 47 under the old row), which the system's greys match: `systemGray4` light,
/// `systemGray5` dark, each with its higher-contrast variant.
///
/// iOS 26: `nil`. The keyboard draws no band behind its accessory either, and the row's keys
/// are glass capsules of their own.
enum KeyboardBand {
    static var color: UIColor? {
        if #available(iOS 26, *) { return nil }
        return UIColor { traits in
            let grey: UIColor = traits.userInterfaceStyle == .dark ? .systemGray5 : .systemGray4
            return grey.resolvedColor(with: traits)
        }
    }
}
