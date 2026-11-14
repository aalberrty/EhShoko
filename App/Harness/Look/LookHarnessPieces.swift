#if DEBUG
import EhModels
import SwiftUI

/// The pieces page of the look harness: everything that may sit in scrolling content.
struct LookHarnessPieces: View {
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.medium) {
            Text(verbatim: "Tokens").lookSectionHeader()
            LookHarnessSwatches()
            Text(verbatim: "Type and marks").lookSectionHeader()
            LookHarnessRow()
            LookHarnessMarks()
            Text(verbatim: "Tags").lookSectionHeader()
            VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                TagText(namespace: "female", color: TagNamespace.female.markColor, tags: [
                    TagText.Tag("glasses", url: URL(string: "ehgaro-harness:tag")), TagText.Tag("kimono"),
                    TagText.Tag("sole female", isWeak: true), TagText.Tag("full color"),
                ])
                TagText(namespace: "parody", color: TagNamespace.parody.markColor, tags: [TagText.Tag("original")])
                TagText(namespace: "group", color: TagNamespace.group.markColor, tags: [TagText.Tag("lantern scans")])
            }
            .environment(\.openURL, OpenURLAction { _ in .handled })
            Text(verbatim: "Covers").lookSectionHeader()
            LookHarnessCovers()
        }
        .foregroundStyle(look.label)
    }
}

private struct LookHarnessSwatches: View {
    @Environment(\.look) private var look

    private var swatches: [(String, AnyShapeStyle)] {
        let colors: [(String, Color)] = [
            ("bg", look.background), ("surface", look.surface), ("raised", look.raised),
            ("label", look.label), ("2nd", look.secondaryLabel), ("3rd", look.tertiaryLabel),
            ("sep", look.separator), ("fill", look.fill), ("fill2", look.fill2), ("fill3", look.fill3),
            ("rating", look.rating),
        ]
        return colors.map { ($0.0, AnyShapeStyle($0.1)) } + [("tint", AnyShapeStyle(.tint))]
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(swatches, id: \.0) { name, style in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(style)
                        .frame(height: 28)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(look.separator)
                        }
                    Text(verbatim: name)
                        .font(.caption2)
                        .foregroundStyle(look.secondaryLabel)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// A row the way a list could draw it: title face, credit, capsule, stars, figure.
private struct LookHarnessRow: View {
    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.medium) {
            CategoryMark(.doujinshi, style: .bar)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Hoshizora Academy ~After School Stories~")
                    .font(.headline)
                    .lookTitleDesign()
                    .lineLimit(1)
                Text(verbatim: "Studio Polaris · Mizuki")
                    .font(.footnote)
                    .foregroundStyle(look.secondaryLabel)
                HStack(spacing: 6) {
                    CategoryMark(.gameCG, style: .capsule)
                    RatingStars(rating: 4.08, tint: .look).font(.caption2)
                    RatingFigure(rating: 4.08).font(.caption).foregroundStyle(look.secondaryLabel)
                }
                Text(verbatim: "f:glasses$ l:english$")
                    .font(.footnote)
                    .lookSyntaxDesign()
                    .foregroundStyle(look.secondaryLabel)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LookHarnessMarks: View {
    @Environment(\.look) private var look
    private let categories = EhModels.Category.allFiltersCases

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 4) {
                ForEach(categories) { CategoryMark($0, style: .capsule) }
            }
            HStack(spacing: 6) {
                ForEach(categories) { CategoryMark($0, style: .dot) }
                Spacer().frame(width: 6)
                ForEach(categories) { CategoryMark($0, style: .square) }
            }
            HStack(spacing: 6) {
                ForEach(0..<10, id: \.self) { index in
                    Circle().fill(FolderColor.color(forFolder: index)).frame(width: 12, height: 12)
                }
                CategoryMark(.manga, style: .name).font(.footnote)
                CategoryMark(.cosplay, style: .name).font(.footnote)
            }
        }
    }
}

private struct LookHarnessCovers: View {
    var body: some View {
        // Fixed widths that fit a 370 pt column (a 402 pt phone less the margins): wider, and
        // the row would widen the page past the screen.
        HStack(alignment: .top, spacing: Tokens.Spacing.small) {
            CoverImage(url: LookHarnessCoverFiles.cover, size: CGSize(width: 88, height: 126), cornerRadius: 10)
            CoverImage(url: LookHarnessCoverFiles.cover, size: CGSize(width: 54, height: 77), cornerRadius: 4)
            CoverImage(url: LookHarnessCoverFiles.webtoon, size: CGSize(width: 54, height: 77), cornerRadius: 4)
            CoverImage(url: nil, size: CGSize(width: 40, height: 57), cornerRadius: 4)
            CoverImage(url: LookHarnessCoverFiles.missing, size: CGSize(width: 40, height: 57), cornerRadius: 4)
            CoverImage(url: LookHarnessCoverFiles.cover, aspectRatio: 7 / 10).frame(width: 50)
        }
    }
}

/// Covers drawn once into the temporary folder: a 250 × 354 cover and a 250 × 1500 strip, which
/// `CoverImage` crops to 2:3.
private enum LookHarnessCoverFiles {
    static let cover = write(name: "look-harness-cover.png", size: CGSize(width: 250, height: 354))
    static let webtoon = write(name: "look-harness-webtoon.png", size: CGSize(width: 250, height: 1500))
    static let missing = FileManager.default.temporaryDirectory.appending(path: "look-harness-missing.png")

    private static func write(name: String, size: CGSize) -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            let colors = [UIColor.systemIndigo, .systemPink, .systemTeal, .systemOrange]
            let band = size.height / CGFloat(colors.count * 2)
            for index in 0..<(colors.count * 2) {
                colors[index % colors.count].setFill()
                context.fill(CGRect(x: 0, y: CGFloat(index) * band, width: size.width, height: band))
            }
            UIColor.white.setFill()
            context.fill(CGRect(x: 20, y: 20, width: size.width - 40, height: 30))
        }
        return (try? data.write(to: url)) == nil ? nil : url
    }
}
#endif
