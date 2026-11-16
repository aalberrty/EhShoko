import SwiftUI

/// A section's heading on Shelf's gallery page: the look's section title, and a link in the
/// tint at the trailing edge ("All 48 ›"), which is absent when there is nothing more to show.
struct ShelfGallerySectionHeading: View {
    let title: String
    var link: String?
    var action: () -> Void = {}

    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .lookSectionHeader()
            Spacer(minLength: Tokens.Spacing.small)
            if let link {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(link)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
                    .hitAreaOutset()
                }
                .buttonStyle(.plain)
                .hitAreaOutsetReturned()
            }
        }
        .padding(.leading, ShelfGalleryLayout.leading)
        .padding(.trailing, ShelfGalleryLayout.trailing)
        .frame(minHeight: 30)
        .padding(.top, 18)
    }
}

/// The page's measures (`shelf.md` section 4).
enum ShelfGalleryLayout {
    /// The side margins of the page's text: 20 pt leading, 16 trailing, as drawn.
    static let leading: CGFloat = 20
    static let trailing: CGFloat = 16
    /// From this width the page is laid out in two columns.
    static let twoColumnWidth: CGFloat = 700
}
