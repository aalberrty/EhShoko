import EhFeatures
import SwiftUI

// Pieces every design's Translate control uses: the mark for pages translated before and
// what VoiceOver reads. The button itself, its tint while on and where it sits are each
// design's (`shelf.md`, `wall.md`, `ledger.md`, section 5).

/// The small dot on the Translate control when pages of this gallery were translated before
/// (`README` 8). It is drawn in the look's tint and is not a control of its own: VoiceOver
/// reads it as part of the button (`readerTranslateAccessibility`).
struct ReaderTranslationMark: View {
    @Environment(\.lookTint) private var tint

    /// Its diameter, the same in every design.
    static let size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: Self.size, height: Self.size)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Puts the mark at the top trailing corner of a Translate control's symbol when
    /// `isShown`. Nothing is added to the hierarchy otherwise.
    func readerTranslationMark(_ isShown: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            if isShown {
                ReaderTranslationMark()
                    .offset(x: ReaderTranslationMark.size / 2, y: -ReaderTranslationMark.size / 2)
            }
        }
    }

    /// What VoiceOver reads for a Translate control: its name, on or off, the pages
    /// translated before and a download under way. On and off are in the value, so the
    /// selected trait is not added as well: VoiceOver would say it twice.
    func readerTranslateAccessibility(_ accessibility: ReaderTranslateAccessibility) -> some View {
        self
            .accessibilityLabel(accessibility.label)
            .accessibilityValue(accessibility.value)
    }
}
