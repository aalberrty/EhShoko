import EhFeatures
import SwiftUI

/// The scrub capsule: "23 / 48" and a ruler of ticks with a needle at the page.
///
/// A finger anywhere on it scrubs. The needle keeps its place when the finger lands and then
/// moves as far as the finger does, so nothing jumps under a touch and a touch that never
/// moves chooses no page. While the finger is down the reader stays and the filmstrip shows
/// the pages around the needle; letting go goes to the needle's page. The ruler runs with the
/// reading direction: right to left puts page 1 on the right.
///
/// A gallery of one page shows "1 / 1" and does not scrub.
struct WallReaderScrubCapsule: View {
    let model: ReaderModel
    let isReversed: Bool

    /// The scrub under the finger; nil while no finger is down.
    @State private var scrub: WallReaderScrub?
    @State private var rulerWidth: CGFloat = 0

    var body: some View {
        let scale = WallReaderScale(pageCount: model.pageCount)
        let position = self.position
        HStack(spacing: Tokens.Spacing.medium) {
            WallReaderPageLabel(position: position)
            WallReaderRuler(
                // Under the finger the needle is where the finger put it, between pages too.
                fraction: scrub?.fraction ?? scale.fraction(forPage: model.sliderPage),
                travel: WallReaderRuler.travel(in: rulerWidth),
                isReversed: isReversed, isScrubbing: scrub != nil
            )
            .opacity(scale.canScrub ? 1 : 0.4)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rulerWidth = $0 }
        }
        .padding(.horizontal, Tokens.Spacing.large)
        .frame(maxWidth: .infinity)
        .frame(height: WallReaderMetrics.clusterHeight)
        .contentShape(.capsule)
        .gesture(WallReaderScrubGesture(isEnabled: scale.canScrub) { touch in
            handle(touch, scale: scale)
        })
        .glassSurface(in: .capsule, isInteractive: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(position.long)
        .accessibilityAdjustableAction { direction in
            // Without the filmstrip the reader follows at once.
            switch direction {
            case .increment: model.setSliderPage(model.sliderPage + 1)
            case .decrement: model.setSliderPage(model.sliderPage - 1)
            @unknown default: break
            }
        }
    }

    /// On the closing page the capsule reads "End", until a scrub names a page again.
    private var position: ReaderPagePosition {
        ReaderPagePosition(
            page: model.sliderPage, pageCount: model.pageCount,
            isAtEnd: model.isAtEnd && !model.showsSliderPreview
        )
    }

    private func handle(_ touch: WallReaderScrubGesture.Touch, scale: WallReaderScale) {
        switch touch {
        case .down(let x):
            scrub = WallReaderScrub(fraction: scale.fraction(forPage: model.sliderPage), x: x)
            model.sliderEditingChanged(true)
        case .moved(let x):
            guard var current = scrub else { return }
            current.move(to: x, travel: WallReaderRuler.travel(in: rulerWidth), isReversed: isReversed)
            let page = scale.page(at: current.fraction)
            current.didChoose = current.didChoose || page != model.sliderPage
            scrub = current
            model.setSliderPage(page)
        case .up:
            guard let current = scrub else { return }
            scrub = nil
            if current.didChoose {
                model.sliderEditingChanged(false)
            } else {
                // A touch that named no page goes nowhere, not even off the closing page.
                model.cancelSliderEditing()
            }
        case .cancelled:
            scrub = nil
            model.cancelSliderEditing()
        }
    }
}

/// The pages along the ruler: 0 at page 1, 1 at the last page.
nonisolated struct WallReaderScale {
    let pageCount: Int

    var canScrub: Bool { pageCount > 1 }

    func fraction(forPage page: Int) -> CGFloat {
        guard canScrub else { return 0 }
        return CGFloat(min(max(page, 1), pageCount) - 1) / CGFloat(pageCount - 1)
    }

    func page(at fraction: CGFloat) -> Int {
        guard canScrub else { return 1 }
        return 1 + Int((min(max(fraction, 0), 1) * CGFloat(pageCount - 1)).rounded())
    }
}

