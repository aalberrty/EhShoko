import EhFeatures
import SwiftUI

// Ledger's page translation (`ledger.md` section 5, `README` 8): at rest, a round Translate
// button leading the buttons, with the mark for pages translated before, and Compare beside it
// while Translate is on; pulled up, the group
// "TRANSLATION · ON THIS IPHONE" with the switch and the segmented control. The switch and
// the button are one state, on or off for this reader. All of it is fills on the system
// sheet: no glass on glass.
//
// Each piece reads the translation's values in a view of its own, so a download's progress
// or a page's status re-renders that piece and nothing else of the sheet.

private typealias Strings = L10n.Localizable.Reader.Translate

/// The resting row's Translate button, where the gallery offers it, and Compare beside it
/// while Translate is on.
///
/// Compare is shown only where it fits. On a 375 pt phone with failed pages (Retry joins the
/// row) or a four-digit page number there is no room for a fifth round button; Compare is then
/// left out of the resting row and stays in the pulled-up segmented control. The slot asks
/// the row for its room first (`layoutPriority`), so the choice is made with what is left
/// after the page number, the other buttons and the row's smallest gap.
struct LedgerTranslateSlot: View {
    let model: ReaderModel

    var body: some View {
        ReaderTranslationSlot(availability: model.translationAvailability) {
            LedgerTranslateButtons(model: model)
        }
        .layoutPriority(1)
    }
}

private struct LedgerTranslateButtons: View {
    let model: ReaderModel

    var body: some View {
        if model.translation.isOn {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tokens.Spacing.small) {
                    LedgerTranslateButton(model: model)
                    LedgerCompareButton(model: model)
                }
                LedgerTranslateButton(model: model)
            }
        } else {
            LedgerTranslateButton(model: model)
        }
    }
}

/// Compare at rest: lit while the wipe is over the page. A press puts the wipe there, and a
/// second press goes back to the translation.
private struct LedgerCompareButton: View {
    let model: ReaderModel

    private static let symbol = "rectangle.split.2x1"

    var body: some View {
        let isComparing = model.translation.displayMode == .compare
        Button {
            model.translation.setDisplayMode(isComparing ? .translated : .compare)
        } label: {
            LedgerRoundLabel(symbol: Self.symbol, isOn: isComparing)
        }
        .ledgerControlName(Strings.compare, symbol: Self.symbol)
        .sensoryFeedback(.selection, trigger: isComparing)
    }
}

/// The open rows' translation group, where the gallery offers it.
struct LedgerTranslationSection: View {
    let model: ReaderModel

    var body: some View {
        ReaderTranslationSlot(availability: model.translationAvailability) {
            LedgerTranslationGroup(model: model)
        }
    }
}

/// Translate at rest: lit while on, the mark while pages were translated before, and a ring
/// of the download's progress while the models download. A press without models opens the
/// download sheet (`ReaderModel.toggleTranslation()`).
private struct LedgerTranslateButton: View {
    let model: ReaderModel

    var body: some View {
        let isOn = model.translation.isOn
        let count = model.translation.pagesTranslatedBefore
        let availability = model.translationAvailability
        Button {
            model.toggleTranslation()
        } label: {
            LedgerRoundLabel(symbol: "translate", isOn: isOn, hasMark: count > 0, readsSelection: false)
            .overlay {
                if let fraction = availability.downloadFraction {
                    LedgerDownloadRing(fraction: fraction)
                }
            }
        }
        .readerTranslateAccessibility(
            ReaderTranslateAccessibility(isOn: isOn, pagesTranslatedBefore: count, availability: availability)
        )
        .accessibilityShowsLargeContentViewer {
            Label(L10n.Localizable.Reader.translate, systemImage: "translate")
        }
    }
}

/// The download's progress around the round button, in the tint.
private struct LedgerDownloadRing: View {
    let fraction: Double

    @Environment(\.lookTint) private var tint

    var body: some View {
        Circle()
            .trim(from: 0, to: min(max(fraction, 0), 1))
            .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(1.25)
            .accessibilityHidden(true)
    }
}

