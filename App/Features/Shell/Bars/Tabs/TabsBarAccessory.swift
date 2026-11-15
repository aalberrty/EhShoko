import EhFeatures
import EhModels
import SwiftUI

/// Continue in the tab bar's accessory (`shelf.md` section 1): the cover, the title and the
/// page of the gallery read last, and how far through it the reader is; one tap opens the
/// reader there.
///
/// It draws no background: the accessory's glass is the system's, and the capsule's on the
/// systems that have no accessory, so nothing in it is glass. It has two forms: the full one,
/// and the compact one for the bar's inline slot, where the accessory moves when the bar
/// minimises.
struct TabsBarAccessory: View {
    @Environment(ContinueModel.self) private var continueModel
    @Environment(AppRouter.self) private var appRouter

    var body: some View {
        if let item = continueModel.first {
            let shown = TabsBarAccessoryItem(item)
            Button {
                appRouter.reading = ReadingRequest(gallery: item.gallery, page: item.page)
            } label: {
                TabsBarAccessoryPlacement { isCompact in
                    TabsBarAccessoryLabel(item: shown, isCompact: isCompact)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Localizable.Shell.Continue.reading)
            .accessibilityValue(Self.accessibilityValue(of: shown))
            // The slot's height is the system's and the text in it stops growing, so the
            // largest sizes read it the way they read a tab: held, in the large content viewer.
            .accessibilityShowsLargeContentViewer {
                Label(shown.title, systemImage: "play.fill")
            }
        }
    }

    /// "Tsukiakari Syndrome, Page 87 of 212 · 41%".
    private static func accessibilityValue(of item: TabsBarAccessoryItem) -> String {
        let percent = Int((item.fraction * 100).rounded())
        return [item.title, L10n.Localizable.Shell.Continue.progress(item.page, item.pageCount, percent)]
            .joined(separator: ", ")
    }
}

/// What the accessory shows of the gallery in progress: a small value, so the label is drawn
/// again only when something it shows has changed.
nonisolated struct TabsBarAccessoryItem: Equatable, Sendable {
    let gid: String
    let coverURL: URL?
    /// The parsed title: the inline slot leaves it about 120 pt.
    let title: String
    let page: Int
    let pageCount: Int
    let fraction: Double

    init(_ item: ContinueItem) {
        gid = item.gallery.gid
        coverURL = item.gallery.coverURL
        title = item.title.core
        page = item.page
        pageCount = item.pageCount
        fraction = item.fraction
    }
}

/// The accessory's content at the slot's size: 48 pt high, 360 pt wide on a 402 pt phone and
/// 234 pt in the inline slot (`spikes/S3.md`, question 4), as wide as the window on an iPad.
private struct TabsBarAccessoryLabel: View {
    let item: TabsBarAccessoryItem
    /// The inline slot: the cover, the title and the ring only.
    let isCompact: Bool

    @Environment(\.look) private var look

    /// The slot's height on every system. Never an unlimited height: in the capsule's bottom
    /// inset that would take the screen.
    private static var height: CGFloat { 48 }
    private static var coverSize: CGSize { CGSize(width: 25, height: 36) }

    var body: some View {
        HStack(spacing: 10) {
            CoverImage(url: item.coverURL, size: Self.coverSize, cornerRadius: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lookTitleDesign()
                    .foregroundStyle(look.label)
                if !isCompact {
                    Text(L10n.Localizable.Shell.Continue.page(item.page, item.pageCount))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(look.secondaryLabel)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            TabsBarProgressRing(fraction: item.fraction)
        }
        // The ring is concentric with the capsule's end; the cover's corners stay inside the
        // curve of the other end.
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        // Two lines fit the slot up to this size.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .contentShape(.rect)
        // On the content, inside the accessory's glass: a marker around glass does nothing
        // (`spikes/S4.md`).
        .readerSource(.continueBar(gid: item.gid))
    }
}

/// Tells the accessory's content whether it is in the bar's inline slot.
///
/// The placement is an iOS 26 environment value; on the systems without it the content is the
/// capsule's and always full. Compact unless the placement is `.expanded`: it is `nil` while
/// the accessory is being removed, and the full form must not be laid into an inline slot
/// (`spikes/S3.md`, question 4).
private struct TabsBarAccessoryPlacement<Content: View>: View {
    @ViewBuilder let content: (_ isCompact: Bool) -> Content

    var body: some View {
        if #available(iOS 26, *), TabAccessoryKind.usesSystemAccessory {
            TabsBarSystemAccessoryPlacement(content: content)
        } else {
            content(false)
        }
    }
}

@available(iOS 26, *)
private struct TabsBarSystemAccessoryPlacement<Content: View>: View {
    let content: (_ isCompact: Bool) -> Content

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        content(placement != .expanded)
    }
}
