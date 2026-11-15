import EhFeatures
import EhModels
import SwiftUI

// The rows of Ledger's search list. Each takes a value worked out by its group, so its body
// formats nothing, and each is one element for VoiceOver.

/// A tag: the namespace in small capitals in its colour in a 74 pt column, the tag with the
/// typed part bold, and its translated name trailing. At accessibility sizes the namespace goes
/// above the tag, so the words keep the row's width.
struct LedgerTagSuggestionRow: View {
    let row: TagSuggestionRowContent

    @ScaledMetric(relativeTo: .caption2) private var column: CGFloat = 74
    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    namespace
                    words
                }
                .padding(.vertical, 6)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    namespace.frame(width: column, alignment: .leading)
                    words
                }
            }
        }
        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var namespace: some View {
        Text(verbatim: row.namespace.rawValue)
            .ledgerSmallCaps(row.namespace.markColor)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    private var words: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.tag)
                .foregroundStyle(look.label)
                .layoutPriority(1)
            Spacer(minLength: 0)
            // The dictionary has no name for the tag: the row would say it twice.
            if !row.translation.characters.elementsEqual(row.tag.characters) {
                Text(row.translation)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
            }
        }
    }
}

/// A saved or recent search as its row shows it: the words with the typed part bold, and a
/// saved search's name when it has one.
nonisolated struct LedgerSearchWord: Identifiable, Equatable, Sendable {
    let word: SearchKeyword
    let text: AttributedString
    let name: AttributedString?

    var id: SearchKeyword { word }
    var keyword: String { word.keyword }

    init(saved word: SearchKeyword, typed: String) {
        self.word = word
        text = Self.bolding(word.keyword, typed)
        name = word.title == word.keyword ? nil : Self.bolding(word.title, typed)
    }

    init(recent keyword: String, typed: String) {
        word = SearchKeyword(keyword: keyword, title: keyword)
        text = Self.bolding(keyword, typed)
        name = nil
    }

    /// `string` with the first part that matches `typed`, ignoring case, bold.
    private static func bolding(_ string: String, _ typed: String) -> AttributedString {
        var text = AttributedString(string)
        if !typed.isEmpty, let range = text.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }
}

/// A saved search (a bookmark, the words in the face the look gives search syntax, its name
/// trailing) or a recent one (a clock and the words), 44 pt high.
struct LedgerSearchWordRow: View {
    enum Kind { case saved, recent }

    let word: LedgerSearchWord
    let kind: Kind

    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: kind == .saved ? "bookmark" : "clock.arrow.circlepath")
                .font(.subheadline)
                .foregroundStyle(look.secondaryLabel)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                .accessibilityHidden(true)
            words
                .foregroundStyle(look.label)
                .truncationMode(.middle)
                .layoutPriority(1)
            if let name = word.name {
                Spacer(minLength: 8)
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
            }
        }
        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var words: some View {
        switch kind {
        case .saved: Text(word.text).font(.subheadline).lookSyntaxDesign()
        case .recent: Text(word.text)
        }
    }
}

/// A gallery in "Recently viewed": what its row shows, worked out once by the group.
nonisolated struct LedgerSeenGallery: Identifiable, Equatable {
    let gallery: Gallery
    let category: String
    let categoryColor: Color
    let title: String

    var id: String { gallery.gid }

    @MainActor
    init(_ gallery: Gallery) {
        self.gallery = gallery
        category = gallery.category.localizedName
        categoryColor = gallery.category.markColor
        title = gallery.trimmedTitle
    }
}

/// A cover 34 pt wide, the category in small capitals in its colour and the title in the
/// look's title face, on two lines.
struct LedgerSeenGalleryRow: View {
    let row: LedgerSeenGallery

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: row.gallery.coverURL, size: CGSize(width: 34, height: 49), cornerRadius: 5)
                .zoomSource(row.gallery.gid)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.category)
                    .ledgerSmallCaps(row.categoryColor)
                    .lineLimit(1)
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .lookTitleDesign()
                    .foregroundStyle(look.label)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue(row.category)
    }
}
