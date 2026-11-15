import EhModels
import SwiftUI

/// One namespace of a gallery's tags as text: the namespace's name in its hue in a fixed
/// column, then every tag as wrapping text separated by middle dots (Ledger's tag table,
/// `ledger.md` section 4). It is one text layout, however many tags it holds.
///
/// Under the Ledger look the name is set in small capitals; under Shelf and Wall in 12 pt
/// semibold, right-aligned, as their gallery pages label namespaces. The column grows with the
/// text size and is as wide as the longest name needs ("CHARACTER", "コスプレイヤー" shrink a
/// little rather than lose letters); at the accessibility sizes the name goes above the tags.
/// Each tag with a `url` is a link: the screen decides what it does through `\.openURL`. Weak
/// tags (the site's dashed ones) have a dashed underline and the secondary colour.
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
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The name's column: "CHARACTER" in Ledger's small capitals takes about 73 pt at the
    /// default size.
    @ScaledMetric(relativeTo: .caption2) private var smallCapsColumn: CGFloat = 80
    @ScaledMetric(relativeTo: .caption) private var column: CGFloat = 72

    init(namespace: String, color: Color, tags: [Tag]) {
        self.namespace = namespace
        self.color = color
        self.tags = tags
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                namespaceLabel(inColumn: false)
                tagText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.medium) {
                namespaceLabel(inColumn: true)
                tagText
            }
        }
    }

    private var tagText: some View {
        Text(tagLine)
            .font(.subheadline)
            .lineSpacing(3)
            .foregroundStyle(look.label)
            // Links take the tint; tags read as text in the label colour.
            .tint(look.label)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func namespaceLabel(inColumn: Bool) -> some View {
        let text = Text(namespace).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.85)
        switch look {
        case .ledger:
            text
                .font(.caption2.bold())
                .tracking(0.8)
                .textCase(.uppercase)
                .frame(width: inColumn ? smallCapsColumn : nil, alignment: .leading)
        case .shelf, .wall:
            text
                .font(.caption.weight(.semibold))
                .frame(width: inColumn ? column : nil, alignment: inColumn ? .trailing : .leading)
        }
    }

    private var tagLine: AttributedString {
        var line = AttributedString()
        for (index, tag) in tags.enumerated() {
            if index > 0 {
                // A no-break space before the dot: a line may end with it, never start with it.
                var separator = AttributedString("\u{00A0}· ")
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
