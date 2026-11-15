import EhFeatures
import SwiftUI

/// The actions of the page on screen as four pills: Save, Copy, Share and Reload. Save, Copy
/// and Share wait for the page's image. Reload is this page's; held, it offers v3's "Retry
/// failed pages" and "Reload all pages", which have no other place in this design.
///
/// The pills name themselves where every name fits its column, and otherwise show their
/// symbols alone: all four the same way.
struct LedgerPagePills: View {
    let model: ReaderModel

    var body: some View {
        let hasImage = model.currentPageHasImage
        ViewThatFits(in: .horizontal) {
            pills(showsTitles: true, hasImage: hasImage)
            pills(showsTitles: false, hasImage: hasImage)
        }
        .buttonStyle(.plain)
    }

    private func pills(showsTitles: Bool, hasImage: Bool) -> some View {
        LedgerEqualColumns(spacing: LedgerReaderMetrics.pillSpacing) {
            ForEach([ReaderImageAction.save, .copy, .share], id: \.self) { action in
                Button {
                    // The page at the moment of the tap; on the closing page, the last page.
                    model.perform(action, page: model.currentPage)
                } label: {
                    LedgerPillLabel(title: action.localizedName, symbol: action.symbolName, showsTitle: showsTitles)
                }
                .ledgerControlName(action.localizedName, symbol: action.symbolName)
                .disabled(!hasImage)
            }
            LedgerReloadPill(model: model, showsTitle: showsTitles)
        }
    }
}

/// Reload: a tap reloads the page on screen, a hold offers the two reloads of the gallery.
private struct LedgerReloadPill: View {
    let model: ReaderModel
    let showsTitle: Bool

    private typealias Strings = L10n.Localizable.ReadingView.ToolbarItem.Button

    var body: some View {
        let reload = ReaderImageAction.reload
        Menu {
            Button(Strings.retryAllFailedImages, systemImage: "exclamationmark.arrow.triangle.2.circlepath") {
                model.retryAllFailedImages()
            }
            Button(Strings.reloadAllImages, systemImage: reload.symbolName) {
                model.reloadAllImages()
            }
        } label: {
            LedgerPillLabel(title: reload.localizedName, symbol: reload.symbolName, showsTitle: showsTitle)
        } primaryAction: {
            model.perform(reload, page: model.currentPage)
        }
        .ledgerControlName(reload.localizedName, symbol: reload.symbolName)
    }
}

/// A symbol and a name on a capsule fill. A fill, not glass: the sheet under it is.
private struct LedgerPillLabel: View {
    let title: String
    let symbol: String
    let showsTitle: Bool

    @Environment(\.look) private var look
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.medium))
            if showsTitle {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(isEnabled ? look.label : look.tertiaryLabel)
        .padding(.horizontal, Tokens.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: LedgerReaderMetrics.pillHeight)
        .background(look.fill3, in: .capsule)
        .contentShape(.capsule)
    }
}

/// Columns of one width. Asked what it would like, it answers with every column as wide as the
/// widest needs, which is how `ViewThatFits` learns whether every pill's name fits; given a
/// width, it shares it out.
private struct LedgerEqualColumns: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let widest = ideal.map(\.width).max() ?? 0
        let needed = widest * CGFloat(subviews.count) + gaps(subviews.count)
        return CGSize(width: proposal.width ?? needed, height: ideal.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = max((bounds.width - gaps(subviews.count)) / CGFloat(subviews.count), 0)
        var x = bounds.minX
        for subview in subviews {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func gaps(_ count: Int) -> CGFloat {
        spacing * CGFloat(count - 1)
    }
}
