import EhFeatures
import SwiftUI

/// Under the slider at rest: "23 / 48" leading and the round buttons trailing, Auto-play and
/// the reading settings, joined by "Retry failed pages" while pages have failed. A gallery of
/// one page has this row alone.
struct LedgerRestRow: View {
    let model: ReaderModel
    let sheet: LedgerSheetState

    var body: some View {
        HStack(spacing: Tokens.Spacing.small) {
            LedgerPageNumber(model: model)
            Spacer(minLength: Tokens.Spacing.small)
            // Translate and Compare lead the buttons once translation exists. Not in the
            // hierarchy until then.
            ReaderTranslationSlot(availability: model.translationAvailability) { EmptyView() }
            LedgerRetryFailedButton(model: model)
            LedgerAutoPlayButton(model: model, sheet: sheet)
            Button {
                model.showSettings()
            } label: {
                LedgerRoundLabel(symbol: "slider.horizontal.3")
            }
            .ledgerControlName(
                L10n.Localizable.ReadingView.ToolbarItem.Button.readingSetting, symbol: "slider.horizontal.3"
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
    }
}

/// "23 / 48", the page in the title face and the total smaller; "End" on the closing page. It
/// follows the slider, so it names the page being scrubbed to.
private struct LedgerPageNumber: View {
    let model: ReaderModel

    @Environment(\.look) private var look

    var body: some View {
        let position = ReaderPagePosition(model: model)
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xSmall) {
            Text(position.current)
                .font(.title3.bold())
                .fontDesign(look.titleDesign)
                .foregroundStyle(look.label)
            if !position.isAtEnd {
                Text(verbatim: "/ \(position.total)")
                    .font(.footnote)
                    .foregroundStyle(look.secondaryLabel)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .padding(.leading, Tokens.Spacing.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(position.long)
    }
}

/// "Retry failed pages", there only while pages have failed. A view of its own, so a change
/// of the count re-renders nothing else.
private struct LedgerRetryFailedButton: View {
    let model: ReaderModel

    var body: some View {
        if model.failedPageCount > 0 {
            Button {
                model.retryAllFailedImages()
            } label: {
                LedgerRoundLabel(symbol: "exclamationmark.arrow.triangle.2.circlepath")
            }
            .ledgerControlName(
                L10n.Localizable.ReadingView.ToolbarItem.Button.retryAllFailedImages,
                symbol: "exclamationmark.arrow.triangle.2.circlepath"
            )
            .transition(.opacity)
        }
    }
}

/// Auto-play's intervals in a menu, as in v3. While it turns pages the button is lit.
private struct LedgerAutoPlayButton: View {
    let model: ReaderModel
    let sheet: LedgerSheetState

    var body: some View {
        let policy = model.autoPlay
        Menu {
            // The section gives the menu its heading, as in v3.
            Section(L10n.Localizable.Reader.autoplay) {
                Picker(L10n.Localizable.Reader.autoplay, selection: selection) {
                    ForEach(ReaderAutoPlayPolicy.allCases) { policy in
                        Text(policy.localizedName).tag(policy)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            LedgerRoundLabel(symbol: "timer", isOn: policy != .off)
        }
        .ledgerControlName(L10n.Localizable.Reader.autoplay, symbol: "timer")
        .accessibilityValue(policy.seconds.map { L10n.Localizable.Reader.Autoplay.every($0) } ?? policy.localizedName)
    }

    private var selection: Binding<ReaderAutoPlayPolicy> {
        Binding(get: { model.autoPlay }, set: { sheet.setAutoPlay($0, of: model) })
    }
}

/// A symbol on a round fill, which is the tint while its thing is on. A fill, not glass: the
/// sheet under it is.
struct LedgerRoundLabel: View {
    let symbol: String
    var isOn = false

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(\.onTint) private var onTint

    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(isOn ? onTint : look.label)
            .frame(width: LedgerReaderMetrics.roundButton, height: LedgerReaderMetrics.roundButton)
            .background { Circle().fill(isOn ? tint : look.fill3) }
            .contentShape(.circle)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension View {
    /// Names a control that shows a symbol alone: for VoiceOver, and in the large content
    /// viewer at the accessibility text sizes, where the sheet's own text stops growing.
    func ledgerControlName(_ title: String, symbol: String) -> some View {
        accessibilityLabel(title)
            .accessibilityShowsLargeContentViewer {
                Label(title, systemImage: symbol)
            }
    }
}
