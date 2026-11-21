import EhFeatures
import SwiftUI

/// Translate, the cluster's leading circle (`wall.md` section 5): a glass circle of the
/// cluster's height in Wall's one container, filled with the tint while Translate is on.
/// While the models download a ring round its edge follows the download; the dot in the tint
/// says pages of this gallery were translated before.
///
/// It is the only view that reads the availability, so the download's progress re-renders
/// this circle and nothing around it. It is not in the hierarchy for a gallery in another
/// language (`ReaderTranslationSlot`).
struct WallReaderTranslateCircle: View {
    let source: WallReaderTranslationSource

    var body: some View {
        let availability = source.availability
        ReaderTranslationSlot(availability: availability) {
            WallReaderTranslateButton(
                source: source, availability: availability,
                isOn: source.isOn, pagesTranslatedBefore: source.pagesTranslatedBefore
            )
        }
    }
}

private struct WallReaderTranslateButton: View {
    let source: WallReaderTranslationSource
    let availability: ReaderTranslationAvailability
    let isOn: Bool
    let pagesTranslatedBefore: Int

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(\.onTint) private var onTint

    var body: some View {
        Button(action: source.toggle) {
            Image(systemName: "translate")
                .font(.body.weight(.semibold))
                .foregroundStyle(isOn ? onTint : look.label)
                // While on, the circle is the tint and the dot would vanish into it; the
                // stored pages already show.
                .readerTranslationMark(!isOn && pagesTranslatedBefore > 0)
                // The circle keeps its size: the symbol stops growing where More's does.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .frame(width: WallReaderMetrics.clusterHeight, height: WallReaderMetrics.clusterHeight)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .overlay { WallReaderDownloadRing(availability: availability) }
        .readerTranslateAccessibility(ReaderTranslateAccessibility(
            isOn: isOn, pagesTranslatedBefore: pagesTranslatedBefore, availability: availability
        ))
        .accessibilityShowsLargeContentViewer {
            Label(L10n.Localizable.Reader.translate, systemImage: "translate")
        }
        .glassSurface(in: .circle, isInteractive: true, tint: isOn ? tint : nil)
        .animation(.smooth(duration: 0.25), value: isOn)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// The ring round the circle while the models download: a faint track and the part done in
/// the tint, from the top, clockwise. While the models are prepared after the download the
/// ring is full. It draws nothing otherwise, and takes no touches.
private struct WallReaderDownloadRing: View {
    let availability: ReaderTranslationAvailability

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let width: CGFloat = 3

    var body: some View {
        if case .installing(let progress) = availability {
            let fraction = progress?.fraction ?? 1
            ZStack {
                Circle()
                    .inset(by: Self.width / 2)
                    .stroke(look.fill, lineWidth: Self.width)
                Circle()
                    .inset(by: Self.width / 2)
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: Self.width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // The store reports a few times a second: glide between reports.
                    .animation(reduceMotion ? nil : .linear(duration: 0.25), value: fraction)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }
}
