import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// What pulling the sheet up uncovers: the strip of thumbnails, the reading group and the
/// page's actions. A gallery of one page has no strip.
///
/// While the sheet rests they are under its edge: not drawn, closed to touches and to
/// VoiceOver, and without the strip, whose thumbnails follow the reader and would load for
/// nobody.
struct LedgerOpenRows: View {
    let model: ReaderModel
    let sheet: LedgerSheetState
    let watch: LedgerPageWatch
    let isReversed: Bool
    /// Whether the sheet has left its resting height.
    let isUncovered: Bool

    @Environment(\.lookTint) private var tint

    var body: some View {
        VStack(spacing: 0) {
            if model.pageCount > 1 {
                strip
                    .frame(maxWidth: .infinity)
                    .frame(height: LedgerReaderMetrics.stripHeight)
                    .clipped()
            }
            // "TRANSLATION · ON THIS IPHONE", its switch and Original, Translated, Side by
            // side: a group above this one once translation exists. Not in the hierarchy
            // until then.
            ReaderTranslationSlot(availability: model.translationAvailability) { EmptyView() }
            LedgerReadingGroup(model: model, sheet: sheet)
                .padding(.top, LedgerReaderMetrics.groupGap)
            LedgerPagePills(model: model, watch: watch)
                .padding(.top, LedgerReaderMetrics.groupGap)
        }
        .padding(.horizontal, LedgerReaderMetrics.sideInset)
        .opacity(isUncovered ? 1 : 0)
        .allowsHitTesting(isUncovered)
        .accessibilityHidden(!isUncovered)
    }

    @ViewBuilder
    private var strip: some View {
        if isUncovered {
            ReaderThumbnailStrip(
                model: model, length: 9, isReversed: isReversed,
                width: 34, currentWidth: 40, outline: tint, spacing: 6
            )
            // Nine thumbnails are wider than a narrow sheet, whose edges cut the outer ones.
            .fixedSize()
            .background { LedgerStripThumbnailLoader(model: model) }
        } else {
            // The strip's place, so nothing under it moves when it comes.
            Color.clear
        }
    }
}

/// Loads the strip's thumbnails while the strip is there: when it appears, when the reader
/// moves on and when a preview page arrives (`ReaderModel.loadStripThumbnails()`). A view of
/// its own, so these changes re-render nothing else.
private struct LedgerStripThumbnailLoader: View {
    let model: ReaderModel

    private struct Trigger: Equatable {
        let page: Int
        let knownThumbnails: Int
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: Trigger(page: model.sliderPage, knownThumbnails: model.previewURLs.count), initial: true) {
                model.loadStripThumbnails()
            }
    }
}

/// The group: the reading direction as a segmented control, Auto-play with its interval and a
/// switch, and v3's reader options that have no other place in this design: Live Text, and in
/// landscape, in a paged direction, the two settings for two pages side by side.
private struct LedgerReadingGroup: View {
    let model: ReaderModel
    let sheet: LedgerSheetState

    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look

    private static let shape = RoundedRectangle(cornerRadius: LedgerReaderMetrics.groupCornerRadius, style: .continuous)
    /// As drawn: left to right, right to left, vertical.
    private static let directions: [ReadingDirection] = [.leftToRight, .rightToLeft, .vertical]
    private typealias Strings = L10n.Localizable.ReadingView.ToolbarItem.Title

    var body: some View {
        @Bindable var settings = settings
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker(L10n.Localizable.ReadingSettingView.Title.direction, selection: $settings.readingDirection) {
                ForEach(Self.directions) { direction in
                    Text(direction.localizedName).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .frame(minHeight: LedgerReaderMetrics.directionRowHeight)

            LedgerAutoPlayRow(model: model, sheet: sheet)

            // No localized name exists; "Live Text" is the system's own term, as in v3.
            LedgerSwitchRow(title: "Live Text", symbol: "text.viewfinder", isOn: $model.isLiveTextEnabled)
                // The system analyzer is missing on some devices and in the simulator.
                .disabled(!ReaderLiveText.isSupported)

            // Where v3 offered them: where two pages can show.
            if sheet.isLandscape, settings.readingDirection != .vertical {
                LedgerSwitchRow(
                    title: Strings.dualPageMode, symbol: "rectangle.split.2x1", isOn: $settings.enablesDualPageMode
                )
                LedgerSwitchRow(title: Strings.exceptTheCover, symbol: "book.closed", isOn: $settings.exceptCover)
                    .disabled(!settings.enablesDualPageMode)
            }
        }
        .background(look.raised, in: Self.shape)
        .overlay { Self.shape.strokeBorder(look.separator, lineWidth: 0.5) }
    }
}

/// A row of the group: a symbol, a name and what stands at its end, under a hairline.
private struct LedgerGroupRow<Trailing: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let trailing: Trailing

    @Environment(\.look) private var look
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 24)
            Text(title)
                .font(.callout)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Tokens.Spacing.small)
            trailing
        }
        .foregroundStyle(isEnabled ? look.label : look.tertiaryLabel)
        .padding(.horizontal, 14)
        .frame(minHeight: LedgerReaderMetrics.rowHeight)
        // The hairline between rows takes no height, so a row is as tall as it says.
        .overlay(alignment: .top) {
            look.separator
                .frame(height: 0.5)
                .padding(.leading, 14)
        }
    }
}

private struct LedgerSwitchRow: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        LedgerGroupRow(title: title, symbol: symbol) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Auto-play: its interval as a menu, and a switch. The interval is kept while auto-play is
/// off, and applies at once while it runs.
private struct LedgerAutoPlayRow: View {
    let model: ReaderModel
    let sheet: LedgerSheetState

    @Environment(\.look) private var look

    private static let intervals = ReaderAutoPlayPolicy.allCases.filter { $0 != .off }

    var body: some View {
        let policy = model.autoPlay
        let shown = policy == .off ? sheet.autoPlayInterval : policy
        LedgerGroupRow(title: L10n.Localizable.Reader.autoplay, symbol: "timer") {
            Menu {
                Picker(L10n.Localizable.Reader.autoplay, selection: interval) {
                    ForEach(Self.intervals) { choice in
                        Text(Self.name(of: choice)).tag(choice)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(Self.name(of: shown))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(look.secondaryLabel)
                    .frame(minHeight: LedgerReaderMetrics.rowHeight)
                    .contentShape(.rect)
            }
            Toggle(L10n.Localizable.Reader.autoplay, isOn: isOn)
                .labelsHidden()
        }
    }

    /// "every 5 s".
    private static func name(of interval: ReaderAutoPlayPolicy) -> String {
        interval.seconds.map { L10n.Localizable.Reader.Autoplay.every($0) } ?? interval.localizedName
    }

    private var interval: Binding<ReaderAutoPlayPolicy> {
        Binding(
            get: { model.autoPlay == .off ? sheet.autoPlayInterval : model.autoPlay },
            set: { sheet.setAutoPlayInterval($0, of: model) }
        )
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { model.autoPlay != .off },
            set: { sheet.setAutoPlay($0 ? sheet.autoPlayInterval : .off, of: model) }
        )
    }
}
