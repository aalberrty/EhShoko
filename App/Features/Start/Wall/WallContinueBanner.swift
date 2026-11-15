import EhFeatures
import SwiftUI

/// Continue on Wall's Front Page (`wall.md` section 2): the gallery read last, as the list's
/// first item. The whole banner opens the reader at the page where reading stopped; the shell
/// presents it, zooming out of the banner's cover. Absent when nothing is in progress.
///
/// It is content that scrolls with the covers, so it is a flat surface, not glass.
struct WallContinueBanner: View {
    @Environment(ContinueModel.self) private var continueModel
    @Environment(AppRouter.self) private var appRouter

    var body: some View {
        // `first` alone, so a page turned in another gallery in progress changes nothing here.
        if let item = continueModel.first {
            Button {
                appRouter.reading = ReadingRequest(gallery: item.gallery, page: item.page)
            } label: {
                WallContinueBannerContent(item: item)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
    }
}

/// The banner's face: cover, label, title, progress, and the play button, which is drawn and
/// not a button of its own because the whole banner does what it would.
private struct WallContinueBannerContent: View {
    let item: ContinueItem

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(\.onTint) private var onTint

    private static var height: CGFloat { 76 }
    private static var cornerRadius: CGFloat { 22 }
    private static var coverSize: CGSize { CGSize(width: 42, height: 60) }
    private static var playDiameter: CGFloat { 44 }

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: item.gallery.coverURL, size: Self.coverSize, cornerRadius: 8)
                // The shell's reader for Continue zooms out of this, under `command`.
                .readerSource(.continueCard(gid: item.gallery.gid))
            details
            Image(systemName: "play.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(onTint)
                .frame(width: Self.playDiameter, height: Self.playDiameter)
                .background(tint, in: .circle)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
        .background(look.surface, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Localizable.Shell.Continue.reading)
        .accessibilityValue(accessibilityValue)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.Localizable.Shell.Continue.title)
                .font(.caption2.bold())
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(look.secondaryLabel)
            Text(item.title.core)
                .font(.subheadline.weight(.semibold))
                .lookTitleDesign()
                .foregroundStyle(look.label)
                .padding(.top, 1)
                .padding(.bottom, 6)
            HStack(spacing: 8) {
                WallProgressBar(fraction: item.fraction, track: look.fill2, fill: tint)
                    .frame(height: 4)
                Text(L10n.Localizable.Gallery.Continue.short(item.page, item.pageCount))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(look.secondaryLabel)
                    .fixedSize()
            }
        }
        .lineLimit(1)
    }

    private var accessibilityValue: String {
        let percent = Int((item.fraction * 100).rounded())
        return [item.title.core, L10n.Localizable.Shell.Continue.progress(item.page, item.pageCount, percent)]
            .joined(separator: ", ")
    }
}

/// A thin bar filled to `fraction`, both ends rounded. A layout rather than a geometry reader:
/// the fill takes its share of whatever width the bar is given.
private struct WallProgressBar: View {
    let fraction: Double
    let track: Color
    let fill: Color

    var body: some View {
        WallFractionLayout(fraction: min(max(fraction, 0), 1)) {
            Capsule().fill(track)
            Capsule().fill(fill)
        }
    }
}

/// Places its first subview across the whole width and its second across `fraction` of it,
/// from the leading edge.
private struct WallFractionLayout: Layout {
    let fraction: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            let width = index == 0 ? bounds.width : bounds.width * fraction
            subview.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
        }
    }
}
