import EhFeatures
import EhModels
import SwiftUI

// The groups shown before anything is typed (`shelf.md` section 6). Each is absent when it
// has nothing to show. Tapping a quick search or a recent search searches it at once, as the
// old app did.

/// "Quick searches" with Edit, over a scrolling row of chips: a bookmark in the tint and the
/// words. Shown while typing too, as drawn.
struct ShelfQuickSearches: View {
    let model: SearchSurfaceModel

    @Environment(\.searchFieldController) private var field

    var body: some View {
        let keywords = model.root.quickSearchKeywords
        if !keywords.isEmpty {
            ShelfSearchHeading(title: L10n.Localizable.SearchView.Section.Title.quickSearch) {
                ShelfSearchEditButton(action: model.root.showQuickSearch)
            }
            ShelfQuickSearchChips(keywords: keywords) { field.search($0.keyword) }
                .shelfSearchRow(insets: EdgeInsets())
        }
    }
}

private struct ShelfQuickSearchChips: View {
    let keywords: [SearchKeyword]
    let search: (SearchKeyword) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(keywords, id: \.self) { keyword in
                    Button { search(keyword) } label: {
                        ShelfQuickSearchChip(title: keyword.title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, ShelfSearchMetrics.shelfMargin, for: .scrollContent)
    }
}

/// A chip 34 pt high on the look's surface, in a 44 pt target.
private struct ShelfQuickSearchChip: View {
    let title: String

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bookmark")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .lookSyntaxDesign()
                .foregroundStyle(look.label)
        }
        .font(.footnote)
        .lineLimit(1)
        .padding(.leading, 10)
        .padding(.trailing, 13)
        .frame(minHeight: 34)
        .background(look.surface, in: .capsule)
        .padding(.vertical, 5)
        .contentShape(.rect)
    }
}

/// "Edit" beside the quick searches: opens the existing editor.
///
/// It is the system's Edit button, whose word the system translates; the app has no string of
/// its own for it. The button never shows an editing state: switching to editing is taken as
/// the tap.
private struct ShelfSearchEditButton: View {
    let action: () -> Void

    var body: some View {
        EditButton()
            .environment(\.editMode, Binding(get: { .inactive }, set: { if $0.isEditing { action() } }))
    }
}

/// "Recent" with Clear, over the searches made from the search field, newest first: ten, or
/// twenty on regular width, as the old app showed. A row can be swiped away.
struct ShelfRecentSearches: View {
    let model: SearchSurfaceModel

    @Environment(\.searchFieldController) private var field
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let keywords = Array(model.root.historyKeywords.prefix(sizeClass == .regular ? 20 : 10))
        if !keywords.isEmpty {
            ShelfSearchHeading(title: L10n.Localizable.Search.Group.recent) {
                Button(L10n.Localizable.ConfirmationDialog.Button.clear) {
                    Task { await model.clearRecentSearches() }
                }
            }
            ForEach(keywords, id: \.self) { keyword in
                Button { field.search(keyword) } label: {
                    ShelfRecentSearchRow(keyword: keyword)
                }
                .shelfSearchRow(separator: keyword != keywords.last)
            }
            .onDelete { offsets in
                let removed = offsets.map { keywords[$0] }
                Task {
                    for keyword in removed {
                        await model.removeRecentSearch(keyword)
                    }
                }
            }
        }
    }
}

private struct ShelfRecentSearchRow: View {
    let keyword: String

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(look.secondaryLabel)
                .accessibilityHidden(true)
            Text(keyword)
                .lookSyntaxDesign()
                .foregroundStyle(look.label)
                .lineLimit(1)
                .truncationMode(.middle)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
    }
}

/// "Recently seen": a shelf of the last galleries opened, covers 62 pt wide. A tap opens the
/// gallery, zooming out of its cover.
struct ShelfRecentlySeen: View {
    let model: SearchSurfaceModel

    @Environment(\.openGallery) private var openGallery

    var body: some View {
        let galleries = model.root.recentGalleries
        if !galleries.isEmpty {
            ShelfSearchHeading(title: L10n.Localizable.SearchView.Section.Title.recentlySeen)
            ShelfRecentlySeenShelf(galleries: galleries) { openGallery($0) }
                .shelfSearchRow(insets: EdgeInsets(top: 4, leading: 0, bottom: 16, trailing: 0))
        }
    }
}

private struct ShelfRecentlySeenShelf: View {
    let galleries: [Gallery]
    let open: (Gallery) -> Void

    private static let cover = CGSize(width: 62, height: 89)

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(galleries) { gallery in
                    Button { open(gallery) } label: {
                        CoverImage(url: gallery.coverURL, size: Self.cover, cornerRadius: 8)
                            .zoomSource(gallery.gid)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(gallery.trimmedTitle)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, ShelfSearchMetrics.shelfMargin, for: .scrollContent)
    }
}
