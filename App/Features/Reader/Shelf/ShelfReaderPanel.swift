import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The bottom of the controls: translation's status capsule and the panel, two shapes of
/// one glass container. The capsule is not in the hierarchy for a gallery in another language.
struct ShelfReaderBottom: View {
    let model: ReaderModel
    let isReversed: Bool

    var body: some View {
        // The capsule stands above the panel without taking part in its layout: it comes and
        // goes, and changes its text, without moving the panel.
        ShelfReaderPanel(model: model, isReversed: isReversed)
            .overlay(alignment: .top) {
                ReaderTranslationSlot(availability: model.translationAvailability) {
                    ShelfTranslationCapsule(model: model)
                }
                .alignmentGuide(.top) { $0[.bottom] + Tokens.Spacing.medium }
            }
    }
}

/// The panel (`shelf.md` section 5): nine thumbnails around the slider's page, the slider with
/// the first and last page numbers at its ends, and a row of buttons. The strip and the slider
/// follow the reading direction; a gallery of one page has neither. Nothing on the panel is
/// glass: the panel is.
private struct ShelfReaderPanel: View {
    let model: ReaderModel
    let isReversed: Bool

    @Environment(\.lookTint) private var tint

    private static let shape = RoundedRectangle(cornerRadius: ShelfReaderMetrics.panelCornerRadius, style: .continuous)
    private static let padding = EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)

    var body: some View {
        let hasStrip = model.pageCount > 1
        VStack(spacing: 0) {
            if hasStrip {
                ReaderThumbnailStrip(
                    model: model, length: 9, isReversed: isReversed,
                    width: 36, currentWidth: 45, outline: tint, outlineOffset: 1.5, othersOpacity: 0.72, spacing: 6
                )
                // Nine thumbnails are wider than a phone's panel: the strip runs under the
                // panel's padding to its edges, which cut the outer ones.
                .fixedSize()
                .frame(maxWidth: .infinity)
                .frame(height: 66)
                .padding(.horizontal, -Self.padding.leading)
                ReaderSliderRow(model: model, isReversed: isReversed)
                    .frame(minHeight: 36)
            }
            ShelfReaderButtonRow(model: model)
                .padding(.top, hasStrip ? 6 : 0)
        }
        .padding(Self.padding)
        .clipShape(Self.shape)
        .glassSurface(in: Self.shape, isInteractive: true)
    }
}

/// Auto-play, the reading direction, Translate (for a gallery that is not in another
/// language) and Settings, symbol over label.
private struct ShelfReaderButtonRow: View {
    let model: ReaderModel

    var body: some View {
        HStack(spacing: 6) {
            ShelfAutoPlayButton(model: model)
            ShelfDirectionButton()
            ReaderTranslationSlot(availability: model.translationAvailability) {
                ShelfTranslateButton(model: model)
            }
            Button {
                model.showSettings()
            } label: {
                ShelfPanelButtonLabel(title: L10n.Localizable.Reader.settings, symbol: "textformat.size")
            }
        }
        .buttonStyle(.plain)
    }
}

/// Auto-play's intervals in a menu. While it turns pages the button is lit.
private struct ShelfAutoPlayButton: View {
    let model: ReaderModel

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
            ShelfPanelButtonLabel(title: L10n.Localizable.Reader.autoplay, symbol: "timer", isOn: policy != .off)
        }
        .accessibilityValue(policy.seconds.map { L10n.Localizable.Reader.Autoplay.every($0) } ?? policy.localizedName)
    }

    private var selection: Binding<ReaderAutoPlayPolicy> {
        Binding(get: { model.autoPlay }, set: { model.setAutoPlay($0) })
    }
}

/// The reading direction, named on the button; a menu of the three.
private struct ShelfDirectionButton: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        let direction = settings.readingDirection
        Menu {
            Section(L10n.Localizable.ReadingSettingView.Title.direction) {
                Picker(L10n.Localizable.ReadingSettingView.Title.direction, selection: $settings.readingDirection) {
                    ForEach(ReadingDirection.allCases) { direction in
                        Label(direction.localizedName, systemImage: direction.shelfSymbol).tag(direction)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            ShelfPanelButtonLabel(title: direction.localizedName, symbol: direction.shelfSymbol)
        }
        .accessibilityLabel(L10n.Localizable.ReadingSettingView.Title.direction)
        .accessibilityValue(direction.localizedName)
    }
}

/// A symbol over a short label, on a 54 pt tile that is lit in the tint while its thing is on.
/// `isMarked` puts the mark for pages translated before on the symbol (Translate).
struct ShelfPanelButtonLabel: View {
    let title: String
    let symbol: String
    var isOn = false
    var isMarked = false

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint

    private static let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.title3)
                .readerTranslationMark(isMarked)
                .frame(height: 24)
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isOn ? tint : look.label)
        .padding(.horizontal, Tokens.Spacing.xSmall)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background { Self.shape.fill(isOn ? tint.opacity(0.2) : .clear) }
        .contentShape(Self.shape)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: symbol) }
    }
}

private extension ReadingDirection {
    var shelfSymbol: String {
        switch self {
        case .leftToRight: "arrow.right"
        case .rightToLeft: "arrow.left"
        case .vertical: "arrow.down"
        }
    }
}
