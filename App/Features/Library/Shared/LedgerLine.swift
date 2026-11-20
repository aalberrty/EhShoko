import SwiftUI

// The rows Ledger's Index and Ledger's library are made of (`ledger.md` sections 2 and 7).
// Sizes are the drawing's at the default text size; colours and faces are the look's, so the
// same layout reads as paper and New York under the Ledger look and as SF on black under
// Shelf's.

/// One line of the Index or the library: its mark, a name, a value, and on a phone a chevron.
struct LedgerLine: View {
    enum Mark: Equatable {
        /// A symbol in the tint.
        case symbol(String)
        /// A favourites folder's colour.
        case folder(Int)
        /// Every folder: a neutral square.
        case allFolders
    }

    let mark: Mark
    let title: String
    var value: String?
    /// A saved search, set in the look's face for search syntax.
    var isSyntax = false
    var showsChevron = true

    @ScaledMetric(relativeTo: .title3) private var markWidth = LedgerLine.markWidth
    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The mark's column at the default text size; the column grows with the text up to the
    /// first accessibility size, where the marks stop growing so that names keep their room.
    static let markWidth: CGFloat = 24
    /// The space between the mark's column and the name.
    static let markSpacing: CGFloat = 13
    /// The largest text size the marks follow.
    static let largestMarkSize = DynamicTypeSize.accessibility1

    /// The mark's column for a scaled `markWidth`, held at the first accessibility size.
    static func markColumn(_ scaledWidth: CGFloat) -> CGFloat {
        min(scaledWidth, markWidth * 1.6)
    }

    var body: some View {
        HStack(spacing: Self.markSpacing) {
            markView
                .dynamicTypeSize(...Self.largestMarkSize)
                .frame(width: Self.markColumn(markWidth))
            Text(title)
                .font(isSyntax ? .footnote : .body)
                .fontDesign(isSyntax ? look.syntaxDesign : nil)
                .foregroundStyle(look.label)
                // At accessibility sizes a name wraps rather than being cut.
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                // A name before its value; a saved search's own name before its syntax,
                // which can run long.
                .layoutPriority(isSyntax ? 0 : 1)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(look.secondaryLabel)
                    .lineLimit(1)
                    // A count or a filter is short and never cut; a saved search's name is
                    // the user's and may be long.
                    .fixedSize(horizontal: !isSyntax, vertical: false)
                    .layoutPriority(isSyntax ? 1 : 0)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(look.tertiaryLabel)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .symbol(let name):
            Image(systemName: name)
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        case .folder(let index):
            LedgerFolderSwatch(color: FolderColor.color(forFolder: index))
        case .allFolders:
            LedgerFolderSwatch(color: look.tertiaryLabel)
        }
    }
}

/// A folder's colour as a 10 pt rounded square.
struct LedgerFolderSwatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

/// A row's highlight while pressed: a fill from the look over the row's own ground, no
/// glass, no shadow.
struct LedgerRowButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 0
    /// The row's ground at rest: the folder cells' raised colour, or none.
    var ground: Color?

    @Environment(\.look) private var look

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .contentShape(shape)
            .background {
                if let ground {
                    shape.fill(ground)
                }
                if configuration.isPressed {
                    shape.fill(look.fill3)
                }
            }
    }
}

/// A folder in the Index's and the library's grids: its colour, its name and its count.
struct LedgerFolderCell: View {
    let folder: LibraryFolder
    let open: () -> Void

    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        Button(action: open) {
            HStack(spacing: 8) {
                LedgerFolderSwatch(color: FolderColor.color(forFolder: folder.index))
                Text(folder.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(look.label)
                    // One column at accessibility sizes, and there the name may wrap.
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                Spacer(minLength: 4)
                if let count = folder.count {
                    Text(count.formatted())
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(look.secondaryLabel)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 38)
            .overlay { shape.strokeBorder(look.separator, lineWidth: 0.5) }
        }
        .buttonStyle(LedgerRowButtonStyle(cornerRadius: 11, ground: look.raised))
        .accessibilityElement(children: .combine)
    }
}
