import EhFeatures
import EhModels
import SwiftUI

/// Who made a gallery, as its title names them ("Mizuiro Atelier · Hoshino Kanae"), with a
/// search for each name and for the uploader. A title that names nobody gives the uploader.
nonisolated struct WallGalleryCredit: Equatable, Sendable {
    struct Target: Identifiable, Equatable, Sendable {
        let name: String
        let keyword: String
        let systemImage: String

        var id: String { keyword }
    }

    let text: String
    let targets: [Target]

    /// What the list already knew, without parsing anything: the page's first frame.
    init?(uploader: String?) {
        guard let uploader, !uploader.isEmpty else { return nil }
        text = uploader
        targets = [Self.uploaderTarget(uploader)]
    }

    private init(text: String, targets: [Target]) {
        self.text = text
        self.targets = targets
    }

    /// Parses the title, off the main actor. The circle and up to three artists, each
    /// searching its tag exactly when the gallery carries one of that name, otherwise the
    /// name in quotes; then the uploader, so that search stays one tap away.
    @concurrent
    static func make(title: String, tags: [GalleryTag], uploader: String?) async -> WallGalleryCredit? {
        let parsed = TitleParser.parse(title)
        var targets: [Target] = []
        if let circle = parsed.circle, !circle.isEmpty {
            targets.append(target(circle, namespace: .group, systemImage: "person.2", tags: tags))
        }
        for artist in parsed.artists.prefix(3) where !artist.isEmpty {
            targets.append(target(artist, namespace: .artist, systemImage: "paintbrush.pointed", tags: tags))
        }
        // A circle named after its one artist would otherwise appear twice.
        var seen = Set<String>()
        targets = targets.filter { seen.insert($0.keyword).inserted }
        guard !targets.isEmpty else { return WallGalleryCredit(uploader: uploader) }
        let text = targets.map(\.name).joined(separator: " · ")
        if let uploader, !uploader.isEmpty {
            targets.append(uploaderTarget(uploader))
        }
        return WallGalleryCredit(text: text, targets: targets)
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
    let model: GalleryDetailModel

    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(\.look) private var look
    @State private var parsed: WallGalleryCredit?
    @State private var searchCount = 0

    var body: some View {
        let tags = model.tagRows.isEmpty ? model.gallery.tags : model.tagRows.map(\.tag)
        let title = model.detail?.title ?? model.gallery.title
        Group {
            if let credit = parsed ?? WallGalleryCredit(uploader: model.uploader) {
                control(for: credit)
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: searchCount)
        // Again when the page's tags arrive: they decide between a tag and a quoted name.
        .task(id: WallCreditInput(title: title, tagCount: tags.count, uploader: model.uploader)) {
            let credit = await WallGalleryCredit.make(title: title, tags: tags, uploader: model.uploader)
            if !Task.isCancelled, credit != parsed {
                parsed = credit
            }
        }
    }

    @ViewBuilder
    private func control(for credit: WallGalleryCredit) -> some View {
        if credit.targets.count == 1, let target = credit.targets.first {
            Button {
                search(target)
            } label: {
                label(credit.text)
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
                label(credit.text)
            }
            .buttonStyle(.plain)
        }
    }

    private func label(_ text: String) -> some View {
        HStack(spacing: 3) {
            Text(verbatim: text)
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

nonisolated private struct WallCreditInput: Equatable, Sendable {
    let title: String
    let tagCount: Int
    let uploader: String?
}