/// A scrub in progress.
nonisolated struct WallReaderScrub {
    /// Where the needle is along the ruler, 0 to 1.
    var fraction: CGFloat
    /// The finger's last place across the screen.
    var x: CGFloat
    /// Whether the scrub has named a page other than the one it found.
    var didChoose = false

    /// Moves the needle as far as the finger moved. It stops at the ruler's ends and turns
    /// back as soon as the finger does, from wherever the finger then is.
    mutating func move(to newX: CGFloat, travel: CGFloat, isReversed: Bool) {
        let step = (newX - x) / travel
        fraction = min(max(fraction + (isReversed ? -step : step), 0), 1)
        x = newX
    }
}

/// "23 / 48", the page in bold and the total smaller, or "End" on the closing page. It keeps
/// the width of its widest value, so the ruler beside it does not move as the digits change.
private struct WallReaderPageLabel: View {
    let position: ReaderPagePosition

    @Environment(\.look) private var look

    var body: some View {
        ZStack(alignment: .leading) {
            pages(current: position.total).hidden()
            if position.isAtEnd {
                current(position.current)
            } else {
                pages(current: position.current)
            }
        }
        .lineLimit(1)
        .fixedSize()
        // The capsule has one line's height.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func pages(current page: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            current(page)
            Text(verbatim: " / " + position.total)
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(look.secondaryLabel)
        }
    }

    private func current(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.body.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(look.label)
    }
}

/// The ruler: even ticks, and the needle in the tint with a faint halo. It is a picture; the
/// capsule takes the touches.
private struct WallReaderRuler: View {
    /// 0 at page 1, 1 at the last page.
    let fraction: CGFloat
    /// How far the needle goes from page 1 to the last page.
    let travel: CGFloat
    let isReversed: Bool
    let isScrubbing: Bool

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint

    private static let needleSize = CGSize(width: 4, height: 26)
    private static let halo: CGFloat = 3

    /// The needle's travel along a ruler of `width`: it stays whole inside it, halo included.
    static func travel(in width: CGFloat) -> CGFloat {
        max(width - needleSize.width - halo * 2, 1)
    }

    var body: some View {
        WallReaderTicks()
            .fill(look.tertiaryLabel)
            .frame(maxWidth: .infinity)
            .frame(height: Self.needleSize.height + Self.halo * 2)
            .overlay(alignment: isReversed ? .trailing : .leading) {
                needle.offset(x: (isReversed ? -fraction : fraction) * travel)
            }
            // A turned page moves the needle with a short glide; under the finger it follows
            // at once.
            .animation(isScrubbing ? nil : .snappy(duration: 0.25), value: fraction)
    }

    private var needle: some View {
        RoundedRectangle(cornerRadius: Self.needleSize.width / 2, style: .continuous)
            .fill(tint)
            .frame(width: Self.needleSize.width, height: Self.needleSize.height)
            .padding(Self.halo)
            .background(tint.opacity(0.25), in: .rect(cornerRadius: Self.halo + Self.needleSize.width / 2, style: .continuous))
    }
}

/// Ticks 1.5 pt wide and 10 pt high, 7 pt apart, centred in the ruler.
private nonisolated struct WallReaderTicks: Shape {
    private static let size = CGSize(width: 1.5, height: 10)
    private static let pitch: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width >= Self.size.width else { return path }
        let count = Int((rect.width - Self.size.width) / Self.pitch) + 1
        let span = CGFloat(count - 1) * Self.pitch + Self.size.width
        var x = rect.minX + (rect.width - span) / 2
        let y = rect.midY - Self.size.height / 2
        for _ in 0..<count {
            path.addRect(CGRect(x: x, y: y, width: Self.size.width, height: Self.size.height))
            x += Self.pitch
        }
        return path
    }
}
