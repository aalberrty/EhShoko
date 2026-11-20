import SwiftUI

extension View {
    /// A screen title that the navigation bar keeps (for Back, the app switcher and VoiceOver)
    /// but does not draw, where the screen draws its own heading or none: an inline title with
    /// an empty principal item in its place.
    ///
    /// Not `toolbar(removing: .title)`: on iOS 26, once the bar changed from `tabs` to `command`,
    /// that left the tab's navigation bar content in UIKit's pending updates, and through the
    /// account button's item it kept the screen's list, rows and header alive.
    func hiddenBarTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
            }
    }
}
