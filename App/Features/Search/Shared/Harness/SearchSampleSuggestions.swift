#if DEBUG || HARNESS
import Dependencies
import EhFeatures
import EhModels
import Foundation

/// A dozen real tags as a suggestion source, for trying suggestions where no dictionary is
/// installed (the part harness): `-HarnessSearchSuggestions YES`. Suggestions also need the
/// tags extension and its suggestion setting, which launch arguments can turn on:
/// `-settings.enablesTagsExtension '<true/>' -settings.showsTagsSearchSuggestion '<true/>'`.
nonisolated enum SearchSampleSuggestions {
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "HarnessSearchSuggestions") }

    /// The surface's model, on the fixture source when it is asked for.
    @MainActor
    static func model(scope: SearchScope) -> SearchSurfaceModel {
        guard isRequested else { return SearchSurfaceModel(scope: scope) }
        return withDependencies {
            $0.tagSuggestionSource = source
        } operation: {
            SearchSurfaceModel(scope: scope)
        }
    }

    private static let tags: [TagTranslation] = [
        TagTranslation(namespace: .female, key: "glasses", value: "眼镜"),
        TagTranslation(namespace: .male, key: "glasses", value: "眼镜"),
        TagTranslation(namespace: .female, key: "big breasts", value: "巨乳"),
        TagTranslation(namespace: .female, key: "kimono", value: "和服"),
        TagTranslation(namespace: .female, key: "stockings", value: "长筒袜"),
        TagTranslation(namespace: .female, key: "swimsuit", value: "泳装"),
        TagTranslation(namespace: .artist, key: "hoshino kanae", value: "星野かなえ"),
        TagTranslation(namespace: .language, key: "chinese", value: "汉语"),
        TagTranslation(namespace: .language, key: "english", value: "英语"),
        TagTranslation(namespace: .parody, key: "touhou project", value: "东方Project"),
        TagTranslation(namespace: .character, key: "reimu hakurei", value: "博丽灵梦"),
        TagTranslation(namespace: .group, key: "summer gang", value: "夏日团")
    ]

    private static let source = TagSuggestionSource(
        hasTranslations: { true },
        suggestions: { text, limit in
            let found = suggestions(for: text)
            let items = found.prefix(limit).map {
                SearchTagSuggestion(suggestion: $0, displayValue: $0.tag.value, imageURL: nil)
            }
            return TagSuggestionResults(items: Array(items), matchCount: found.count)
        }
    )

    /// Tags whose key or name contains the last word, its namespace prefix respected.
    private static func suggestions(for text: String) -> [TagSuggestion] {
        guard let word = text.split(separator: " ").last.map(String.init), !word.isEmpty else { return [] }
        var namespace: TagNamespace?
        var term = word
        if let colon = word.firstIndex(of: ":") {
            let prefix = word[..<colon]
            namespace = TagNamespace.allCases.first {
                $0.rawValue.caseInsensitiveCompare(prefix) == .orderedSame
                    || $0.abbreviation?.caseInsensitiveCompare(prefix) == .orderedSame
            }
            term = String(word[word.index(after: colon)...])
        }
        return tags.compactMap { tag in
            guard namespace == nil || tag.namespace == namespace else { return nil }
            let keyRange = term.isEmpty ? nil : tag.key.range(of: term, options: .caseInsensitive)
            let valueRange = term.isEmpty ? nil : tag.value.range(of: term, options: .caseInsensitive)
            guard term.isEmpty || keyRange != nil || valueRange != nil else { return nil }
            return TagSuggestion(
                tag: tag, weight: 1, keyRange: keyRange, valueRange: valueRange,
                originalKeyword: word, matchesNamespace: namespace != nil
            )
        }
    }
}
#endif
