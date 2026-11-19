import EhFeatures
import EhModels
import SwiftUI

/// One page of a numbered list in the wall (`WallListGrid.numbered`): under its divider, a
/// lazy grid of its covers while the page is near the screen, and blank space of the same
/// height while it is not.
///
/// A grid that has left the screen keeps every cell it built, so a page away from the
/// screen is no grid at all. The grid has the page's height whatever it has measured, so
/// the pages below it stand where `ListPageSpans` says, and it is a new one whenever its
/// columns or its density change, as the grid of a plain list is (`WallArrangement`).
///
/// A view of its own, compared by what it draws: a scroll that brings another page near
/// draws the wall again, and a page of which nothing changed is then left alone.
///
/// What a page costs beside one grid for all: its grid builds its first row the moment it
/// is made, a screen before that row is seen, and when the page has left, its cells go all
/// at once. For the wall's cells that is a frame or two at a page's boundary.
struct WallListPage: View, Equatable {
    let rows: ArraySlice<RankedEntry>
    /// The number on the page's divider; `nil` for the first page, which has none.
    let number: Int?
    let isNear: Bool
    /// How high the page's rows are together.
    let height: CGFloat
    let dividerHeight: CGFloat
    let layout: WallGridLayout
    let style: WallCellStyle
    /// The gallery open in the side pane, whose cover is outlined.
    let selectedID: String?
    let actions: GalleryActionsModel
    let prefetcher: ListCoverPrefetcher

    @Environment(\.openGallery) private var openGallery

    /// What the page draws. The actions model and the prefetcher are the list's own for as
    /// long as it lives, and are not compared.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isNear == rhs.isNear && lhs.number == rhs.number && lhs.height == rhs.height
            && lhs.dividerHeight == rhs.dividerHeight && lhs.layout == rhs.layout && lhs.style == rhs.style
            && lhs.selectedID == rhs.selectedID && lhs.rows == rhs.rows
    }

    var body: some View {
        if isNear {
            VStack(alignment: .leading, spacing: 0) {
                if let number {
                    WallListPageDivider(page: number, height: dividerHeight)
                        .spokenOnlyOnScreen()
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                    cells
                }
                // Both its width and its height are given, so the stack around it never asks
                // the grid how large it is: a lazy grid answers by measuring its rows, and was
                // asked whenever a page came or went.
                .frame(width: width, height: height, alignment: .top)
                .id(WallArrangement(layout))
            }
        } else {
            Color.clear.frame(height: height + (number == nil ? 0 : dividerHeight))
        }
    }

    /// The columns and the gaps between them: the wall's width without its margins.
    private var width: CGFloat {
        CGFloat(layout.columns) * layout.cellWidth + CGFloat(layout.columns - 1) * layout.columnSpacing
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: layout.columnSpacing, alignment: .top),
            count: layout.columns
        )
    }

    /// The cell and its modifiers, written out without a condition (`spikes/S1.md`, rule 1).
    private var cells: some View {
        ForEach(rows) { row in
            WallCoverCell(entry: row.entry, rank: row.rank, isSelected: row.id == selectedID, style: style).equatable()
                .contentShape(.rect)
                // A tap gesture, not a `Button`: a pinch must not open the covers under the
                // fingers, and a finger that moves fails a tap gesture.
                .onTapGesture { openGallery(row.entry.gallery) }
                .accessibilityAddTraits(.isButton)
                .galleryContextMenu(row.entry, actions: actions)
                .onAppear { prefetcher.appeared(row.id) }
        }
    }
}

/// What a grid's rows depend on: which cells share a row, and the form they have.
struct WallArrangement: Hashable {
    let density: WallDensity
    let columns: Int

    init(_ layout: WallGridLayout) {
        density = layout.density
        columns = layout.columns
    }
}
