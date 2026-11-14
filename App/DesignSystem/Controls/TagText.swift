import EhModels
import SwiftUI

/// One namespace of a gallery's tags as text: the namespace's name in its hue in a fixed
/// column, then every tag as wrapping text separated by middle dots (Ledger's tag table,
/// `ledger.md` section 4). It is one text layout, however many tags it holds.
///
/// Under the Ledger look the name is set in small capitals; under Shelf and Wall in 12 pt
/// semibold, right-aligned, as their gallery pages label namespaces. Each tag with a `url` is a
/// link: the screen decides what it does through `\.openURL`. Weak tags (the site's dashed
/// ones) have a dashed underline and the secondary colour.
struct TagText: View {
    struct Tag: Hashable, Sendable {
        let text: String
        let isWeak: Bool
        let url: URL?

        init(_ text: String, isWeak: Bool = false, url: URL? = nil) {
            self.text = text
            self.isWeak = isWeak
            self.url = url
        }
    }

    private let namespace: String
    private let color: Color
    private let tags: [Tag]
    @Environment(\.look) private var look

    init(namespace: String, color: Color, tags: [Tag]) {
        self.namespace = namespace
        self.color = color
        self.tags = tags
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.medium) {
            namespaceLabel
            Text(tagLine)
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(look.label)
                // Links take the tint; tags read as text in the label colour.
                .tint(look.label)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var namespaceLabel: some View {
        let text = Text(namespace).foregroundStyle(color).lineLimit(1)
        switch look {
        case .ledger:
            text
                .font(.caption2.bold())
                .tracking(0.8)
                .textCase(.uppercase)
                .frame(width: 74, alignment: .leading)
        case .shelf, .wall:
            text
                .font(.caption.weight(.semibold))
                .frame(width: 72, alignment: .trailing)
        }
    }

    private var tagLine: AttributedString {
        var line = AttributedString()
        for (index, tag) in tags.enumerated() {
            if index > 0 {
                var separator = AttributedString(" · ")
                separator.swiftUI.foregroundColor = look.tertiaryLabel
                line += separator
            }
            var run = AttributedString(tag.text)
            run.link = tag.url
            if tag.isWeak {
                run.swiftUI.foregroundColor = look.secondaryLabel
                run.swiftUI.underlineStyle = Text.LineStyle(pattern: .dash)
            }
            line += run
        }
        return line
    }
}

private struct TagTextPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.medium) {
            TagText(namespace: "female", color: TagNamespace.female.markColor, tags: [
                TagText.Tag("glasses", url: URL(string: "tag:glasses")), TagText.Tag("kimono"),
                TagText.Tag("sole female", isWeak: true), TagText.Tag("full color"),
            ])
            TagText(namespace: "artist", color: TagNamespace.artist.markColor, tags: [TagText.Tag("lantern")])
        }
    }
}

#Preview {
    SchemePreview { TagTextPreview() }
}
