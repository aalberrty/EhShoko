import SwiftUI

// A line under a screen's large title ("Version 3.0.0 (42)"). iOS 26 has a toolbar place for
// it; iOS 18 has none, so there the screen shows the same line at the head of its content.
// A screen uses both: `largeSubtitle` on the screen and `LargeSubtitleFallback` where the
// line goes on iOS 18, and each shows only on its own system.

extension View {
    /// The line in the large title's subtitle place on iOS 26; nothing on iOS 18, where the
    /// screen's `LargeSubtitleFallback` shows it.
    func largeSubtitle<Subtitle: View>(@ViewBuilder _ subtitle: () -> Subtitle) -> some View {
        modifier(LargeSubtitleItem(subtitle: subtitle()))
    }
}

/// The line at the head of the screen's content on iOS 18 (a form's first section header);
/// nothing on iOS 26, where `largeSubtitle` puts it under the title.
struct LargeSubtitleFallback<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #unavailable(iOS 26) {
            content
        }
    }
}

private struct LargeSubtitleItem<Subtitle: View>: ViewModifier {
    let subtitle: Subtitle

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.toolbar {
                ToolbarItem(placement: .largeSubtitle) { subtitle }
            }
        } else {
            content
        }
    }
}
