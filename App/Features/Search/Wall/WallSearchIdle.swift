import EhFeatures
import EhModels
import SwiftUI

// The groups of Wall's surface that do not depend on the typed text (`wall.md` section 6).
// Each is absent when it has nothing to show. Tapping a quick search or a recent search
// searches it at once, as the old app did.

/// "Quick searches" with Edit, over a scrolling row of chips: a bookmark and the words in the
/// search syntax's face. Shown before and while typing.
struct WallQuickSearches: View {
    let model: SearchSurfaceModel

    @Environment(\.searchFieldController) private var field

    var body: some View {
        let keywords = model.root.quickSearchKeywords
        if !keywords.isEmpty {
            WallSearchHeading(title: L10n.Localizable.SearchView.Section.Title.quickSearch) {
                WallSearchEditButton(action: model.root.showQuickSearch)
            }
            WallQuickSearchChips(keywords: keywords) { field.search($0.keyword) }
                .padding(.top, 4)
                .padding(.bottom, 10)
        }
    }
}

private struct WallQuickSearchChips: View {
    let keywords: [SearchKeyword]
    let search: (SearchKeyword) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(keywords, id: \.self) { keyword in
                    Button { search(keyword) } label: {
                        WallQuickSearchChip(title: keyword.title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }
}

/// A chip 36 pt high on the look's faintest fill, in a 44 pt target.
private struct WallQuickSearchChip: View {
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
        .frame(minHeight: 36)
        .background(look.fill3, in: .capsule)
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

/// "Edit" beside the quick searches: opens the existing editor.
///
/// It is the system's Edit button, whose word the system translates; the app has no string of
/// its own for it. The button never shows an editing state: switching to editing is taken as
/// the tap.
private struct WallSearchEditButton: View {
    let action: () -> Void

    var body: some View {
        EditButton()
            .environment(\.editMode, Binding(get: { .inactive }, set: { if $0.isEditing { action() } }))
            .frame(minHeight: 44)
            .contentShape(.rect)
    }
}

/// "Recent" with Clear, over the searches made from the search field: ten, or twenty on
/// regular width, as the old app showed, the newest nearest the field. A row searches its
/// words; its trailing cross removes it, as the old app's did.
struct WallRecentSearches: View {
    let model: SearchSurfaceModel

    @Environment(\.searchFieldController) private var field
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let newestFirst = model.root.historyKeywords.prefix(sizeClass == .regular ? 20 : 10)
        if !newestFirst.isEmpty {
            WallSearchHeading(title: L10n.Localizable.Search.Group.recent) {
                Button(L10n.Localizable.ConfirmationDialog.Button.clear) {
                    Task { await model.clearRecentSearches() }
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            ForEach(newestFirst.reversed(), id: \.self) { keyword in
                WallRecentSearchRow(keyword: keyword) {
                    field.search(keyword)
                } remove: {
                    Task { await model.removeRecentSearch(keyword) }
                }
            }
        }
    }
}

private struct WallRecentSearchRow: View {
    let keyword: String
    let search: () -> Void
    let remove: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        Button(action: search) {
            WallSearchColumns {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
                    .accessibilityHidden(true)
            } main: {
                Text(keyword)
                    .lookSyntaxDesign()
                    .foregroundStyle(look.label)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Room for the cross over the row's trailing edge.
            .padding(.trailing, 32)
        }
        .buttonStyle(WallSearchRowStyle())
        .overlay(alignment: .trailing) {
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(look.tertiaryLabel)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.trailing, WallSearchMetrics.rowInset - 14)
            // VoiceOver offers removing as an action of the row, which names the words.
            .accessibilityHidden(true)
        }
        .accessibilityAction(named: L10n.Localizable.ConfirmationDialog.Button.remove, remove)
    }
}

/// "Recently seen": a row of the last galleries opened, covers 62 pt wide, as v3 has. A tap
/// opens the gallery, zooming out of its cover.
struct WallRecentlySeen: View {
    let model: SearchSurfaceModel

    @Environment(\.openGallery) private var openGallery

    var body: some View {
        let galleries = model.root.recentGalleries
        if !galleries.isEmpty {
            WallSearchHeading(title: L10n.Localizable.SearchView.Section.Title.recentlySeen)
            WallRecentlySeenCovers(galleries: galleries) { openGallery($0) }
                .padding(.bottom, 6)
        }
    }
}

private struct WallRecentlySeenCovers: View {
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
        .contentMargins(.horizontal, WallSearchMetrics.rowInset, for: .scrollContent)
    }
}
