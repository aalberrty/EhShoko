import EhFeatures
import EhModels
import SwiftUI

// The pieces only the Index is made of, on a phone and in the iPad column (`ledger.md`
// section 2). Its title, its lines, its folder cells and its small capitals are shared with
// Ledger's other parts (`Library/Shared`). Sizes are the drawing's at the default text size; colours and faces
// are the look's, so the same layout reads as paper and New York under the Ledger look and
// as SF on black under Shelf's.

/// A section's heading with an optional control trailing ("1,284 in all", Edit), or under it
/// at accessibility text sizes, where the two would not fit on one line.
struct LedgerIndexSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                heading
                control
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                heading
                Spacer(minLength: 8)
                control
            }
        }
    }

    private var heading: some View {
        Text(title)
            .lookSectionHeader()
            .lineLimit(1)
    }

    private var control: some View {
        trailing
            .font(.subheadline.weight(.medium))
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
    @Environment(\.dynamicTypeSize) private var typeSize

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
                    .ledgerSmallCaps()
                Text(item.title.core)
                    .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                    .lookTitleDesign()
                    .foregroundStyle(look.label)
                Text(progressText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(look.secondaryLabel)
            }
            // At accessibility sizes the lines wrap rather than cut, and the play circle, which
            // only marks the card as the way to read on, makes room for them.
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            Spacer(minLength: 0)
            if !isCompact, !typeSize.isAccessibilitySize {
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
