import SwiftUI

/// Closes a sheet: the system close button on iOS 26, an "xmark" on iOS 18, named "Close" for
/// VoiceOver (a bare symbol is read by its symbol's name).
struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            Button(role: .close, action: action)
        } else {
            Button(action: action) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(L10n.Localizable.Common.close)
        }
    }
}

/// Confirms a sheet: the system confirm button on iOS 26, a "checkmark" on iOS 18, named
/// "Done" for VoiceOver, which reads the bare checkmark as "Selected".
struct SheetConfirmButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            Button(role: .confirm, action: action)
        } else {
            Button(action: action) {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel(L10n.Localizable.EhSettingView.ToolbarItem.Button.done)
        }
    }
}

/// An alert's cancel button: the system's own title on iOS 26, `title` on iOS 18, where a
/// cancel button needs one.
struct AlertCancelButton: View {
    let title: String

    var body: some View {
        if #available(iOS 26, *) {
            Button(role: .cancel) {}
        } else {
            Button(title, role: .cancel) {}
        }
    }
}
