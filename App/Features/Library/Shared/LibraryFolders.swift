import EhCore

// The favourites folders as the library's designs and Ledger's Index list them: names and
// counts from `UserStore`, which every favourites page updates.

/// One favourites folder: its number, its name and its count while known.
nonisolated struct LibraryFolder: Identifiable, Equatable, Sendable {
    /// 0...9, or -1 for every folder.
    let index: Int
    let name: String
    /// `nil` until a favourites page said.
    let count: Int?

    var id: Int { index }
}

extension UserStore {
    /// The ten folders with their names and the counts known this session.
    var libraryFolders: [LibraryFolder] {
        (0...9).map { index in
            LibraryFolder(index: index, name: favoriteFolderTitle(index), count: favoriteFolderCounts[index])
        }
    }
}
