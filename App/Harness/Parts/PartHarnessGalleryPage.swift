#if DEBUG || HARNESS
import EhModels
import Foundation

/// A gallery page as the site sends it, made from the page the harness stored, so that the
/// fetch a gallery page makes after a favourite was added or removed is answered with the
/// page as it now is. It has what the real parser reads: the titles, the info table, the
/// rating, the favourite link, the tags, the archive and torrent links, the previews (without
/// viewer links, so the reader asks for no image page), the comments and the API key.
nonisolated enum PartHarnessGalleryPage {
    struct Stored: Sendable {
        let detail: GalleryDetail
        let tags: [GalleryTag]
        let comments: [GalleryComment]
        let previewURLs: [Int: URL]
        /// The folder's name when the gallery is a favourite, else `nil`.
        let favoriteFolder: String?
    }

    static func html(_ page: Stored) -> String {
        let detail = page.detail
        var html = "<html><head><title>\(escape(detail.title))</title></head><body>"
        html += "<div class=\"gm\">"
        html += "<div id=\"gleft\"><div id=\"gd1\"><div style=\"width:250px; height:354px; background:transparent url(\(detail.coverURL?.absoluteString ?? "https://ehgt.org/g/blank.gif")) 0 0 no-repeat\"></div></div></div>"
        html += "<div id=\"gd2\"><h1 id=\"gn\">\(escape(detail.title))</h1><h1 id=\"gj\">\(escape(detail.jpnTitle ?? ""))</h1></div>"
        html += "<div id=\"gmid\"><div id=\"gd3\">"
        html += "<div id=\"gdc\"><div class=\"cs\">\(detail.category.rawValue)</div></div>"
        html += "<div id=\"gdn\"><a href=\"https://e-hentai.org/uploader/\(escape(detail.uploader))\">\(escape(detail.uploader))</a></div>"
        html += infoTable(detail) + rating(detail) + favoriteLink(page.favoriteFolder)
        html += "</div>" + tagList(page.tags) + links(detail) + "</div></div>"
        html += previews(page.previewURLs, pageCount: detail.pageCount)
        html += comments(page.comments)
        html += "<script type=\"text/javascript\">\nvar gid = \(detail.gid);\nvar apikey = \"0123456789abcdef01\";\nvar average_rating = \(detail.rating);\n</script>"
        return html + "</body></html>"
    }

    private static func infoTable(_ detail: GalleryDetail) -> String {
        let visible = switch detail.visibility {
        case .yes: "Yes"
        case .no(let reason): "No (\(escape(reason)))"
        }
        let parent = detail.parentURL.map { "<a href=\"\($0.absoluteString)\">\($0.lastPathComponent)</a>" } ?? "None"
        let rows = [
            ("Posted:", format(detail.postedDate, as: "yyyy-MM-dd HH:mm")),
            ("Parent:", parent),
            ("Visible:", visible),
            ("Language:", "\(detail.language.rawValue) &nbsp;"),
            ("File Size:", "\(detail.sizeCount) \(siteUnit(detail.sizeType))"),
            ("Length:", "\(detail.pageCount) pages"),
            ("Favorited:", "\(detail.favoritedCount) times"),
        ]
        return "<div id=\"gdd\"><table>"
            + rows.map { "<tr><td class=\"gdt1\">\($0.0)</td><td class=\"gdt2\">\($0.1)</td></tr>" }.joined()
            + "</table></div>"
    }

    /// The site writes binary units; a stored page made by the harness may say `MB`.
    private static func siteUnit(_ unit: String) -> String {
        switch unit {
        case "KB": "KiB"
        case "MB": "MiB"
        case "GB": "GiB"
        default: unit
        }
    }

    /// The stars show the user's own rating when there is one (a class other than `ir`), else
    /// the average; the label always gives the average.
    private static func rating(_ detail: GalleryDetail) -> String {
        let isOwn = detail.userRating > 0
        let stars = isOwn ? detail.userRating : detail.rating
        return "<div id=\"gdr\"><table><tr><td id=\"grt2\"><div id=\"rating_image\" class=\"\(isOwn ? "ir irb" : "ir")\" style=\"background-position:\(starOffsets(stars))\"></div></td>"
            + "<td id=\"grt3\"><span id=\"rating_count\">\(detail.ratingCount)</span></td></tr>"
            + "<tr><td id=\"rating_label\" colspan=\"3\">Average: \(String(format: "%.2f", detail.rating))</td></tr></table></div>"
    }

    private static func favoriteLink(_ folder: String?) -> String {
        "<div id=\"gdf\"><div style=\"float:left\">&nbsp; <a id=\"favoritelink\" href=\"#\">\(folder.map(escape) ?? "Add to Favorites")</a></div></div>"
    }

    private static func tagList(_ tags: [GalleryTag]) -> String {
        var html = "<div id=\"gd4\"><div id=\"taglist\"><table>"
        for tag in tags {
            html += "<tr><td class=\"tc\">\(escape(tag.rawNamespace)):</td><td>"
            for content in tag.contents {
                let vote = content.isVotedUp ? "tup" : content.isVotedDown ? "tdn" : ""
                html += "<div class=\"\(content.isWeak ? "gtl" : "gt")\"><a class=\"\(vote)\" href=\"#\">\(escape(content.text))</a></div>"
            }
            html += "</td></tr>"
        }
        return html + "</table></div></div>"
    }

    private static func links(_ detail: GalleryDetail) -> String {
        var html = "<div id=\"gd5\">"
        if let archiveURL = detail.archiveURL {
            html += "<p class=\"g2 gsp\"><a href=\"#\" onclick=\"return popUp('\(escape(archiveURL.absoluteString))',480,320)\">Archive Download</a></p>"
        }
        html += "<p class=\"g2\"><a href=\"#\">Torrent Download (\(detail.torrentCount))</a></p>"
        return html + "</div>"
    }

    private static func previews(_ urls: [Int: URL], pageCount: Int) -> String {
        let pages = urls.keys.sorted()
        var html = "<p class=\"gpc\">Showing 1 - \(pages.count) of \(pageCount) images</p><div id=\"gdt\" class=\"gt100\">"
        for page in pages {
            guard let url = urls[page] else { continue }
            html += "<a><div title=\"Page \(page): \(page).jpg\" style=\"background:transparent url(\(url.absoluteString)) 0 0 no-repeat\"></div></a>"
        }
        return html + "</div>"
    }

    private static func comments(_ comments: [GalleryComment]) -> String {
        var html = "<div id=\"cdiv\" class=\"gm\">"
        for comment in comments {
            html += "<div class=\"c1\"><div class=\"c2\">"
            html += "<div class=\"c3\">Posted on \(format(comment.commentDate, as: "dd MMMM yyyy, HH:mm")) by: &nbsp; \(escape(comment.author))</div>"
            html += controls(comment)
            if let score = comment.score {
                html += "<div class=\"c5 nosel\"><span>\(escape(score))</span></div>"
            }
            let text = comment.contents.compactMap(\.text).joined()
            html += "</div><div class=\"c6\" id=\"comment_\(comment.commentID)\">\(escape(text).replacingOccurrences(of: "\n", with: "<br>"))</div></div>"
        }
        return html + "</div>"
    }

    private static func controls(_ comment: GalleryComment) -> String {
        guard comment.votable || comment.editable else { return "" }
        var html = "<div class=\"c4 nosel\">"
        if comment.votable {
            let id = comment.commentID
            html += "[<a id=\"comment_vote_up_\(id)\" style=\"\(comment.votedUp ? "color:blue" : "")\" href=\"#\">Vote+</a>] "
            html += "[<a id=\"comment_vote_down_\(id)\" style=\"\(comment.votedDown ? "color:blue" : "")\" href=\"#\">Vote-</a>]"
        }
        if comment.editable {
            html += "[<a href=\"#\" onclick=\"edit_comment(\(comment.commentID))\">Edit</a>]"
        }
        return html + "</div>"
    }

    /// The sprite offsets of the stars image, as on a list row.
    private static func starOffsets(_ rating: Float) -> String {
        let shown = Int(rating.rounded(.up))
        let isHalf = Float(shown) != rating
        return "\(-16 * (5 - max(min(shown, 5), 0)))px \(isHalf ? -21 : -1)px"
    }

    /// The site's dates are in UTC.
    private static func format(_ date: Date, as format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
#endif
