import EhModels
import Foundation
import Kanna

// MARK: User

extension Parser {
    /// The user's favorite folder names from the settings page, keyed by folder index 0–9.
    public static func parseFavoriteCategories(doc: HTMLDocument) throws -> [Int: String] {
        var favoriteCategories = [Int: String]()

        for link in doc.xpath("//div [@id='favsel']") {
            for inputLink in link.xpath("//input") {
                guard let name = inputLink["name"],
                      let value = inputLink["value"],
                      let type = FavoritesType(rawValue: name)
                else { continue }

                favoriteCategories[type.index] = value
            }
        }

        if !favoriteCategories.isEmpty {
            return favoriteCategories
        } else {
            throw AppError.parseFailed
        }
    }

    /// Whether the settings page lists the app's own profile, and its value.
    public static func parseProfileIndex(doc: HTMLDocument) throws -> VerifyEhProfileResponse {
        var profileNotFound = true
        var profileValue: Int?

        let selector = doc.at_xpath("//select [@name='profile_set']")
        let options = selector?.xpath("//option")

        guard let options = options, options.count >= 1
        else { throw AppError.parseFailed }

        for link in options where EhSetting.verifyAppProfileName(with: link.text) {
            profileNotFound = false
            profileValue = Int(link["value"] ?? "")
        }

        return .init(profileValue: profileValue, isProfileNotFound: profileNotFound)
    }
}

// MARK: Favourites folders

extension Parser {
    /// The ten folders listed above a favourites page (`div.fp`), with the user's names and
    /// their counts. Empty when the page lists none (signed out, an error page).
    public static func parseFavoriteFolders(doc: HTMLDocument) -> [FavoriteFolder] {
        var folders = [FavoriteFolder]()
        // `div.fp.fps` is "Show All Favorites", not a folder.
        for (position, block) in doc.xpath("//div[@class='fp']").enumerated() {
            let cells = Array(block.xpath("./div"))
            guard let first = cells.first, let last = cells.last,
                  let count = parseCount(first.text)
            else { continue }
            let index = block["onclick"].flatMap(parseFolderIndex(onclick:)) ?? position
            let name = (last.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard (0...9).contains(index), !folders.contains(where: { $0.index == index }) else { continue }
            folders.append(FavoriteFolder(
                index: index, name: name.isEmpty ? "Favorites \(index)" : name, count: count
            ))
        }
        return folders.sorted { $0.index < $1.index }
    }

    /// "117" or "1,284".
    private static func parseCount(_ text: String?) -> Int? {
        guard let text else { return nil }
        let digits = text.filter(\.isWholeNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    /// `document.location='https://e-hentai.org/favorites.php?favcat=3'`.
    private static func parseFolderIndex(onclick: String) -> Int? {
        guard let range = onclick.range(of: "favcat=") else { return nil }
        return Int(onclick[range.upperBound...].prefix(while: \.isWholeNumber))
    }
}
