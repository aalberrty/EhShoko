import EhCore
import EhFeatures
import SwiftUI

/// The top group: Close, a capsule with the title and the page, and a capsule with Share and
/// More. Three glass shapes in the layer's one container, side by side, none on another.
struct ShelfReaderTopBar: View {
    let model: ReaderModel
    let spreads: ShelfReaderSpreads

    var body: some View {
        HStack(spacing: ShelfReaderMetrics.topSpacing) {
            ReaderCloseControl()
            ShelfReaderTitleCapsule(model: model, spreads: spreads)
            ShelfReaderActionGroup(model: model, offersDualPage: spreads.offersDualPage)
        }
    }
}

/// The title on one line over "Page 23 of 48", "Pages 22–23 of 48" or "End". It follows the
/// slider, so it names the page being scrubbed to.
private struct ShelfReaderTitleCapsule: View {
    let model: ReaderModel
    let spreads: ShelfReaderSpreads

    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 1) {
            Text(model.title(prefersJapanese: settings.displaysJapaneseTitle))
                .font(.footnote.weight(.semibold))
                .fontDesign(look.titleDesign)
                .foregroundStyle(look.label)
            Text(spreads.text(for: ReaderPagePosition(model: model)))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(look.secondaryLabel)
        }
        .lineLimit(1)
        .padding(.horizontal, Tokens.Spacing.large)
        .padding(.vertical, Tokens.Spacing.xSmall)
        .frame(maxWidth: .infinity, minHeight: ReaderMetrics.closeSize)
        .glassSurface(in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// Share (the page on screen) and More, two 44 pt buttons on one capsule.
private struct ShelfReaderActionGroup: View {
    let model: ReaderModel
    let offersDualPage: Bool

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            Button {
                // The page at the moment of the tap; on the closing page, the last page.
                model.perform(.share, page: model.currentPage)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: ReaderMetrics.closeSize, height: ReaderMetrics.closeSize)
                    .contentShape(.rect)
            }
            .accessibilityLabel(L10n.Localizable.ReadingView.ContextMenu.Button.share)

            ShelfReaderMoreMenu(model: model, offersDualPage: offersDualPage)
        }
        .buttonStyle(.plain)
        .font(.body.weight(.medium))
        .foregroundStyle(look.label)
        .glassSurface(in: .capsule, isInteractive: true)
    }
}

/// Which pages the capsule names: the page, or the two pages of a spread when the engine lays
/// out two side by side (`ReaderConfiguration.usesDualPage(in:)`).
struct ShelfReaderSpreads: Equatable {
    /// In landscape, in a paged direction: where two pages can show.
    let offersDualPage: Bool
    let enablesDualPage: Bool
    let exceptCover: Bool

    var isDualPage: Bool { offersDualPage && enablesDualPage }

    func text(for position: ReaderPagePosition) -> String {
        guard isDualPage, !position.isAtEnd else { return position.long }
        let layout = ReaderSpreadLayout(pageCount: position.pageCount, isDualPage: true, exceptCover: exceptCover)
        let pages = layout.pages(inSpread: layout.spreadIndex(forPage: position.page))
        // A spread whose second page is the last reports that page; name the spread from its
        // first page whichever it reports.
        let first = ReaderPagePosition(page: pages.lowerBound, pageCount: position.pageCount, isAtEnd: false)
        return first.long(spreadEndingAt: pages.upperBound)
    }
}
