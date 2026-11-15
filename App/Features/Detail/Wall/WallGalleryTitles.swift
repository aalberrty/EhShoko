import EhFeatures
import EhModels
import SwiftUI

/// What the panel shows of a gallery's titles: the heading (the parsed title, without the
/// bracketed groups around it), who made it, and the other title as the site has it.
///
/// Worked out off the main actor whenever the titles or the tags change. Until then the
/// panel shows the title as the list had it and the uploader as the credit.
nonisolated struct WallGalleryTitles: Equatable, Sendable {
    /// What the titles are made from.
    nonisolated struct Input: Equatable, Sendable {
        /// The title the settings ask for: the Japanese one when preferred and present.
        let shown: String
        let title: String
        let japaneseTitle: String?
        let tags: [GalleryTag]
        let uploader: String?
    }

    let heading: String
    let credit: WallGalleryCredit?
    /// The full title the heading is not taken from, with all its groups ("(C103) [水色アトリエ
    /// (星野かなえ)] 夜明けの箱庭 …"); the full title itself when the gallery has only one.
    /// `nil` when it would repeat the heading.
    let other: String?
    /// The full titles, for the heading's Copy menu.
    let copyable: [String]

    /// Before parsing: the title as it is and the uploader.
    init(unparsed input: Input) {
        heading = input.shown
        credit = WallGalleryCredit(uploader: input.uploader)
        other = nil
        copyable = Self.copyable(input)
    }

    private init(heading: String, credit: WallGalleryCredit?, other: String?, copyable: [String]) {
        self.heading = heading
        self.credit = credit
        self.other = other
        self.copyable = copyable
    }

    @concurrent
    static func make(from input: Input) async -> WallGalleryTitles {
        let shown = TitleParser.parse(input.shown)
        let heading = shown.core.isEmpty ? input.shown : shown.core
        // The credit from the romanised title, whose names match the tags; from the Japanese
        // one when only it names anybody.
        var credit = WallGalleryCredit(parsed: TitleParser.parse(input.title), tags: input.tags, uploader: input.uploader)
        if credit == nil, let japanese = input.japaneseTitle, !japanese.isEmpty {
            credit = WallGalleryCredit(parsed: TitleParser.parse(japanese), tags: input.tags, uploader: input.uploader)
        }
        let full = input.shown == input.title ? input.japaneseTitle : input.title
        let other = [full, input.shown]
            .compactMap(\.self)
            .first { !$0.isEmpty && $0 != heading }
        return WallGalleryTitles(
            heading: heading, credit: credit ?? WallGalleryCredit(uploader: input.uploader), other: other,
            copyable: copyable(input)
        )
    }

    private static func copyable(_ input: Input) -> [String] {
        var titles = [input.title]
        if let japanese = input.japaneseTitle, !japanese.isEmpty, japanese != input.title {
            titles.append(japanese)
        }
        return titles
    }
}

/// Who made a gallery, as its title names them ("Mizuiro Atelier · Hoshino Kanae"), with a
/// search for each name and, last, for the uploader. A title that names nobody gives the
/// uploader alone, which keeps v3's uploader search one tap away.
nonisolated struct WallGalleryCredit: Equatable, Sendable {
    nonisolated struct Target: Identifiable, Equatable, Sendable {
        let name: String
        let keyword: String
        let systemImage: String

        var id: String { keyword }
    }

    let text: String
    let targets: [Target]

    init?(uploader: String?) {
        guard let uploader, !uploader.isEmpty else { return nil }
        text = uploader
        targets = [Self.uploaderTarget(uploader)]
    }

    /// The circle and up to three artists, each searching its tag exactly when the gallery
    /// carries one of that name, otherwise the name in quotes. `nil` when the title names
    /// nobody.
    init?(parsed: ParsedTitle, tags: [GalleryTag], uploader: String?) {
        var targets: [Target] = []
        if let circle = parsed.circle, !circle.isEmpty {
            targets.append(Self.target(circle, namespace: .group, systemImage: "person.2", tags: tags))
        }
        for artist in parsed.artists.prefix(3) where !artist.isEmpty {
            targets.append(Self.target(artist, namespace: .artist, systemImage: "paintbrush.pointed", tags: tags))
        }
        // A circle named after its one artist would otherwise appear twice.
        var seen = Set<String>()
        targets = targets.filter { seen.insert($0.keyword).inserted }
        guard !targets.isEmpty else { return nil }
        text = targets.map(\.name).joined(separator: " · ")
        if let uploader, !uploader.isEmpty {
            targets.append(Self.uploaderTarget(uploader))
        }
        self.targets = targets
    }

    private static func target(
        _ name: String, namespace: TagNamespace, systemImage: String, tags: [GalleryTag]
    ) -> Target {
        let lowered = name.lowercased()
        let match = tags.first { $0.namespace == namespace }.flatMap { tag in
            tag.contents.first { $0.text.lowercased() == lowered }.map { $0.searchKeyword(tag: tag) }
        }
        return Target(name: name, keyword: match ?? "\"\(name)\"", systemImage: systemImage)
    }

    private static func uploaderTarget(_ uploader: String) -> Target {
        Target(name: uploader, keyword: DetailSearchKeyword.uploader(uploader), systemImage: "person.crop.circle")
    }
}

/// The credit under the title: a tap searches it, through a menu when it names several.
struct WallGalleryCreditLine: View {
    let credit: WallGalleryCredit

    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(\.look) private var look
    @State private var searchCount = 0

    var body: some View {
        control
            .sensoryFeedback(.impact(flexibility: .soft), trigger: searchCount)
    }

    @ViewBuilder
    private var control: some View {
        if credit.targets.count == 1, let target = credit.targets.first {
            Button {
                search(target)
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                ForEach(credit.targets) { target in
                    Button {
                        search(target)
                    } label: {
                        Label(L10n.Localizable.List.Action.searchArtist(target.name), systemImage: target.systemImage)
                    }
                }
            } label: {
                label
            }
            .buttonStyle(.plain)
        }
    }

    private var label: some View {
        HStack(spacing: 3) {
            Text(verbatim: credit.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(look.label)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(look.tertiaryLabel)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }

    private func search(_ target: WallGalleryCredit.Target) {
        searchCount += 1
        stack?.push(.search(keyword: target.keyword))
    }
}
