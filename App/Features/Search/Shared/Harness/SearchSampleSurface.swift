#if DEBUG || HARNESS
import EhFeatures
import SwiftUI

/// A plain search surface built only from the shared layer, shown in place of the chosen
/// design with the launch argument `-HarnessSearchSample YES`, so the field, its bar and its
/// presentation can be tried under both bars before the three designs exist. It is also the
/// example for them: a design composes these pieces its own way.
///
/// `-HarnessSearchKeys YES` adds a row of keys on top of the keyboard, as Ledger's.
struct SearchSampleSurface: View {
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "HarnessSearchSample") }
    private static var showsKeys: Bool { UserDefaults.standard.bool(forKey: "HarnessSearchKeys") }

    let model: SearchSurfaceModel

    @Environment(\.look) private var look

    var body: some View {
        SearchSampleList(model: model)
            .background(look.background)
            .navigationTitle(L10n.Localizable.SearchView.Title.search)
            .navigationBarTitleDisplayMode(.inline)
            .searchFieldBar {
                SearchFieldCapsule {
                    SearchScopeMenu(model: model)
                } field: {
                    if Self.showsKeys {
                        TagSearchField(model: model, prompt: model.scope.localizedPrompt, tokenStyle: .tint) {
                            SearchSampleKeys()
                        }
                    } else {
                        TagSearchField(model: model, prompt: model.scope.localizedPrompt, tokenStyle: .tint)
                    }
                }
                SearchFiltersButton(model: model)
            }
    }
}

/// Reads the suggestions; the first row alone reads the text.
private struct SearchSampleList: View {
    let model: SearchSurfaceModel

    @Environment(\.searchFieldController) private var field

    var body: some View {
        let rows = TagSuggestionRowContent.rows(for: model.suggestions.suggestions)
        List {
            SearchTitlesButton(model: model)
            if rows.isEmpty {
                SearchSampleIdle(model: model)
            } else {
                Section(L10n.Localizable.Search.Group.tags) {
                    ForEach(rows) { row in
                        Button { field.accept(row.item) } label: { SearchSampleRow(row: row) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

/// Before anything is typed: the copied link, quick searches and recent searches.
private struct SearchSampleIdle: View {
    let model: SearchSurfaceModel

    @Environment(\.searchFieldController) private var field

    var body: some View {
        if model.hasLinkOffer {
            Button(L10n.Localizable.Search.Link.title, systemImage: "link") { field.openCopiedLink() }
        }
        let quick = model.root.quickSearchKeywords
        if !quick.isEmpty {
            Section(L10n.Localizable.SearchView.Section.Title.quickSearch) {
                ForEach(quick, id: \.self) { keyword in
                    Button(keyword.title) { field.search(keyword.keyword) }
                        .lookSyntaxDesign()
                }
            }
        }
        let recent = model.root.historySearchKeywords
        if !recent.isEmpty {
            Section(L10n.Localizable.Search.Group.recent) {
                ForEach(recent, id: \.self) { keyword in
                    Button(keyword.title) { field.use(keyword.keyword) }
                        .lookSyntaxDesign()
                }
                .onDelete { offsets in
                    let keywords = offsets.map { recent[$0].keyword }
                    Task { for keyword in keywords { await model.removeRecentSearch(keyword) } }
                }
            }
        }
    }
}

private struct SearchSampleRow: View {
    let row: TagSuggestionRowContent

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: row.namespace.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.namespace.markColor)
                .frame(width: 72, alignment: .trailing)
            Text(row.tag)
                .foregroundStyle(look.label)
            Spacer(minLength: 8)
            Text(row.translation)
                .font(.subheadline)
                .foregroundStyle(look.secondaryLabel)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// Keys that insert at the caret, each its own glass capsule on a clear row, as Ledger's.
private struct SearchSampleKeys: View {
    private static let keys = ["artist:", "female:", "male:", "parody:", "group:", "character:", "-", "$"]

    @Environment(\.searchFieldController) private var field

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Self.keys, id: \.self) { key in
                    Button { field.insert(key) } label: {
                        Text(verbatim: key)
                            .font(.system(.callout, design: .monospaced))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassSurface(in: .capsule, isInteractive: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }
}
#endif
