import EhFeatures
import EhModels
import SwiftUI

// The pieces the Index is made of, on a phone and in the iPad column (`ledger.md`
// section 2). Sizes are the drawing's at the default text size; colours and faces are the
// look's, so the same layout reads as paper and New York under the Ledger look and as SF on
// black under Shelf's.

/// The Index's own title: 36 pt on a phone, 28 in the column, in the look's title face.
struct LedgerIndexTitle: View {
    let isColumn: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var pageSize: CGFloat = 36
    @Environment(\.look) private var look

    var body: some View {
        Text(L10n.Localizable.Shell.Place.index)
            .font(isColumn ? .title.bold() : .system(size: pageSize, weight: .bold))
            .lookTitleDesign()
            .foregroundStyle(look.label)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One line of the Index: its mark, a name, a value, and on a phone a chevron.
struct LedgerIndexLine: View {
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

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 13) {
            markView
                .frame(width: 24)
            Text(title)
                .font(isSyntax ? .footnote : .body)
                .fontDesign(isSyntax ? look.syntaxDesign : nil)
                .foregroundStyle(look.label)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(look.secondaryLabel)
                    .lineLimit(1)
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
            LedgerIndexFolderSwatch(color: FolderColor.color(forFolder: index))
        case .allFolders:
            LedgerIndexFolderSwatch(color: look.tertiaryLabel)
        }
    }
}

/// A folder's colour as a 10 pt rounded square.
struct LedgerIndexFolderSwatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

/// A section's heading with an optional control trailing ("1,284 in all", Edit).
struct LedgerIndexSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .lookSectionHeader()
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
                .font(.subheadline.weight(.medium))
        }
    }
}

extension LedgerIndexSectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// "Edit" beside QUICK SEARCHES: opens the existing editor.
///
/// It is the system's Edit button, whose label the system translates; the app has no string
/// of its own for the word. The button never enters an editing state here: switching to
/// editing is taken as the tap.
struct LedgerIndexEditButton: View {
    let action: () -> Void

    var body: some View {
        EditButton()
            .environment(\.editMode, Binding(get: { .inactive }, set: { if $0.isEditing { action() } }))
    }
}

/// A row's highlight while pressed: a fill from the look over the row's own ground, no
/// glass, no shadow.
struct LedgerIndexRowButtonStyle: ButtonStyle {
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

// MARK: Continue

/// The Continue card: the gallery read last, where it was left, and a tap to go on reading.
/// Absent under `tabs` on a phone, where the tab bar's accessory has it.
struct LedgerIndexContinueCard: View {
    let item: ContinueItem
    /// The iPad column's smaller card.
    let isCompact: Bool
    let open: () -> Void

    @Environment(\.look) private var look
    @Environment(\.onTint) private var onTint
    @Environment(\.chrome) private var chrome

    private var cornerRadius: CGFloat { isCompact ? 14 : 18 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Button(action: open) {
            content
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .padding(.vertical, isCompact ? 9 : 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                // On the content: the reader zooms out of the card and back into it.
                .readerSource(sourceID)
                .background(look.raised, in: shape)
                .overlay(alignment: .bottom) { progressBar }
                .clipShape(shape)
                .overlay { shape.strokeBorder(look.separator, lineWidth: 0.5) }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Localizable.Shell.Continue.reading)
        .accessibilityValue("\(item.title.core), \(progressText)")
    }

    private var content: some View {
        HStack(spacing: 12) {
            CoverImage(
                url: item.gallery.coverURL,
                size: isCompact ? CGSize(width: 34, height: 49) : CGSize(width: 40, height: 57),
                cornerRadius: 5
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(isCompact ? L10n.Localizable.Shell.Continue.title : L10n.Localizable.Shell.Continue.reading)
                    .ledgerSmallCapitals()
                Text(item.title.core)
                    .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                    .lookTitleDesign()
                    .foregroundStyle(look.label)
                Text(progressText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(look.secondaryLabel)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if !isCompact {
                Image(systemName: "play.fill")
                    .font(.body)
                    .foregroundStyle(onTint)
                    .frame(width: 38, height: 38)
                    .background(.tint, in: .circle)
                    .accessibilityHidden(true)
            }
        }
    }

    /// 3 pt along the bottom edge: the part read in the tint over a faint track.
    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(look.fill2)
            Rectangle().fill(.tint)
                .scaleEffect(x: min(max(item.fraction, 0), 1), anchor: .leading)
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private var progressText: String {
        L10n.Localizable.Shell.Continue.progress(item.page, item.pageCount, Int((item.fraction * 100).rounded()))
    }

    /// Under `command` the shell zooms the reader out of `continueCard`. Under `tabs` it asks
    /// for `continueBar`, the accessory's; the card shows under `tabs` only beside the iPad
    /// column, where the accessory is off and the card is that control.
    private var sourceID: ReaderSourceID {
        chrome.bar == .tabs ? .continueBar(gid: item.gallery.gid) : .continueCard(gid: item.gallery.gid)
    }
}

extension View {
    /// Ledger's small capitals: 11 pt bold, uppercase, tracked 0.9, secondary, under every
    /// look. A layout detail, not the look's section heading. Uppercase is a text case, so
    /// VoiceOver reads the original string.
    func ledgerSmallCapitals() -> some View {
        modifier(LedgerSmallCapitals())
    }
}

private struct LedgerSmallCapitals: ViewModifier {
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content
            .font(.caption2.bold())
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(look.secondaryLabel)
    }
}

// MARK: Favourites

/// A folder in the phone's two-column grid: its colour, its name and its count.
struct LedgerIndexFolderCell: View {
    let folder: LedgerIndexFolder
    let open: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        Button(action: open) {
            HStack(spacing: 8) {
                LedgerIndexFolderSwatch(color: FolderColor.color(forFolder: folder.index))
                Text(folder.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(look.label)
                    .lineLimit(1)
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
        .buttonStyle(LedgerIndexRowButtonStyle(cornerRadius: 11, ground: look.raised))
        .accessibilityElement(children: .combine)
    }
}
