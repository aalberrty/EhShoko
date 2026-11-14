import EhCore
import EhFeatures
import EhModels
import SwiftUI

extension View {
    /// The long-press menu every list design puts on a gallery (`Design/designs/README.md`
    /// section 5.3): Read, Favourite into the folder used last or Remove from favourites, Move
    /// to folder (in favourites), Search the circle or an artist the title names, Share. Its
    /// preview shows the cover with the full title, the credit and the tags.
    ///
    /// Apply it where the list builds the row, around the cell, never inside it: the cell
    /// stays an `Equatable` value. Only two small structs are created per row; the menu's
    /// entries and the preview are built when the menu opens, so it costs nothing while the
    /// list scrolls.
    ///
    /// - Parameters:
    ///   - entry: the row's gallery.
    ///   - actions: the list's actions model; it performs Read and the favourite actions.
    ///   - offersMove: whether the list shows favourites, where Move to folder is offered.
    func galleryContextMenu(_ entry: GalleryEntry, actions: GalleryActionsModel, offersMove: Bool = false) -> some View {
        contextMenu {
            GalleryContextMenu(entry: entry, actions: actions, offersMove: offersMove)
        } preview: {
            GalleryMenuPreview(entry: entry)
        }
    }
}

/// The long-press menu's entries. `galleryContextMenu(_:actions:offersMove:)` places it; a
/// design that needs the same entries elsewhere (Ledger's More swipe action opens them in a
/// menu of its own) uses this view directly.
struct GalleryContextMenu: View {
    let entry: GalleryEntry
    let actions: GalleryActionsModel
    let offersMove: Bool

    @Environment(StackRouter.self) private var stack
    @Environment(UserStore.self) private var userStore

    var body: some View {
        // Read here, when the menu opens, so rows do not observe the list's favourite changes.
        let folder = actions.favoriteFolder(of: entry)
        let gallery = entry.gallery
        Section {
            Button(L10n.Localizable.List.Action.read, systemImage: "book") {
                actions.read(gallery)
            }
            if actions.isLoggedIn {
                favoriteEntries(folder: folder)
            }
        }
        let searches = GalleryCreditSearch.targets(for: entry)
        if !searches.isEmpty {
            Section {
                ForEach(searches) { target in
                    Button(L10n.Localizable.List.Action.searchArtist(target.name), systemImage: target.systemImage) {
                        stack.push(.search(keyword: target.keyword))
                    }
                }
            }
        }
        if let url = gallery.galleryURL {
            Section {
                ShareLink(item: url) {
                    Label(L10n.Localizable.DetailView.ToolbarItem.Button.share, systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder
    private func favoriteEntries(folder: Int?) -> some View {
        let gallery = entry.gallery
        if let folder {
            if offersMove {
                Menu {
                    ForEach(Array(FavoriteReport.folders), id: \.self) { index in
                        Toggle(isOn: Binding(get: { index == folder }, set: { _ in actions.move(gallery, to: index) })) {
                            Text(userStore.favoriteFolderName(index))
                        }
                        .disabled(index == folder)
                    }
                } label: {
                    Label(L10n.Localizable.List.Action.move, systemImage: "folder")
                }
            }
            Button(L10n.Localizable.List.Action.unfavorite, systemImage: "heart.slash", role: .destructive) {
                actions.unfavorite(gallery)
            }
        } else {
            Button(L10n.Localizable.List.Action.favorite, systemImage: "heart") {
                actions.favorite(gallery)
            }
        }
    }
}

/// The menu's preview: the cover beside the full title, the credit and the tags, which is how
/// a one-line caption is read in full.
private struct GalleryMenuPreview: View {
    let entry: GalleryEntry
    @Environment(\.look) private var look

    private static let coverSize = CGSize(width: 104, height: 149)

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.medium) {
            HStack(alignment: .top, spacing: Tokens.Spacing.medium) {
                CoverImage(url: entry.gallery.coverURL, size: Self.coverSize)
                VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                    CategoryMark(entry.gallery.category, style: .capsule)
                    Text(entry.gallery.title)
                        .font(.headline)
                        .fontDesign(look.titleDesign)
                        .foregroundStyle(look.label)
                        .fixedSize(horizontal: false, vertical: true)
                    if let credit = entry.title.credit {
                        Text(credit)
                            .font(.subheadline)
                            .foregroundStyle(look.secondaryLabel)
                    }
                }
            }
            ForEach(entry.gallery.tags.prefix(6)) { tag in
                TagText(
                    namespace: tag.namespace?.localizedName ?? tag.rawNamespace,
                    color: tag.namespace?.markColor ?? look.secondaryLabel,
                    tags: tag.contents.map { TagText.Tag($0.text, isWeak: $0.isWeak) }
                )
            }
        }
        .padding(Tokens.Spacing.large)
        .frame(width: 340, alignment: .leading)
        .background(look.background)
    }
}

/// The circle and the artists a parsed title names, each as a search.
nonisolated struct GalleryCreditSearch: Identifiable, Equatable {
    let name: String
    let keyword: String
    let systemImage: String

    var id: String { keyword }

    /// At most the circle and three artists. A name that matches one of the gallery's tags in
    /// the same namespace searches that tag exactly; otherwise the name in quotes.
    static func targets(for entry: GalleryEntry) -> [GalleryCreditSearch] {
        let title = entry.title
        let tags = entry.gallery.tags
        var targets: [GalleryCreditSearch] = []
        if let circle = title.circle, !circle.isEmpty {
            targets.append(target(circle, namespace: .group, systemImage: "person.2", tags: tags))
        }
        for artist in title.artists.prefix(3) where !artist.isEmpty {
            targets.append(target(artist, namespace: .artist, systemImage: "paintbrush.pointed", tags: tags))
        }
        // A circle named after its one artist would otherwise appear twice.
        var seen = Set<String>()
        return targets.filter { seen.insert($0.keyword).inserted }
    }

    private static func target(
        _ name: String, namespace: TagNamespace, systemImage: String, tags: [GalleryTag]
    ) -> GalleryCreditSearch {
        let lowered = name.lowercased()
        let match = tags.first { $0.namespace == namespace }.flatMap { tag in
            tag.contents.first { $0.text.lowercased() == lowered }.map { $0.searchKeyword(tag: tag) }
        }
        return GalleryCreditSearch(name: name, keyword: match ?? "\"\(name)\"", systemImage: systemImage)
    }
}

extension ParsedTitle {
    /// "Circle (Artist, Artist)", as the title writes it; `nil` when it names neither.
    var credit: String? {
        let names = self.artists.joined(separator: ", ")
        switch (circle, names.isEmpty) {
        case (let circle?, false): return "\(circle) (\(names))"
        case (let circle?, true): return circle
        case (nil, false): return names
        case (nil, true): return nil
        }
    }
}

extension UserStore {
    /// The folder's name on the site, or "Favorites n" when it has none of its own.
    func favoriteFolderName(_ index: Int) -> String {
        customFavoriteCategoryName(index: index)
            ?? L10n.Localizable.Struct.User.FavoriteCategory.default("\(index)")
    }
}
