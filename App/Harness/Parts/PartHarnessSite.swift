#if DEBUG || HARNESS
import EhModels
import Foundation

/// The site the part harness's client answers from: the harness's 120 synthetic galleries (the
/// same as its list fixtures, so the stored page and the history match) as list and favourites
/// pages in the site's Extended mode, which the real parser reads. Covers come from the list
/// harness's cover server, so nothing leaves the device and every decode can be counted.
///
/// The favourites are every other gallery, spread over folders 0 to 8 (six or seven each),
/// folder 9 empty; the folder bar above every favourites page names the ten folders and gives
/// the counts of `PartHarnessAccount.folders`. Pages hold 25 galleries and link the next one
/// as the site does. The favourites' order follows the last `inline_set` asked for.
actor PartHarnessSite {
    nonisolated enum Page: Equatable {
        case favorites
        case watched
        case list(isPaged: Bool)

        /// The page a URL asks for, or `nil` for one the site does not serve (a gallery, the API).
        init?(url: URL) {
            switch url.path {
            case "/favorites.php": self = .favorites
            case "/watched": self = .watched
            case "/popular", "/toplist.php": self = .list(isPaged: false)
            case "", "/": self = .list(isPaged: true)
            default: return nil
            }
        }
    }

    private nonisolated struct Favorite {
        let folder: Int
        let date: Date
    }

    private var galleries: [Gallery] = []
    private var favorites: [String: Favorite] = [:]
    private var sortsByPosted = false

    private nonisolated static let pageSize = 25
    private nonisolated static let folderColors = ["000", "f00", "fa0", "dd0", "080", "9f4", "4bf", "00f", "508", "e8e"]

    /// The site's answer to a page that needs an account, which the client reports as such.
    nonisolated static let loginPrompt = "<html><head><title>E-Hentai.org Login</title></head><body><div class=\"d\"><p>This page requires you to log on.</p></div></body></html>"

    func body(of page: Page, url: URL) async -> String {
        await prepare()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        // The cursor is the last gallery shown, alone or before the favourites' timestamp.
        let after = value("next")?.split(separator: "-").first.map(String.init)
        switch page {
        case .favorites:
            switch value("inline_set") {
            case "fs_p": sortsByPosted = true
            case "fs_f": sortsByPosted = false
            default: break
            }
            let folder = value("favcat").flatMap(Int.init)
            var shown = galleries.filter { favorites[$0.gid].map { folder == nil || $0.folder == folder } ?? false }
            if !sortsByPosted {
                shown.sort { (favorites[$0.gid]?.date ?? .distantPast) > (favorites[$1.gid]?.date ?? .distantPast) }
            }
            let (rows, next) = Self.page(of: shown, after: after)
            let cursor = next.map { gid in
                "favcat=\(value("favcat") ?? "all")&next=\(gid)-\(Int(favorites[gid]?.date.timeIntervalSince1970 ?? 0))"
            }
            return html(rows: rows, isFavorites: true, next: cursor)
        case .watched, .list(isPaged: true):
            let (rows, next) = Self.page(of: galleries, after: after)
            return html(rows: rows, isFavorites: false, next: next.map { "next=\($0)" })
        case .list(isPaged: false):
            return html(rows: Array(galleries.prefix(Self.pageSize)), isFavorites: false, next: nil)
        }
    }

    private func prepare() async {
        guard galleries.isEmpty else { return }
        galleries = await ListHarnessGalleries.make(count: 120, session: "parts", coverLatency: 0.05)
        let reference = Date(timeIntervalSince1970: 1_790_100_000)
        for (index, gallery) in galleries.enumerated() where index.isMultiple(of: 2) {
            // 37 and 120 have no common factor, so every favourite has a date of its own.
            let date = reference.addingTimeInterval(-Double((index * 37) % 120) * 3_600)
            favorites[gallery.gid] = Favorite(folder: (index / 2) % 9, date: date)
        }
    }

    private nonisolated static func page(of galleries: [Gallery], after gid: String?) -> ([Gallery], next: String?) {
        let start = gid.flatMap { gid in galleries.firstIndex { $0.gid == gid }.map { $0 + 1 } } ?? 0
        let rows = Array(galleries.dropFirst(start).prefix(pageSize))
        let hasMore = start + rows.count < galleries.count
        return (rows, hasMore ? rows.last?.gid : nil)
    }

    // MARK: HTML

    private func html(rows: [Gallery], isFavorites: Bool, next: String?) -> String {
        var html = "<html><head><title>E-Hentai</title></head><body>"
        if isFavorites {
            // The order's switch names the order it would switch to.
            html += "<div class=\"ido\"><div><div><a href=\"?inline_set=\(sortsByPosted ? "fs_f" : "fs_p")\">"
            html += sortsByPosted ? "Use Favorited" : "Use Posted"
            html += "</a></div></div></div>"
            html += Self.folderBar
        }
        html += Self.displayModes
        html += "<table class=\"itg glte\"><tbody>"
        for gallery in rows {
            html += row(gallery, isFavorites: isFavorites)
        }
        html += "</tbody></table>"
        if let next {
            html += "<div class=\"searchnav\"><div><a href=\"https://e-hentai.org/?\(next)\">Next &gt;</a></div></div>"
        }
        return html + "</body></html>"
    }

    /// One gallery as the Extended mode draws it. No whitespace between the elements: the
    /// parser takes the node after `gl3e` as the title's link.
    private func row(_ gallery: Gallery, isFavorites: Bool) -> String {
        let url = "https://e-hentai.org/g/\(gallery.gid)/\(gallery.token)/"
        let favorite = favorites[gallery.gid]
        let mark = favorite.map { " style=\"border-color:#\(Self.folderColors[$0.folder])\"" } ?? ""
        var row = "<tr><td class=\"gl1e\"><div><a href=\"\(url)\"><img alt=\"\" src=\"\(Self.escape(gallery.coverURL?.absoluteString ?? ""))\" style=\"height:354px;width:250px\"></a></div></td>"
        row += "<td class=\"gl2e\"><div><div class=\"gl3e\">"
        row += "<div class=\"cn\" onclick=\"document.location='https://e-hentai.org/'\">\(gallery.category.rawValue)</div>"
        row += "<div onclick=\"popUp('\(url)')\" id=\"posted_\(gallery.gid)\"\(mark)>\(Self.date(gallery.postedDate))</div>"
        row += "<div class=\"ir\" style=\"background-position:\(Self.stars(gallery.rating));opacity:1\"></div>"
        if let uploader = gallery.uploader {
            row += "<div><a href=\"https://e-hentai.org/uploader/\(Self.escape(uploader))\">\(Self.escape(uploader))</a></div>"
        }
        row += "<div>\(gallery.pageCount) \(gallery.pageCount == 1 ? "page" : "pages")</div>"
        if isFavorites, let favorite {
            row += "<p>Favorited:</p><p>\(Self.date(favorite.date))</p>"
        }
        row += "</div><a href=\"\(url)\"><div class=\"glink\">\(Self.escape(gallery.title))</div><div><table><tbody>"
        for tag in gallery.tags {
            row += "<tr><td class=\"tc\">\(tag.rawNamespace):</td><td>"
            for content in tag.contents {
                row += "<div class=\"gt\" title=\"\(Self.escape("\(tag.rawNamespace):\(content.text)"))\">\(Self.escape(content.text))</div>"
            }
            row += "</td></tr>"
        }
        return row + "</tbody></table></div></a></div></td></tr>"
    }

    private nonisolated static let folderBar = PartHarnessAccount.folders.map { folder in
        "<div class=\"fp\" onclick=\"document.location='https://e-hentai.org/favorites.php?favcat=\(folder.index)'\"><div>\(folder.count)</div><div class=\"i\"></div><div>\(escape(folder.name))</div></div>"
    }.joined()

    private nonisolated static let displayModes = "<div id=\"dms\"><div><select onchange=\"document.location='?inline_set=dm_'+this.value\"><option value=\"m\">Minimal</option><option value=\"p\">Minimal+</option><option value=\"l\">Compact</option><option value=\"e\" selected=\"selected\">Extended</option><option value=\"t\">Thumbnail</option></select></div></div>"

    /// The sprite offsets of the stars image: the whole stars across, a half star below.
    private nonisolated static func stars(_ rating: Float) -> String {
        let shown = Int(rating.rounded(.up))
        let isHalf = Float(shown) != rating
        return "\(-16 * (5 - max(min(shown, 5), 0)))px \(isHalf ? -21 : -1)px"
    }

    /// The site's dates, in UTC: `2026-11-15 08:30`.
    private nonisolated static func date(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }

    private nonisolated static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
#endif
