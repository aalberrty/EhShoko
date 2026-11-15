import SwiftUI

/// The size of the piles on one screen, worked out once from the grid's width: the drawn
/// size (`wall.md` section 7, covers 76 pt wide) wherever a column holds the whole fan, and
/// smaller in a narrower column, so neighbouring fans never overlap.
nonisolated struct WallPileMetrics: Equatable, Sendable {
    let scale: CGFloat

    /// A pile's cover, 7:10 (`Design/designs/README.md` section 9.3).
    static let coverSize = CGSize(width: 76, height: 109)
    /// From the top of the fan to the name.
    static let stackHeight: CGFloat = 122
    /// How far the back covers lie from the front one: across, and down.
    static let fanOffset = CGSize(width: 19, height: 3)
    /// The back covers' turns, in degrees: the left one anticlockwise, the right one clockwise.
    static let leftTurn: Double = -9
    static let rightTurn: Double = 8
    /// The width of the whole fan: the left cover, turned 9 degrees and moved 19 pt out,
    /// reaches 65 pt from the centre.
    static let fanWidth: CGFloat = 130

    /// How many lines a name may take: one, as drawn; two at accessibility text sizes,
    /// where the grid has fewer columns and a name would otherwise lose most of itself.
    let nameLines: Int

    /// The metrics for a column `width` points wide; the drawn size while the width is not
    /// known yet (0).
    init(columnWidth width: CGFloat, nameLines: Int) {
        scale = width > 0 ? min(1, width / Self.fanWidth) : 1
        self.nameLines = nameLines
    }

    var coverSize: CGSize {
        CGSize(width: (Self.coverSize.width * scale).rounded(), height: (Self.coverSize.height * scale).rounded())
    }

    var stackHeight: CGFloat { (Self.stackHeight * scale).rounded() }
    var offset: CGSize { CGSize(width: Self.fanOffset.width * scale, height: Self.fanOffset.height * scale) }
    var cornerRadius: CGFloat { 7 * scale }
    var top: CGFloat { 6 * scale }
}

/// One pile: three cards fanned, each with a hairline edge and no shadow, then the folder's
/// colour dot and name on one line and its count beneath. It sits in scrolling content, so
/// nothing in it is glass, material or shadow; it takes values only and its body formats
/// nothing.
struct WallPileView: View, Equatable {
    let pile: WallPile
    let metrics: WallPileMetrics

    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 0) {
            WallPileFan(pile: pile, metrics: metrics)
            HStack(spacing: 5) {
                if pile.folder != WallPile.allFolders {
                    Circle()
                        .fill(FolderColor.color(forFolder: pile.folder))
                        .frame(width: 8, height: 8)
                }
                Text(pile.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(look.label)
                    .lineLimit(metrics.nameLines)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            // A count not yet known keeps its line, so the grid does not move when it comes.
            Text(pile.count ?? "0")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(look.secondaryLabel)
                .lineLimit(1)
                .opacity(pile.count == nil ? 0 : 1)
                .accessibilityHidden(pile.count == nil)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pile == rhs.pile && lhs.metrics == rhs.metrics
    }
}

/// The three covers: the newest in front, straight; the second behind it to the left and the
/// third to the right, turned. A place with no cover is a tile.
private struct WallPileFan: View {
    let pile: WallPile
    let metrics: WallPileMetrics

    var body: some View {
        let offset = metrics.offset
        ZStack {
            card(1)
                .rotationEffect(.degrees(WallPileMetrics.leftTurn))
                .offset(x: -offset.width, y: offset.height)
            card(2)
                .rotationEffect(.degrees(WallPileMetrics.rightTurn))
                .offset(x: offset.width, y: offset.height)
            card(0)
        }
        .padding(.top, metrics.top)
        .frame(height: metrics.stackHeight, alignment: .top)
    }

    private func card(_ place: Int) -> some View {
        WallPileCard(card: pile.cards[place], place: place, folder: pile.folder, metrics: metrics)
    }
}

/// One cover, a cover's placeholder, or a tile. Each lies on the look's background, so a
/// translucent placeholder does not show the cards behind it.
private struct WallPileCard: View {
    let card: WallPile.Card
    /// 0 in front, 1 and 2 behind.
    let place: Int
    let folder: Int
    let metrics: WallPileMetrics

    @Environment(\.look) private var look

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        let size = metrics.coverSize
        Group {
            switch card {
            case .cover(let url):
                CoverImage(url: url, size: size, cornerRadius: metrics.cornerRadius)
            case .pending:
                // What `CoverImage` draws while it loads.
                shape
                    .fill(look.fill2)
                    .frame(width: size.width, height: size.height)
            case .tile:
                shape
                    .fill(tileColor.opacity(Self.tileOpacity[place]))
                    .frame(width: size.width, height: size.height)
            }
        }
        .background(look.background, in: shape)
        .overlay { shape.strokeBorder(look.separator, lineWidth: 0.5) }
    }

    /// The folder's colour; the look's neutral fill for All, which has none.
    private var tileColor: Color {
        folder == WallPile.allFolders ? look.fill : FolderColor.color(forFolder: folder)
    }

    /// The front tile full, the ones behind lighter, so three tiles still read as a fan.
    private static let tileOpacity: [Double] = [1, 0.7, 0.45]
}
