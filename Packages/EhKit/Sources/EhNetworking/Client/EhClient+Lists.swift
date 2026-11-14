import EhModels
import EhParser
import Foundation

// Each list page is parsed once for both its galleries and its paging.
extension EhClient {
    /// Frontpage. Pass the last gallery id of the previous page as `lastID` to continue.
    public func frontpage(filter: Filter, after lastID: String? = nil) async throws -> GalleryListPage {
        try await perform { builder in
            try await listPage(lastID.map { builder.moreFrontpageGalleries(filter: filter, lastID: $0) }
                ?? builder.frontpageGalleries(filter: filter))
        }
    }

    public func popular(filter: Filter) async throws -> [Gallery] {
        try await popularPage(filter: filter).galleries
    }

    /// Popular as a page, with the favourite marks of its galleries. It has no further pages.
    public func popularPage(filter: Filter) async throws -> GalleryListPage {
        try await perform { builder in
            try await listPage(builder.popularGalleries(filter: filter))
        }
    }

    /// Watched tags list. Requires login.
    public func watched(
        filter: Filter, keyword: String = "", after lastID: String? = nil
    ) async throws -> GalleryListPage {
        try await perform { builder in
            try await listPage(
                lastID.map { builder.moreWatchedGalleries(filter: filter, lastID: $0, keyword: keyword) }
                    ?? builder.watchedGalleries(filter: filter, keyword: keyword)
            )
        }
    }

    public func search(
        keyword: String, filter: Filter, after lastID: String? = nil
    ) async throws -> GalleryListPage {
        try await perform { builder in
            try await listPage(
                lastID.map { builder.moreSearchGalleries(keyword: keyword, filter: filter, lastID: $0) }
                    ?? builder.searchGalleries(keyword: keyword, filter: filter)
            )
        }
    }

    /// First page of a favorites category (`-1` is "all"). A non-nil `sortOrder` asks the
    /// server to switch to that order.
    public func favorites(
        category: Int, keyword: String = "", sortOrder: FavoritesSortOrder? = nil
    ) async throws -> FavoritesPage {
        try await perform { builder in
            try await favoritesPage(
                builder.favoritesGalleries(favIndex: category, keyword: keyword, sortOrder: sortOrder)
            )
        }
    }

    /// Next page of a favorites category. `lastTimestamp` is `PageNumber.lastItemTimestamp`
    /// of the previous page.
    public func moreFavorites(
        category: Int, keyword: String = "", lastID: String, lastTimestamp: String
    ) async throws -> FavoritesPage {
        try await perform { builder in
            try await favoritesPage(builder.moreFavoritesGalleries(
                favIndex: category, lastID: lastID, lastTimestamp: lastTimestamp, keyword: keyword
            ))
        }
    }

    /// Toplists are always served by e-hentai.org. `pageNumber` is 0-based; nil is the first page.
    public func toplists(type: ToplistsType, pageNumber: Int? = nil) async throws -> GalleryListPage {
        try await perform { builder in
            try await listPage(builder.toplistsGalleries(type: type, pageNum: pageNumber))
        }
    }
}

private extension EhClient {
    func listPage(_ request: URLRequest) async throws -> GalleryListPage {
        let data = try await body(request)
        let document = try Parser.htmlDocument(data: data)
        return GalleryListPage(
            galleries: try Parser.parseGalleries(doc: document),
            pageNumber: Parser.parsePageNum(doc: document),
            favoriteMarks: Parser.parseFavoriteMarks(doc: document)
        )
    }

    func favoritesPage(_ request: URLRequest) async throws -> FavoritesPage {
        let data = try await body(request)
        let document = try Parser.htmlDocument(data: data)
        return FavoritesPage(
            galleries: try Parser.parseGalleries(doc: document),
            pageNumber: Parser.parsePageNum(doc: document),
            sortOrder: Parser.parseFavoritesSortOrder(doc: document),
            folders: Parser.parseFavoriteFolders(doc: document),
            favoriteMarks: Parser.parseFavoriteMarks(doc: document)
        )
    }
}

// MARK: Result types

/// One page of a gallery list and the paging information to request the next one.
public struct GalleryListPage: Sendable {
    public var galleries: [Gallery]
    public var pageNumber: PageNumber
    /// The favourited galleries among `galleries`, keyed by gid.
    public var favoriteMarks: [String: FavoriteMark]

    public init(galleries: [Gallery], pageNumber: PageNumber, favoriteMarks: [String: FavoriteMark] = [:]) {
        self.galleries = galleries
        self.pageNumber = pageNumber
        self.favoriteMarks = favoriteMarks
    }
}

/// One page of the favorites list. `sortOrder` is the order the server reports on the first page.
public struct FavoritesPage: Sendable {
    public var galleries: [Gallery]
    public var pageNumber: PageNumber
    public var sortOrder: FavoritesSortOrder?
    /// The ten folders with their names and counts, as listed above the galleries. Every
    /// favourites page carries them, whichever folder it shows.
    public var folders: [FavoriteFolder]
    /// The folder and favourited date of each of `galleries`, keyed by gid.
    public var favoriteMarks: [String: FavoriteMark]

    public init(
        galleries: [Gallery], pageNumber: PageNumber, sortOrder: FavoritesSortOrder?,
        folders: [FavoriteFolder] = [], favoriteMarks: [String: FavoriteMark] = [:]
    ) {
        self.galleries = galleries
        self.pageNumber = pageNumber
        self.sortOrder = sortOrder
        self.folders = folders
        self.favoriteMarks = favoriteMarks
    }
}
