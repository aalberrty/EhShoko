import EhFeatures
import EhModels
import SwiftUI

/// Maps a `Route` to the part wrapper that draws it. A design's views are reached only
/// through their wrapper, so this never names one.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .galleryList(.favorites):
            LibraryScreen()
        case .galleryList(let kind):
            GalleryListScreen(context: .place(kind))
        case .search(let keyword):
            GalleryListScreen(
                context: ListContext(kind: .search(keyword: keyword, recordsHistory: false), title: keyword)
            )
        case .typedSearch(let keyword):
            GalleryListScreen(
                context: ListContext(kind: .search(keyword: keyword, recordsHistory: true), title: keyword)
            )
        case .listSearch(let scope, let keyword):
            GalleryListScreen(context: ListContext(kind: .scopedSearch(scope, keyword: keyword), title: keyword))
        case .favoritesFolder(let folder):
            LibraryFolderScreen(folder: folder)
        case .detail(let gallery, let intent):
            GalleryPage(gallery: gallery, intent: intent)
                // From the cover that was tapped, whatever list design drew it. The pane's and
                // the sheet's pages are roots, not destinations, and do not zoom.
                .zoomDestination(gallery.gid)
        case .detailChild(let route):
            GalleryChildScreen(route: route)
        case .settings(let route):
            SettingsDestination(route: route)
        }
    }
}
