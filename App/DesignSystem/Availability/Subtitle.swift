import SwiftUI

extension View {
    /// The screen's title with a subtitle under it ("Front Page · 25 new"):
    /// `navigationSubtitle` on iOS 26; on iOS 18, where it does not exist, a two-line title
    /// item in the principal placement, which needs the title as well.
    ///
    /// `subtitle` `nil` shows the title alone. Use with the inline title display mode, which is
    /// where the iOS 18 principal item shows.
    func screenSubtitle(_ subtitle: String?, title: String) -> some View {
        modifier(ScreenSubtitle(title: title, subtitle: subtitle))
    }
}

private struct ScreenSubtitle: ViewModifier {
    let title: String
    let subtitle: String?

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .navigationTitle(title)
                .navigationSubtitle(subtitle ?? "")
        } else if let subtitle {
            content
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(title)
                                .font(.headline)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                    }
                }
        } else {
            content.navigationTitle(title)
        }
    }
}
