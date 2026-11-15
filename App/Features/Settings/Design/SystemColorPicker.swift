import SwiftUI
import UIKit

/// The system's colour picker, opened from a menu item. SwiftUI's `ColorPicker` is a well
/// that opens it only when tapped itself, so the accent's "Custom…" presents this instead.
///
/// It reports a colour when the user settles on one, not while a slider or the spectrum is
/// being dragged: each report re-tints the whole app.
struct SystemColorPicker: UIViewControllerRepresentable {
    let initial: UIColor
    let onSelect: (UIColor) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.selectedColor = initial
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: SystemColorPicker
        /// A colour reached by dragging and not yet reported; closing the picker reports it.
        /// Closing without a choice reports nothing, so "Look's own" stays.
        private var pending: UIColor?

        init(parent: SystemColorPicker) {
            self.parent = parent
        }

        func colorPickerViewController(
            _ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool
        ) {
            if continuously {
                pending = color
            } else {
                pending = nil
                parent.onSelect(color)
            }
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            if let pending {
                parent.onSelect(pending)
                self.pending = nil
            }
            parent.dismiss()
        }
    }
}
