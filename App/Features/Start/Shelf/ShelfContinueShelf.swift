import EhFeatures
import EhModels
import SwiftUI

/// Continue on Home: "Continue" with "History ›", over a shelf of up to ten cards, one per
/// gallery in progress (`shelf.md` section 2). Three placeholder cards until the database first
/// answers; no section at all when nothing is in progress. Shown under either bar: the tab
/// bar's accessory shows only the latest gallery, the shelf shows them all.
struct ShelfContinueSection: View {
    let margins: ShelfHomeMargins
    let open: (ContinueItem) -> Void
    let openHistory: () -> Void

    @Environment(ContinueModel.self) private var model

    var body: some View {
        let items = model.items
        let isLoading = model.loadingState.isLoading
        if !items.isEmpty || isLoading {
            VStack(alignment: .leading, spacing: 0) {
                ShelfHomeHeading(
                    title: L10n.Localizable.Shell.Continue.title,
                    link: L10n.Localizable.HistoryView.Title.history, action: openHistory, margins: margins
                )
                if items.isEmpty {
                    ShelfContinuePlaceholders(margins: margins)
                } else {
                    ShelfContinueShelf(items: items, margins: margins, open: open)
                }
            }
        }
    }
}

/// The cards in a horizontal shelf that snaps to them.
struct ShelfContinueShelf: View {
    let items: [ContinueItem]
    let margins: ShelfHomeMargins
    let open: (ContinueItem) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: ShelfContinueCard.spacing) {
                ForEach(items) { item in
                    Button { open(item) } label: {
                        ShelfContinueCard(item: item)
                    }
                    .buttonStyle(.plain)
                    // On the button, which is the one element VoiceOver reads for the card.
                    .accessibilityLabel(item.title.core)
                    .accessibilityValue(ShelfContinueCard.accessibilityValue(of: item))
                    .accessibilityHint(L10n.Localizable.Shell.Continue.reading)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, margins.leading, for: .scrollContent)
        .padding(.top, 1)
    }
}

/// One gallery in progress: the cover beside the title, the credit, a progress bar and
/// "87 / 212". The reader zooms out of the cover.
struct ShelfContinueCard: View {
    let item: ContinueItem

    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 104
    @Environment(\.look) private var look

    static let width: CGFloat = 292
    static let spacing: CGFloat = 12
    static let cornerRadius: CGFloat = 20
    static let cover = CGSize(width: 62, height: 89)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        HStack(alignment: .top, spacing: 12) {
            CoverImage(url: item.gallery.coverURL, size: Self.cover, cornerRadius: 12)
                .readerSource(.continueCard(gid: item.id))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.core)
                    .font(.subheadline.weight(.semibold))
                    .lookTitleDesign()
                    .foregroundStyle(look.label)
                    .lineLimit(2)
                if let credit = item.title.shelfCredit {
                    Text(credit)
                        .font(.caption)
                        .foregroundStyle(look.secondaryLabel)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    ShelfProgressBar(fraction: item.fraction)
                    Text(L10n.Localizable.Gallery.Continue.short(item.page, item.pageCount))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(look.secondaryLabel)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 14))
        .frame(width: Self.width, height: height, alignment: .topLeading)
        .background(look.surface, in: shape)
        .contentShape(shape)
    }

    /// "Page 87 of 212 · 41%".
    static func accessibilityValue(of item: ContinueItem) -> String {
        L10n.Localizable.Shell.Continue.progress(item.page, item.pageCount, Int((item.fraction * 100).rounded()))
    }
}

/// A 4 pt bar: the share read in the tint over the look's fill. The fill is a shape that takes
/// its width from the bar's own bounds, so nothing measures the layout.
private struct ShelfProgressBar: View {
    let fraction: Double
    @Environment(\.look) private var look

    var body: some View {
        Capsule()
            .fill(look.fill2)
            .overlay { ShelfProgressFill(fraction: fraction).fill(.tint) }
            .frame(height: 4)
    }
}

private nonisolated struct ShelfProgressFill: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        let width = rect.width * min(max(fraction, 0), 1)
        let filled = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        return Path(roundedRect: filled, cornerRadius: rect.height / 2)
    }
}

/// What stands in for the cards until the database answers: three card shapes that shimmer.
private struct ShelfContinuePlaceholders: View {
    let margins: ShelfHomeMargins

    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 104
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: ShelfContinueCard.spacing) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: ShelfContinueCard.cornerRadius, style: .continuous)
                    .fill(look.surface)
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(look.fill2)
                            .frame(width: ShelfContinueCard.cover.width, height: ShelfContinueCard.cover.height)
                            .padding(8)
                    }
                    .frame(width: ShelfContinueCard.width, height: height)
            }
        }
        .padding(.leading, margins.leading)
        .padding(.top, 1)
        // As wide as the shelf it stands for, whose scroll view takes the width it is given:
        // without the zero minimum the cards' 900 pt would widen the header, and a list
        // centres a row wider than itself (`ShelfPopularPlaceholders` the same).
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
        .shimmering()
        .accessibilityHidden(true)
    }
}

extension ParsedTitle {
    /// "Circle · Artist, Artist", as Shelf writes a credit; `nil` when the title names neither.
    fileprivate var shelfCredit: String? {
        let names = artists.joined(separator: ", ")
        switch (circle, names.isEmpty) {
        case (let circle?, false): return "\(circle) · \(names)"
        case (let circle?, true): return circle
        case (nil, false): return names
        case (nil, true): return nil
        }
    }
}
