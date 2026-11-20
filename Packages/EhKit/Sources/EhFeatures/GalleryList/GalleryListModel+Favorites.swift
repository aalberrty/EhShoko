extension GalleryListModel {
    /// Takes the favourites changed from this list (`GalleryActionsModel.favoriteChanges`): a
    /// favourites folder drops the galleries that were removed from favourites, or moved to
    /// another folder, so the row goes at once in every design, whichever way it was changed
    /// (the long-press menu, Ledger's swipe actions). All Favorites keeps a moved gallery,
    /// which is still a favourite. Other lists keep their rows: their favourite marks follow
    /// the change through `GalleryActionsModel.favoriteFolder(of:)`.
    ///
    /// Pass the whole table each time it changes; a gallery dropped before is not there to
    /// drop again.
    public func applyFavoriteChanges(_ changes: [String: FavoriteChange]) {
        guard case .favorites(let folder, _, _) = source, !changes.isEmpty else { return }
        let dropped = Set(changes.compactMap { gid, change in
            Self.leaves(folder, by: change) ? gid : nil
        })
        guard entries.contains(where: { dropped.contains($0.id) }) else { return }
        // Pages start further up by the rows dropped above them (numbered lists only, which a
        // favourites list is not, but kept right whatever the list).
        pageStarts = pageStarts.map { start in
            let above = entries[..<min(start.index, entries.count)].count(where: { dropped.contains($0.id) })
            return PageStart(page: start.page, index: start.index - above)
        }
        entries.removeAll { dropped.contains($0.id) }
        // Nothing left of what was loaded: ask the site what the folder holds now, rather than
        // show placeholders, or an empty folder that has a next page.
        if entries.isEmpty { reload() }
    }

    /// Whether `change` takes a gallery out of `folder` (`-1` is every folder).
    nonisolated static func leaves(_ folder: Int, by change: FavoriteChange) -> Bool {
        switch change {
        case .removed: true
        case .added(let to): folder != -1 && to != folder
        }
    }
}
