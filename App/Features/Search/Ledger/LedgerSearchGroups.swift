import EhFeatures
import EhModels
import SwiftUI

// The groups of Ledger's search (`ledger.md` section 6). Each is absent when it has nothing
// to show. While typing: Tags, Saved and Recent; before typing: Saved, Recent and Recently
// viewed. A tapped saved or recent search is searched at once, as the old app did.

/// "Tags": the suggestions for the word at the caret. Choosing one turns that word into its
/// token. Suggestions come only with the tags extension, its suggestion setting and a
/// dictionary, as before.
struct LedgerTagSuggestions: View {
    let model: SearchSurfaceModel

    @Environment(\.searchFieldController) private var field

    var body: some View {
        let rows = TagSuggestionRowContent.rows(for: model.suggestions.suggestions)
        if !rows.isEmpty {
            LedgerSearchHeading(title: L10n.Localizable.Search.Group.tags)
            ForEach(rows) { row in
                Button { field.accept(row.item) } label: {
                    LedgerTagSuggestionRow(row: row)
                }
                .ledgerSearchRow(separator: .row(isLast: row.id == rows.last?.id))
            }
        }
    }
}

/// The groups that follow what is typed: Saved and Recent narrow to the searches that contain
/// it, with that part bold, and Recently viewed shows only before anything is typed.
///
/// The one view of Ledger's search that reads `model.text` (`spikes/S6.md` section 9): a
/// keystroke re-evaluates this body, which only filters two short lists (the app keeps twenty
/// recent searches at most), and the rows it hands down are values, so a row whose words did
/// not change is not drawn again. The screen around it never reads the text.
struct LedgerSearchTypedGroups: View {
    let model: SearchSurfaceModel

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let typed = model.text.trimmingCharacters(in: .whitespaces)
        let saved = model.matchingQuickSearches.map { LedgerSearchWord(saved: $0, typed: typed) }
        // Ten, or twenty on regular width, as the old app showed.
        let recent = model.matchingRecentSearches
            .prefix(sizeClass == .regular ? 20 : 10)
            .map { LedgerSearchWord(recent: $0, typed: typed) }
        LedgerSavedSearches(words: saved)
        LedgerRecentSearches(model: model, words: recent)
        if typed.isEmpty {
            let seen = model.root.recentGalleries
            LedgerRecentlySeen(rows: seen.map(LedgerSeenGallery.init))
            if saved.isEmpty, recent.isEmpty, seen.isEmpty {
                LedgerSearchHint()
            }
        }
    }
}

/// "Saved": quick searches, in the face the look gives search syntax.
private struct LedgerSavedSearches: View {
    let words: [LedgerSearchWord]

    @Environment(\.searchFieldController) private var field

    var body: some View {
        if !words.isEmpty {
            LedgerSearchHeading(title: L10n.Localizable.Search.Group.saved)
            ForEach(words) { word in
                Button { field.search(word.keyword) } label: {
                    LedgerSearchWordRow(word: word, kind: .saved)
                }
                .ledgerSearchRow(separator: .row(isLast: word.id == words.last?.id))
            }
        }
    }
}

/// "Recent" with Clear: the searches made from the field, newest first. A row can be swiped
/// away.
private struct LedgerRecentSearches: View {
    let model: SearchSurfaceModel
    let words: [LedgerSearchWord]

    @Environment(\.searchFieldController) private var field

    var body: some View {
        if !words.isEmpty {
            LedgerSearchHeading(title: L10n.Localizable.Search.Group.recent) {
                Button(L10n.Localizable.ConfirmationDialog.Button.clear) {
                    Task { await model.clearRecentSearches() }
                }
            }
            ForEach(words) { word in
                Button { field.search(word.keyword) } label: {
                    LedgerSearchWordRow(word: word, kind: .recent)
                }
                .ledgerSearchRow(separator: .row(isLast: word.id == words.last?.id))
            }
            .onDelete { offsets in
                let removed = offsets.map { words[$0].keyword }
                Task {
                    for keyword in removed {
                        await model.removeRecentSearch(keyword)
                    }
                }
            }
        }
    }
}

/// "Recently viewed" as rows: the last galleries opened, each with a small cover it zooms out
/// of.
private struct LedgerRecentlySeen: View {
    let rows: [LedgerSeenGallery]

    @Environment(\.openGallery) private var openGallery

    var body: some View {
        if !rows.isEmpty {
            LedgerSearchHeading(title: L10n.Localizable.SearchView.Section.Title.recentlySeen)
            ForEach(rows) { row in
                Button { openGallery(row.gallery, from: .recentlySeen) } label: {
                    LedgerSeenGalleryRow(row: row)
                }
                .ledgerSearchRow(separator: .row(isLast: row.id == rows.last?.id))
            }
        }
    }
}

/// With no saved search, no recent search and nothing viewed: one line saying what the field
/// takes.
private struct LedgerSearchHint: View {
    @Environment(\.look) private var look

    var body: some View {
        Text(L10n.Localizable.Search.hint)
            .font(.subheadline)
            .foregroundStyle(look.secondaryLabel)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .ledgerSearchRow()
    }
}
