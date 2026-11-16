import EhFeatures
import EhModels
import UIKit

extension SearchToken {
    /// The site's namespace the token's prefix names (`f` and `female` both name Female), or
    /// `nil` for a tag without one or a prefix the site does not have as a namespace.
    var tagNamespace: TagNamespace? {
        guard let written = namespace.map(Self.withoutAlternativeMark) else { return nil }
        return TagNamespace.allCases.first { namespace in
            namespace.rawValue.caseInsensitiveCompare(written) == .orderedSame
                || namespace.abbreviation?.caseInsensitiveCompare(written) == .orderedSame
        }
    }

    /// A `~` term: one of several tags any of which may match.
    var isAlternative: Bool { term.hasPrefix("~") }

    /// "female:glasses", as the field shows the token: the namespace written out, the tag
    /// without quotes or `$`. The exclude mark is the token's icon, so it is not in the text.
    var displayText: String {
        let tag = namespace == nil ? Self.withoutAlternativeMark(tag) : tag
        let prefix = isAlternative ? "~" : ""
        guard let namespace else { return prefix + tag }
        let name = tagNamespace?.rawValue ?? Self.withoutAlternativeMark(namespace)
        return prefix + name + ":" + tag
    }

    /// "Female glasses", "Not female glasses": what VoiceOver says for the token, the
    /// namespace in the user's language.
    var spokenText: String {
        let tag = namespace == nil ? Self.withoutAlternativeMark(tag) : tag
        let name = tagNamespace?.localizedName ?? namespace.map(Self.withoutAlternativeMark)
        let words = [name, tag].compactMap(\.self).joined(separator: " ")
        return isExcluded ? L10n.Localizable.Search.Token.excluded(words) : words
    }

    /// The token the field draws for this term; it carries the term back as its represented
    /// object.
    func makeFieldToken() -> UISearchToken {
        let icon = isExcluded ? UIImage(systemName: "minus.circle") : nil
        let token = UISearchToken(icon: icon, text: displayText)
        token.representedObject = self
        return token
    }

    private static func withoutAlternativeMark(_ text: String) -> String {
        text.hasPrefix("~") ? String(text.dropFirst()) : text
    }
}

extension UISearchToken {
    /// The term this token stands for, when the field made it.
    var searchToken: SearchToken? { representedObject as? SearchToken }
}
