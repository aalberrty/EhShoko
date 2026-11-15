#if DEBUG || HARNESS
import SwiftUI

/// What the reader harness hands the engine for its trailing slot: a stand-in for the closing
/// page with the sizes `closing-page.md` gives it (a 456 pt column at most 420 pt wide), so the
/// slot can be tried with taps, zoom and rotation before the real page exists. The real one is
/// `ReaderClosingPage`, made by the reader's own data source.
///
/// Like the real page it has no gesture on its background, so the engine's tap zones work on
/// every empty part of it, and its height does not depend on the height it is given.
struct ReaderHarnessClosingPage: View {
    let model: ReaderHarnessModel

    @State private var isFavourite = false

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [.indigo, .teal], startPoint: .top, endPoint: .bottom))
                .frame(width: 84, height: 120)
            Spacer().frame(height: 14)
            Text(verbatim: "THE END · \(model.galleryPageCount) PAGES")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Spacer().frame(height: 10)
            Text(verbatim: "A Long Afternoon by the Water, and the Evening After")
                .font(.system(size: 21, weight: .bold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 4)
            Text(verbatim: "Mizuiro Atelier")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer().frame(height: 18)
            stars
            Spacer().frame(height: 18)
            HStack(spacing: 10) {
                tile(isFavourite ? "Favourited" : "Favourite", isFavourite ? "heart.fill" : "heart") {
                    isFavourite.toggle()
                }
                tile("Comments · 37", "bubble.left") {}
                tile("Gallery page", "doc.text") {}
            }
            Spacer().frame(height: 16)
            Button {
                model.closingPageButtonTapped("more by")
            } label: {
                Text(verbatim: "More by Mizuiro Atelier ›").font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    /// Five stars that are only drawn: the real page's rating is F19's.
    private var stars: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { _ in
                Image(systemName: "star")
                    .font(.system(size: 30))
                    .frame(width: 38, height: 38)
            }
        }
        .foregroundStyle(.yellow)
        .accessibilityHidden(true)
    }

    private func tile(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            model.closingPageButtonTapped(title)
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(verbatim: title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 18))
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}
#endif
