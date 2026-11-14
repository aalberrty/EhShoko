import EhModels
import SwiftUI

// The colours every look shares (`Design/designs/README.md` section 7): the site's ten
// category hues and nine namespace hues, each with a variant for light and one for dark
// grounds, and the site's ten favourites folder colours. They live in the asset catalog under
// `Look/`; each is looked up once, here.

extension EhModels.Category {
    /// The category's hue for marks, dots and bars. Private galleries take Misc's.
    nonisolated var markColor: Color {
        switch self {
        case .doujinshi: MarkColors.doujinshi
        case .manga: MarkColors.manga
        case .artistCG: MarkColors.artistCG
        case .gameCG: MarkColors.gameCG
        case .western: MarkColors.western
        case .nonH: MarkColors.nonH
        case .imageSet: MarkColors.imageSet
        case .cosplay: MarkColors.cosplay
        case .asianPorn: MarkColors.asianPorn
        case .misc, .private: MarkColors.misc
        }
    }
}

extension TagNamespace {
    /// The namespace's hue for its label, dot or small capitals. Language, reclass and temp
    /// take Other's grey.
    nonisolated var markColor: Color {
        switch self {
        case .female: MarkColors.female
        case .male: MarkColors.male
        case .mixed: MarkColors.mixed
        case .artist: MarkColors.artist
        case .group: MarkColors.group
        case .parody: MarkColors.parody
        case .character: MarkColors.character
        case .cosplayer: MarkColors.cosplayer
        case .language, .reclass, .temp, .other: MarkColors.other
        }
    }
}

/// The site's ten favourites folder colours, by folder index.
nonisolated enum FolderColor {
    static func color(forFolder index: Int) -> Color {
        MarkColors.folders[min(max(index, 0), MarkColors.folders.count - 1)]
    }
}

nonisolated private enum MarkColors {
    static let doujinshi = Color("Look/Category/Doujinshi")
    static let manga = Color("Look/Category/Manga")
    static let artistCG = Color("Look/Category/Artist CG")
    static let gameCG = Color("Look/Category/Game CG")
    static let western = Color("Look/Category/Western")
    static let nonH = Color("Look/Category/Non-H")
    static let imageSet = Color("Look/Category/Image Set")
    static let cosplay = Color("Look/Category/Cosplay")
    static let asianPorn = Color("Look/Category/Asian Porn")
    static let misc = Color("Look/Category/Misc")

    static let female = Color("Look/Namespace/female")
    static let male = Color("Look/Namespace/male")
    static let mixed = Color("Look/Namespace/mixed")
    static let artist = Color("Look/Namespace/artist")
    static let group = Color("Look/Namespace/group")
    static let parody = Color("Look/Namespace/parody")
    static let character = Color("Look/Namespace/character")
    static let cosplayer = Color("Look/Namespace/cosplayer")
    static let other = Color("Look/Namespace/other")

    static let folders: [Color] = (0..<10).map { Color("Look/Folder/Folder \($0)") }
}
