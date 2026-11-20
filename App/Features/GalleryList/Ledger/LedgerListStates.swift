import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// A search that found nothing (`ledger.md` section 3, `09-empty-results-light`): the query's
/// tags as chips, the Search filter in words, "No galleries match", and up to three ways to
/// loosen the search, each one tap. No counts are shown: each would be another search.
///
/// It takes the screen's place, not a row's, and scrolls when the text is large; nothing in it
/// is glass. Dropping the minimum rating or including every category changes the Search
/// filter and reloads the list; dropping a tag searches again without it.
struct LedgerLooseningState: View {
    let keyword: String
    let perform: (ListMenuAction) -> Void

    @Environment(FilterStore.self) private var filterStore
    @Environment(StackRouter.self) private var stack
    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @ScaledMetric(relativeTo: .largeTitle) private var circleSize: CGFloat = 72

    var body: some View {
        let filter = filterStore[.search]
        let terms = SearchTokens.split(keyword)
        ScrollView {
            VStack(spacing: 0) {
                chips(terms)
                Text(L10n.Localizable.List.Search.Empty.filters(FilterSummary(filter).longText))
                    .font(.footnote)
                    .foregroundStyle(look.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.top, Tokens.Spacing.small)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: circleSize * 0.4, weight: .medium))
                    .foregroundStyle(look.secondaryLabel)
                    .frame(width: circleSize, height: circleSize)
                    .background(look.fill3, in: .circle)
                    .padding(.top, Tokens.Spacing.xxLarge)
                    .accessibilityHidden(true)
                Text(L10n.Localizable.List.Search.Empty.title)
                    .font(.title2.bold())
                    .fontDesign(look.titleDesign)
                    .foregroundStyle(look.label)
                    .multilineTextAlignment(.center)
                    .padding(.top, Tokens.Spacing.large)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.Localizable.List.Search.Empty.body)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.top, Tokens.Spacing.small)
                ways(SearchLoosening.actions(for: keyword, filter: filter))
                    .padding(.top, Tokens.Spacing.large)
                Text(L10n.Localizable.List.Search.Empty.note)
                    .font(.footnote)
                    .foregroundStyle(look.tertiaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.top, Tokens.Spacing.large)
            }
            .padding(.horizontal, Tokens.Spacing.large)
            .padding(.vertical, Tokens.Spacing.medium)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background { look.background.ignoresSafeArea() }
    }

    @ViewBuilder
    private func chips(_ terms: SearchTokens) -> some View {
        let texts = terms.tokens.map(Self.chipText) + (terms.remainder.isEmpty ? [] : [terms.remainder])
        if !texts.isEmpty {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(texts, id: \.self) { text in
                    Text(verbatim: text)
                        .font(.footnote.weight(.medium))
                        .fontDesign(look.syntaxDesign)
                        .foregroundStyle(look.label)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .background(look.fill3, in: .capsule)
                }
            }
        }
    }

    private func ways(_ loosenings: [SearchLoosening]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(loosenings.enumerated()), id: \.element) { offset, loosening in
                Button { apply(loosening) } label: {
                    HStack(spacing: Tokens.Spacing.medium) {
                        Image(systemName: Self.symbol(of: loosening))
                            .foregroundStyle(tint)
                            .frame(width: 24)
                        Text(Self.title(of: loosening))
                            .foregroundStyle(look.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(look.tertiaryLabel)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) {
                    if offset > 0 {
                        look.separator.frame(height: 0.5).padding(.leading, 14)
                    }
                }
            }
        }
        .background(look.raised, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(look.separator, lineWidth: 0.5)
        }
    }

    /// The model says what loosening does; the view only goes where it says.
    private func apply(_ loosening: SearchLoosening) {
        switch loosening.perform(on: keyword, filterStore: filterStore) {
        case .reload:
            perform(.reload)
        case .search(let keyword):
            stack.push(.search(keyword: keyword))
        }
    }

    private static func chipText(_ token: SearchToken) -> String {
        let tag = token.namespace.map { $0 + ": " + token.tag } ?? token.tag
        return token.isExcluded ? "-" + tag : tag
    }

    private static func title(of loosening: SearchLoosening) -> String {
        switch loosening {
        case .dropMinimumRating(let rating): L10n.Localizable.List.Search.Loosen.rating(rating)
        case .includeAllCategories: L10n.Localizable.List.Search.Loosen.categories(FilterSummary.categoryCount)
        case .dropTag(let token): L10n.Localizable.List.Search.Loosen.term(chipText(token))
        }
    }

    private static func symbol(of loosening: SearchLoosening) -> String {
        switch loosening {
        case .dropMinimumRating: "star.slash"
        case .includeAllCategories: "square.grid.2x2"
        case .dropTag: "tag.slash"
        }
    }
}

/// A list that a first screen or the library embeds under its header keeps its header when it
/// has nothing to show, so its state is a row under the header rather than the whole screen,
/// and inside a scroll view nothing may be glass: the same states as the full-screen ones,
/// with plain buttons.
struct LedgerInlineState: View {
    let phase: ListFeed.Phase
    let feed: ListFeed
    /// Opens Filters; `nil` when the filter is the default or the list has none.
    let filters: (() -> Void)?

    @Environment(AppRouter.self) private var appRouter
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: Tokens.Spacing.small) {
            Image(systemName: symbol)
                .font(.title.weight(.medium))
                .foregroundStyle(look.tertiaryLabel)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .fontDesign(look.titleDesign)
                .foregroundStyle(look.label)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
            }
            action
                .buttonStyle(.borderless)
                .fontWeight(.semibold)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Spacing.xxLarge)
        .padding(.horizontal, Tokens.Spacing.large)
    }

    @ViewBuilder
    private var action: some View {
        switch phase {
        case .signedOut:
            Button(L10n.Localizable.NotLoginView.Button.login) {
                appRouter.presentSignIn()
            }
        case .failed(let error) where error.isRetryable:
            Button(L10n.Localizable.ErrorView.Button.retry) { feed.retry() }
        case .empty:
            if let filters {
                Button(L10n.Localizable.ToolbarItem.Button.filters, action: filters)
            }
        default:
            EmptyView()
        }
    }

    private var symbol: String {
        switch phase {
        case .signedOut(let kind): kind == .watched ? "eye" : "heart"
        case .failed(let error): error.symbol.rawValue
        default: "square.stack.3d.up.slash"
        }
    }

    private var title: String {
        switch phase {
        case .signedOut(.watched): L10n.Localizable.List.Signin.Watched.title
        case .signedOut(.favorites): L10n.Localizable.List.Signin.Favorites.title
        case .failed(let error): error.headline ?? error.alertText
        default: L10n.Localizable.List.Empty.ledger
        }
    }

    private var message: String? {
        switch phase {
        case .failed(let error) where error.headline != nil: error.alertText
        default: nil
        }
    }
}
