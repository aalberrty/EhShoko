import EhModels
import EhNetworking

extension GalleryListModel {
    /// One request to the client. Runs off the main actor: the client parses on its own.
    nonisolated static func fetch(
        _ request: PageRequest, of source: GalleryListSource, filter: Filter, client: EhClient
    ) async throws -> FetchedPage {
        let lastID = request.lastID
        switch source {
        case .frontpage:
            return FetchedPage(try await client.frontpage(filter: filter, after: lastID))
        case .popular:
            return FetchedPage(try await client.popularPage(filter: filter))
        case .watched(let keyword):
            return FetchedPage(try await client.watched(filter: filter, keyword: keyword, after: lastID))
        case .search(let keyword):
            return FetchedPage(try await client.search(keyword: keyword, filter: filter, after: lastID))
        case .toplists(let type):
            let pageNumber: Int? = if case .page(let page) = request { page } else { nil }
            return FetchedPage(try await client.toplists(type: type, pageNumber: pageNumber))
        case .favorites(let category, let keyword, let sortOrder):
            if case .after(let lastID, let timestamp?) = request {
                return FetchedPage(try await client.moreFavorites(
                    category: category, keyword: keyword, lastID: lastID, lastTimestamp: timestamp
                ))
            }
            return FetchedPage(try await client.favorites(category: category, keyword: keyword, sortOrder: sortOrder))
        }
    }
}

/// Where one page of a numbered list starts among its entries.
public nonisolated struct PageStart: Hashable, Sendable, Identifiable {
    /// The page, 1-based.
    public let page: Int
    /// The index in `entries` of its first row.
    public let index: Int

    public var id: Int { page }

    public init(page: Int, index: Int) {
        self.page = page
        self.index = index
    }
}

nonisolated extension FetchedPage {
    init(_ page: GalleryListPage) {
        self.init(galleries: page.galleries, pageNumber: page.pageNumber, favoriteMarks: page.favoriteMarks)
    }

    init(_ page: FavoritesPage) {
        self.init(
            galleries: page.galleries, pageNumber: page.pageNumber, sortOrder: page.sortOrder,
            favoriteMarks: page.favoriteMarks, folders: page.folders
        )
    }
}
