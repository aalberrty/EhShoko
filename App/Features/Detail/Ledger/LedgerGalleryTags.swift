import EhCore
import EhDatabase
import EhFeatures
import EhModels
import SwiftUI

private typealias MenuTitles = L10n.Localizable.DetailView.ContextMenu.Button

/// The tags as text (`ledger.md` section 4): "TAGS · 58" with Vote trailing when signed in,
/// then one line per namespace, its name in small capitals in the namespace's hue and every
/// tag as wrapping text separated by middle dots. A namespace is one `TagText`, so 58 tags are
/// seven text layouts however many there are.
///
/// Each tag is a link: a tap searches it. Vote switches the links to open the tag's menu
/// (Vote up, Vote down or Withdraw vote, and Tag detail when the tag has one) until Vote is
/// tapped again. A long press on a namespace's line lists its tags that have a detail, signed
/// in or not, as the old app's long press on a tag offered it to everyone; a line is one
/// text, so the menu is the line's rather than one tag's.
struct LedgerGalleryTags: View {
    let model: GalleryDetailModel

    @Environment(SettingsStore.self) private var settings
    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(\.onTint) private var onTint
    @State private var isVoting = false
    @State private var menuChip: DetailTagChip?
    @State private var searchCount = 0

    var body: some View {
        let rows = model.tagRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                LedgerSectionHeading(title: L10n.Localizable.Gallery.Tags.count(rows.reduce(0) { $0 + $1.chips.count })) {
                    if model.isLoggedIn {
                        voteButton
                    }
                }
                .padding(.bottom, 6)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    LedgerRule()
                    LedgerTagLine(
                        row: row, rowIndex: index, translations: translations(of: row),
                        showsImages: settings.showsImagesInTags
                    )
                    .equatable()
                    .padding(.vertical, 8)
                    .contextMenu { detailMenu(for: row) }
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                guard let chip = LedgerTagLink.chip(for: url, in: rows) else { return .systemAction }
                open(chip)
                return .handled
            })
            .confirmationDialog(
                menuChip.map { chipText($0) } ?? "", isPresented: isMenuPresented, titleVisibility: .visible,
                presenting: menuChip
            ) { chip in
                menu(for: chip)
            }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: searchCount)
            .onChange(of: model.isLoggedIn) { _, isLoggedIn in
                if !isLoggedIn { isVoting = false }
            }
        }
    }

    private var voteButton: some View {
        Button {
            withAnimation(.snappy) { isVoting.toggle() }
        } label: {
            Text(L10n.Localizable.Gallery.Tags.vote)
                .fontWeight(isVoting ? .semibold : .regular)
                .foregroundStyle(isVoting ? AnyShapeStyle(onTint) : AnyShapeStyle(.tint))
                .padding(.horizontal, isVoting ? 10 : 0)
                .padding(.vertical, isVoting ? 3 : 0)
                .background {
                    if isVoting {
                        Capsule().fill(.tint)
                    }
                }
                .hitAreaOutset(HitArea.shortWord)
        }
        .buttonStyle(.plain)
        .hitAreaOutsetReturned(HitArea.shortWord)
        .accessibilityAddTraits(isVoting ? .isSelected : [])
    }

    private func open(_ chip: DetailTagChip) {
        if isVoting {
            menuChip = chip
        } else {
            searchCount += 1
            stack?.push(.search(keyword: chip.searchKeyword))
        }
    }

    private var isMenuPresented: Binding<Bool> {
        Binding(get: { menuChip != nil }, set: { if !$0 { menuChip = nil } })
    }

    /// v3's tag menu: withdraw a vote, or vote up or down; the tag's detail while tags are
    /// translated and its translation has one.
    @ViewBuilder
    private func menu(for chip: DetailTagChip) -> some View {
        if chip.hasVote {
            Button(MenuTitles.withdrawVote) { model.voteTag(chip, vote: chip.withdrawVote) }
        } else {
            Button(MenuTitles.voteUp) { model.voteTag(chip, vote: 1) }
            Button(MenuTitles.voteDown) { model.voteTag(chip, vote: -1) }
        }
        if settings.translatesTags, let detail = chip.detail {
            Button(MenuTitles.detail) { model.showTagDetail(detail) }
        }
    }

    /// The tag details of a namespace's tags, while tags are translated; empty, and so no
    /// menu, when none of them has one.
    @ViewBuilder
    private func detailMenu(for row: DetailTagRow) -> some View {
        if settings.translatesTags {
            let chips = row.chips.filter { $0.detail != nil }
            if !chips.isEmpty {
                Section(MenuTitles.detail) {
                    ForEach(chips) { chip in
                        if let detail = chip.detail {
                            Button(chipText(chip), systemImage: "doc.richtext") { model.showTagDetail(detail) }
                        }
                    }
                }
            }
        }
    }

    /// This row's translations, looked up synchronously; reading them observes the service.
    private func translations(of row: DetailTagRow) -> [String: TagTranslationDisplay] {
        guard settings.translatesTags else { return [:] }
        return row.chips.reduce(into: [:]) { result, chip in
            result[chip.translationKey] = model.translation(for: chip)
        }
    }

    private func chipText(_ chip: DetailTagChip) -> String {
        let translation = settings.translatesTags ? model.translation(for: chip) : nil
        return chip.content.chipText(translation: translation, showsImages: false)
    }
}

/// One namespace: its name and every tag, as one text.
private struct LedgerTagLine: View, Equatable {
    let row: DetailTagRow
    let rowIndex: Int
    /// Empty when tags are not translated.
    let translations: [String: TagTranslationDisplay]
    let showsImages: Bool

    var body: some View {
        TagText(
            namespace: row.tag.namespace?.localizedName ?? row.tag.rawNamespace,
            color: (row.tag.namespace ?? .other).markColor,
            tags: row.chips.enumerated().map { index, chip in
                TagText.Tag(
                    chip.content.chipText(translation: translations[chip.translationKey], showsImages: showsImages),
                    isWeak: chip.content.isWeak,
                    url: LedgerTagLink.url(row: rowIndex, chip: index)
                )
            }
        )
    }
}

/// The links inside the tag text: each names its row and its place in the row, so a tap
/// finds the tag without a lookup table.
private enum LedgerTagLink {
    static let scheme = "ledger-tag"

    static func url(row: Int, chip: Int) -> URL? {
        URL(string: "\(scheme):\(row).\(chip)")
    }

    static func chip(for url: URL, in rows: [DetailTagRow]) -> DetailTagChip? {
        guard url.scheme == scheme else { return nil }
        let parts = url.absoluteString.dropFirst(scheme.count + 1).split(separator: ".").compactMap { Int($0) }
        guard parts.count == 2, rows.indices.contains(parts[0]), rows[parts[0]].chips.indices.contains(parts[1])
        else { return nil }
        return rows[parts[0]].chips[parts[1]]
    }
}
