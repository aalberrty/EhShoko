import EhCore
import EhFeatures
import SwiftUI

/// The control sheet: its two heights, how the system presents it, and its rows.
///
/// It is a plain system sheet, with no background of its own, so it is glass on iOS 26 and the
/// system's sheet on iOS 18. It is not modal (`presentationBackgroundInteraction`), cannot be
/// swiped away (the tap in the middle of the page hides it), and stays a sheet in landscape.
/// The reading settings and the share sheet are presented from inside it.
struct LedgerReaderSheet: View {
    let model: ReaderModel
    let sheet: LedgerSheetState

    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look
    @State private var stage: LedgerSheetStage
    /// Whether the open rows have been built while the sheet rests.
    @State private var hasOpenRows = false
    @State private var watch = LedgerPageWatch()

    init(model: ReaderModel, sheet: LedgerSheetState) {
        self.model = model
        self.sheet = sheet
        // A sheet that comes back open shows its open rows from its first frame.
        _stage = State(initialValue: sheet.isOpen ? .open : .rest)
    }

    var body: some View {
        let heights = LedgerSheetHeights(hasPages: model.pageCount > 1, open: sheet.openHeight)
        // The rows scroll where the sheet cannot be as tall as they are: at the largest text
        // sizes, and in landscape.
        ScrollView {
            LedgerSheetRows(model: model, sheet: sheet, watch: watch, stage: stage, hasOpenRows: hasOpenRows)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if stage == .open {
                        sheet.openRowsDidLayOut(height: height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        // The open rows are built once the sheet has come to rest, not with it and not under
        // the finger that pulls it up: built at the start of a pull, they cost it its first
        // frames.
        .task {
            try? await Task.sleep(for: LedgerReaderMetrics.openRowsDelay)
            if !Task.isCancelled {
                hasOpenRows = true
            }
        }
        // The sheet's own height, which follows a finger: a size, reported when the stage it
        // gives changes and not on every frame.
        .onGeometryChange(for: LedgerSheetStage.self) { heights.stage(at: $0.size.height) } action: { stage in
            withAnimation(LedgerReaderMetrics.rowsAnimation) { self.stage = stage }
        }
        .background { LedgerPageWatcher(model: model, watch: watch) }
        // A sheet does not inherit the tint.
        .lookEnvironment(look, accent: settings.accentColor)
        .presentationDetents([heights.restDetent, heights.openDetent], selection: detent(heights))
        .presentationBackgroundInteraction(.enabled)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        .presentationCompactAdaptation(.none)
        .readerDestinationSheets(model)
    }

    /// The chosen height as one of the two detents. The open detent's height can change, so
    /// the choice is kept as a flag and not as a detent.
    private func detent(_ heights: LedgerSheetHeights) -> Binding<PresentationDetent> {
        Binding(
            get: { sheet.isOpen ? heights.openDetent : heights.restDetent },
            set: { sheet.isOpen = $0 == heights.openDetent }
        )
    }
}

/// The rows, top down. The slider keeps its place in both arrangements: at rest the page and
/// the round buttons are under it; open, the header is above it and the strip, the group and
/// the pills under it. While the sheet rests the open rows wait under its edge, unseen.
private struct LedgerSheetRows: View {
    let model: ReaderModel
    let sheet: LedgerSheetState
    let watch: LedgerPageWatch
    let stage: LedgerSheetStage
    let hasOpenRows: Bool

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let isReversed = settings.readingDirection == .rightToLeft
        VStack(spacing: 0) {
            if stage == .open {
                LedgerSheetHeader(model: model)
                    .transition(.opacity)
            }
            // A gallery of one page has no slider.
            if model.pageCount > 1 {
                ReaderSliderRow(model: model, isReversed: isReversed)
                    .frame(minHeight: LedgerReaderMetrics.sliderHeight)
                    .padding(.horizontal, LedgerReaderMetrics.textInset)
                    .padding(.bottom, stage == .open ? 0 : LedgerReaderMetrics.restRowGap)
            }
            if stage != .open {
                LedgerRestRow(model: model, sheet: sheet, watch: watch)
                    .transition(.opacity)
            }
            if hasOpenRows || stage != .rest {
                LedgerOpenRows(
                    model: model, sheet: sheet, watch: watch, isReversed: isReversed, isUncovered: stage != .rest
                )
            }
        }
        .padding(.top, LedgerReaderMetrics.topInset)
        .padding(.bottom, LedgerReaderMetrics.bottomInset)
        // The sheet is a bar of controls of fixed sizes over the page, so its text grows as
        // far as the largest standard size, like the system's bars; beyond that the buttons
        // without a name show theirs in the large content viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// "Page 23 of 48", or "End", with the gallery's short title trailing.
private struct LedgerSheetHeader: View {
    let model: ReaderModel

    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.medium) {
            Text(ReaderPagePosition(model: model).long)
                .font(.title2.bold())
                .fontDesign(look.titleDesign)
                .monospacedDigit()
                .foregroundStyle(look.label)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            Spacer(minLength: 0)
            LedgerSheetTitle(model: model)
        }
        .lineLimit(1)
        .padding(.horizontal, LedgerReaderMetrics.textInset)
        .frame(minHeight: LedgerReaderMetrics.headerHeight)
        .accessibilityElement(children: .combine)
    }
}

/// The title without its groups. A view of its own, so a page turn does not parse it again.
private struct LedgerSheetTitle: View {
    let model: ReaderModel

    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look

    var body: some View {
        Text(model.shortTitle(prefersJapanese: settings.displaysJapaneseTitle))
            .font(.footnote)
            .foregroundStyle(look.secondaryLabel)
            .truncationMode(.tail)
    }
}
