import SwiftUI

/// Sizes of Ledger's sheet, at the default text size.
nonisolated enum LedgerReaderMetrics {
    /// The resting height, above the safe area. With the safe area under it the sheet covers
    /// the bottom 184 to 185 pt of an iPhone's screen (spike S4).
    static let restHeight: CGFloat = 150
    /// The open height that was drawn. The open sheet is as tall as its rows and never taller
    /// than this, or than its rows at the default text size where the translation group shows
    /// (`LedgerSheetHeights.maximumOpen`): the drawing had the group but not the Live Text row.
    static let maximumOpenHeight: CGFloat = 456
    /// The least the open height stands above the resting one.
    static let minimumPull: CGFloat = 60
    /// How far above its resting height the sheet still counts as resting.
    static let restTolerance: CGFloat = 10

    /// From the sheet's top edge to its first row: the room the grabber takes.
    static let topInset: CGFloat = 22
    /// Under the last row.
    static let bottomInset: CGFloat = 16
    static let headerHeight: CGFloat = 44
    static let sliderHeight: CGFloat = 36
    /// Between the slider and the row under it at rest.
    static let restRowGap: CGFloat = 12
    /// The round buttons at rest.
    static let roundButton: CGFloat = 46
    static let stripHeight: CGFloat = 62
    /// A row of the group.
    static let rowHeight: CGFloat = 46
    /// The group's first row, which holds the segmented control.
    static let directionRowHeight: CGFloat = 50
    static let groupCornerRadius: CGFloat = 20
    /// Above the group and above the pills.
    static let groupGap: CGFloat = 10
    static let pillHeight: CGFloat = 40
    static let pillSpacing: CGFloat = 8
    /// From the sheet's sides to the group and the pills.
    static let sideInset: CGFloat = 16
    /// From the sheet's sides to the header and the slider.
    static let textInset: CGFloat = 20
    /// The line above the translation group: its name, or the current page's status.
    static let translationLineHeight: CGFloat = 26
    /// From the group's edge to that line's text.
    static let translationLineInset: CGFloat = 16
    /// The translation group with its line: the line, the switch and the segmented control.
    static let translationGroupHeight: CGFloat = translationLineHeight + rowHeight + directionRowHeight

    /// The one animation the page's inset changes in (spike S4: the engine follows it frame by
    /// frame, 21 to 24 layout passes over about 0.4 s).
    static let pageAnimation: Animation = .snappy(duration: 0.35)
    /// The rows changing between the sheet's two heights.
    static let rowsAnimation: Animation = .snappy(duration: 0.3)
    /// How long after the sheet is shown its open rows are built: after it has come to rest.
    static let openRowsDelay: Duration = .milliseconds(700)
}

/// Which rows the sheet shows, from the height it stands at. It follows the sheet under a
/// finger, so pulling it up uncovers the open rows instead of an empty sheet.
nonisolated enum LedgerSheetStage: Hashable, Sendable {
    /// At the resting height: the slider, the page and the round buttons.
    case rest
    /// Leaving the resting height: the same, with the open rows under them.
    case rising
    /// Nearer the open height: the header, the slider and the open rows.
    case open
}

/// The sheet's two heights for one gallery, above the safe area.
nonisolated struct LedgerSheetHeights: Equatable, Sendable {
    let rest: CGFloat
    let open: CGFloat

    /// - Parameters:
    ///   - showsTranslation: whether the open rows hold the translation group, which the
    ///     gallery has where it offers Translate.
    ///   - open: the open height once the open rows have been laid out; `nil` gives what they
    ///     need at the default text size in portrait.
    init(hasPages: Bool, showsTranslation: Bool = false, open: CGFloat? = nil) {
        typealias Metrics = LedgerReaderMetrics
        // A gallery of one page has no slider and no strip.
        let slider = hasPages ? Metrics.sliderHeight : 0
        rest = hasPages
            ? Metrics.restHeight
            : Metrics.restHeight - Metrics.sliderHeight - Metrics.restRowGap
        let rows = Metrics.topInset + Metrics.headerHeight + slider + (hasPages ? Metrics.stripHeight : 0)
            + (showsTranslation ? Metrics.translationGroupHeight : 0)
            + Metrics.groupGap + Metrics.directionRowHeight + 2 * Metrics.rowHeight
            + Metrics.groupGap + Metrics.pillHeight + Metrics.bottomInset
        self.open = open ?? rows
    }

    /// The tallest the open sheet grows when its rows are taller (a larger text size, the
    /// two-page rows in landscape); beyond it they scroll. It is the height that was drawn,
    /// or, where the translation group shows, what the rows need with it at the default text
    /// size, so that they never scroll there in portrait.
    static func maximumOpen(hasPages: Bool, showsTranslation: Bool) -> CGFloat {
        max(LedgerReaderMetrics.maximumOpenHeight, Self(hasPages: hasPages, showsTranslation: showsTranslation).open)
    }

    var restDetent: PresentationDetent { .height(rest) }
    var openDetent: PresentationDetent { .height(open) }

    func stage(at height: CGFloat) -> LedgerSheetStage {
        if height <= rest + LedgerReaderMetrics.restTolerance {
            .rest
        } else if height < (rest + open) / 2 {
            .rising
        } else {
            .open
        }
    }
}