/// Pulled up: the group's line, then one group of the switch and the segmented control.
private struct LedgerTranslationGroup: View {
    let model: ReaderModel

    @Environment(\.look) private var look

    private static let shape = RoundedRectangle(cornerRadius: LedgerReaderMetrics.groupCornerRadius, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            LedgerTranslationLine(model: model)
            VStack(spacing: 0) {
                LedgerTranslateSwitchRow(model: model)
                LedgerTranslationDisplayRow(model: model)
            }
            .background(look.raised, in: Self.shape)
            .overlay { Self.shape.strokeBorder(look.separator, lineWidth: 0.5) }
        }
    }
}

/// Above the group, one line of fixed height: the group's name ("TRANSLATION · ON THIS
/// IPHONE"), or what the current page or the download is doing ("Translating page 23…",
/// "Couldn't translate page 23" with Try again). A page that is done says nothing more: the
/// segmented control is how to see the original, and the switch names the target. The line
/// keeps its height whatever it says, so the open sheet, and the page above it, do not move
/// with every page.
private struct LedgerTranslationLine: View {
    let model: ReaderModel

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint

    var body: some View {
        let status = model.translation.status
        let text = status?.text(showsDone: false) ?? model.translationAvailability.installingText
        HStack(spacing: 6) {
            if let text {
                if status?.isWorking == true {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityHidden(true)
                } else if status?.offersRetry == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Tokens.Spacing.small)
                if status?.offersRetry == true {
                    Button(ReaderTranslationStatus.retryTitle) {
                        model.retryTranslation()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            } else {
                Text(Strings.group(PageTranslationDevice.name).uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(look.secondaryLabel)
        .padding(.leading, LedgerReaderMetrics.translationLineInset)
        .padding(.trailing, Tokens.Spacing.small)
        .padding(.top, 3)
        .frame(height: LedgerReaderMetrics.translationLineHeight)
    }
}

/// "Translate to 简体中文" and its switch: the same as the resting button, on or off for this
/// reader. Turned on without models, it opens the download sheet and stays off.
private struct LedgerTranslateSwitchRow: View {
    let model: ReaderModel

    var body: some View {
        let title = Strings.`switch`(Strings.target)
        // The group's first row: the group's edge is above it, not a hairline.
        LedgerGroupRow(title: title, symbol: "translate", hasHairline: false) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { model.translation.isOn },
            set: { isOn in
                if isOn != model.translation.isOn { model.toggleTranslation() }
            }
        )
    }
}

/// Original, Translated or Compare while Translate is on (`README` 7.4; there is no side by
/// side). Compare puts the wipe over the page.
private struct LedgerTranslationDisplayRow: View {
    let model: ReaderModel

    private static let modes: [ReaderTranslationDisplayMode] = [.original, .translated, .compare]

    var body: some View {
        Picker(L10n.Localizable.Reader.translate, selection: selection) {
            ForEach(Self.modes, id: \.self) { mode in
                Text(Self.name(of: mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(!model.translation.isOn)
        .padding(.horizontal, 14)
        .frame(minHeight: LedgerReaderMetrics.directionRowHeight)
        .overlay(alignment: .top) {
            LedgerGroupHairline()
        }
    }

    private var selection: Binding<ReaderTranslationDisplayMode> {
        Binding(
            get: { model.translation.displayMode },
            set: { model.translation.setDisplayMode($0) }
        )
    }

    private static func name(of mode: ReaderTranslationDisplayMode) -> String {
        switch mode {
        case .original: Strings.original
        case .translated: Strings.translated
        case .compare: Strings.compare
        }
    }
}

/// Whether the open rows hold the translation group: the sheet's heights count it while they
/// do (`LedgerSheetHeights`). A view of its own, so a download's progress re-renders nothing
/// else.
struct LedgerTranslationPresence: View {
    let model: ReaderModel
    let sheet: LedgerSheetState

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: model.translationAvailability != .unavailable, initial: true) { _, isShown in
                sheet.translationDidChange(isShown: isShown)
            }
    }
}
