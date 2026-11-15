import EhFeatures
import EhModels
import SwiftUI

private typealias Titles = L10n.Localizable.DetailView.ContextMenu.Button

/// Tag detail (`ledger.md` section 4, child screens): a sheet at the medium detent with the
/// namespace in small capitals, the translated name in the title face, the description and
/// images, then the actions as rows: search the tag, vote (signed in), and the translation's
/// links.
struct LedgerTagDetailSheet: View {
    let detail: TagDetail
    let model: GalleryDetailModel

    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look

    var body: some View {
        let chip = self.chip
        NavigationStack {
            List {
                Section {
                    header(chip)
                        .listRowSeparator(.hidden)
                    if !detail.imageURLs.isEmpty {
                        images
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                .listRowBackground(Color.clear)
                if let chip {
                    Section {
                        actions(chip)
                    }
                    .listRowBackground(Color.clear)
                }
                if !detail.links.isEmpty {
                    Section {
                        ForEach(detail.links, id: \.self) { url in
                            Link(destination: url) {
                                Label(url.absoluteString, systemImage: "link")
                                    .lineLimit(2)
                            }
                        }
                    } header: {
                        Text(L10n.Localizable.TagDetailView.Section.Title.links)
                            .ledgerSmallCaps()
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            // The rows sit on the sheet's glass.
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The tag the sheet is about: the one on the page whose translation this is.
    private var chip: DetailTagChip? {
        model.tagRows.lazy.flatMap(\.chips).first { $0.detail == detail }
    }

    private func header(_ chip: DetailTagChip?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let namespace = chip?.content.rawNamespace {
                let tagNamespace = TagNamespace(rawValue: namespace)
                Text(tagNamespace?.localizedName ?? namespace)
                    .ledgerSmallCaps(tagNamespace?.markColor)
            }
            Text(detail.title.removingEmojiPresentation)
                .font(.title2.bold())
                .fontDesign(look.titleDesign)
                .foregroundStyle(look.label)
                .accessibilityAddTraits(.isHeader)
            if !detail.description.isEmpty {
                Text(detail.description)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var images: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(detail.imageURLs, id: \.self) { url in
                    RemoteImage(url: url, size: CGSize(width: 110, height: 110 / Tokens.Aspect.preview), cornerRadius: 4)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .frame(height: 110 / Tokens.Aspect.preview)
    }

    @ViewBuilder
    private func actions(_ chip: DetailTagChip) -> some View {
        row(L10n.Localizable.SearchView.Title.search, systemImage: "magnifyingglass") {
            dismiss()
            stack?.push(.search(keyword: chip.searchKeyword))
        }
        if model.isLoggedIn {
            if chip.hasVote {
                row(Titles.withdrawVote, systemImage: chip.content.isVotedUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill") {
                    model.voteTag(chip, vote: chip.withdrawVote)
                }
            } else {
                row(Titles.voteUp, systemImage: "hand.thumbsup") { model.voteTag(chip, vote: 1) }
                row(Titles.voteDown, systemImage: "hand.thumbsdown") { model.voteTag(chip, vote: -1) }
            }
        }
    }

    private func row(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(look.label)
        }
    }
}
