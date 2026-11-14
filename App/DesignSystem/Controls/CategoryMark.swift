import EhModels
import SwiftUI

/// A gallery's category in its hue, in the shape a design draws it. The hue is the same in
/// every look (`Category.markColor`); the shape belongs to the layout that places it.
///
/// Takes values only and reads nothing from the environment but the font, so a cell can hold
/// it. The shapes without text are hidden from VoiceOver: the row reads the category's name.
struct CategoryMark: View {
    enum Style: Equatable {
        /// The name in the hue on a 17% tint of it, in a capsule 20 high (Shelf's rows).
        case capsule
        /// A 7 pt rounded square (Wall's captions, its gallery line and tag chips).
        case dot
        /// A 10 pt rounded square (Ledger's rows without a cover).
        case square
        /// A 3 pt bar at the row's leading edge, as tall as the row (Ledger's rows).
        case bar
        /// The name in the hue, in the surrounding font (Ledger's metadata line).
        case name
    }

    private let category: EhModels.Category
    private let style: Style

    init(_ category: EhModels.Category, style: Style) {
        self.category = category
        self.style = style
    }

    var body: some View {
        let color = category.markColor
        switch style {
        case .capsule:
            Text(category.localizedName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .frame(minHeight: 20)
                .background(color.opacity(0.17), in: .capsule)
        case .dot:
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        case .square:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        case .bar:
            UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
        case .name:
            Text(category.localizedName)
                .foregroundStyle(color)
        }
    }
}
