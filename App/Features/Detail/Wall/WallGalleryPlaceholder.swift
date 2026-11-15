import SwiftUI

/// The panel below the heading while the page opens: the five round actions, a heading, a few
/// chips and a strip of pages in the look's fills, shimmering. Shapes only, so it costs
/// nothing to lay out.
struct WallGalleryPlaceholder: View {
    let metrics: WallGalleryMetrics

    @Environment(\.look) private var look

    private static let chipWidths: [CGFloat] = [104, 122, 78, 84, 96, 112, 70]

    var body: some View {
        let fill = metrics.fill(look)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(spacing: 8) {
                        Circle().fill(fill).frame(width: 50, height: 50)
                        bar(width: 34)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            bar(width: 46)
                .padding(.top, 24)
            FlowLayout(spacing: 6) {
                ForEach(Self.chipWidths.indices, id: \.self) { index in
                    Capsule().fill(fill).frame(width: Self.chipWidths[index], height: 28)
                }
            }
            .padding(.top, 12)
            bar(width: 78)
                .padding(.top, 24)
            HStack(spacing: Tokens.Spacing.small) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(fill)
                        .frame(width: 74, height: 74 / Tokens.Aspect.preview)
                }
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .shimmering()
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat) -> some View {
        Capsule()
            .fill(look.fill2)
            .frame(width: width, height: 9)
    }
}
