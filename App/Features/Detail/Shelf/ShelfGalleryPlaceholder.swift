import SwiftUI

/// The page below the header while it opens: the ruled row, the four tiles and a strip of
/// pages in the look's fills, shimmering. Shapes only, so it costs nothing to lay out.
struct ShelfGalleryPlaceholder: View {
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(spacing: 6) {
                        bar(width: 34, height: 8)
                        bar(width: 40, height: 18)
                        bar(width: 28, height: 8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 66)
            .padding(.horizontal, Tokens.Spacing.small)
            .overlay(alignment: .top) { Rectangle().fill(look.separator).frame(height: 0.5) }
            .overlay(alignment: .bottom) { Rectangle().fill(look.separator).frame(height: 0.5) }
            .padding(.top, Tokens.Spacing.medium)
            HStack(spacing: Tokens.Spacing.small) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(look.surface)
                        .frame(height: 58)
                }
            }
            .padding(.horizontal, Tokens.Spacing.large)
            .padding(.top, 14)
            bar(width: 120, height: 22)
                .padding(.leading, ShelfGalleryLayout.leading)
                .padding(.top, 22)
            HStack(spacing: Tokens.Spacing.small) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(look.fill3)
                        .frame(width: 74, height: 74 / Tokens.Aspect.preview)
                }
            }
            .padding(.leading, ShelfGalleryLayout.leading)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .shimmering()
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 3, style: .continuous)
            .fill(look.fill2)
            .frame(width: width, height: height)
    }
}
