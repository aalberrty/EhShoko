#if DEBUG
import EhModels
import SwiftUI

/// The harness's sheet: the gallery of previews, like a Settings sheet holds them.
struct PreviewHarnessSheet: View {
    @Binding var page: PreviewHarnessPage
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                switch page {
                case .options: PreviewHarnessGallery()
                case .sizes: PreviewHarnessSizes()
                }
            }
            .background(look.background)
            .navigationTitle(Text(verbatim: "Previews"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(selection: $page) {
                        ForEach(PreviewHarnessPage.allCases) { page in
                            Text(verbatim: page.rawValue.capitalized).tag(page)
                        }
                    } label: {
                        Text(verbatim: "Page")
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: "Done")
                    }
                }
            }
        }
    }
}

/// The 23 options at 110 × 176 pt, the three preset tiles in their own looks, and the
/// pictures of a mix.
struct PreviewHarnessGallery: View {
    static let optionSize = CGSize(width: 110, height: 176)
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(DesignPart.allCases, id: \.self) { part in
                PreviewHarnessRow(title: part.localizedName) {
                    ForEach(part.options, id: \.self) { option in
                        PreviewHarnessItem(caption: option.localizedName, size: Self.optionSize) {
                            DesignPreview(.option(part, option))
                        }
                    }
                }
            }
            PreviewHarnessRow(title: "Presets") {
                ForEach(DesignStyle.allCases, id: \.self) { style in
                    PreviewHarnessItem(caption: style.localizedName, size: CGSize(width: 106, height: 170)) {
                        DesignPreview(.firstScreen(DesignChoices(preset: style)), look: style)
                    }
                }
            }
            PreviewHarnessRow(title: "A mix: Shelf with Ledger's lists and Wall's reader") {
                ForEach(Self.mixSubjects(look), id: \.self) { subject in
                    PreviewHarnessItem(caption: "", size: CGSize(width: 66, height: 106)) {
                        DesignPreview(subject)
                    }
                }
                PreviewHarnessItem(caption: "Custom tile", size: CGSize(width: 80, height: 128)) {
                    DesignPreview(.firstScreen(Self.mix(look)))
                }
            }
        }
        .padding(16)
    }

    /// The owner's example of a mix (Shelf with Ledger's lists and Wall's reader), in `look`.
    static func mix(_ look: Look) -> DesignChoices {
        var choices = DesignChoices(preset: .shelf)
        choices.list = .ledger
        choices.reader = .wall
        choices.look = switch look {
        case .shelf: .shelf
        case .wall: .wall
        case .ledger: .ledger
        }
        return choices
    }

    static func mixSubjects(_ look: Look) -> [DesignPreview.Subject] {
        let mix = mix(look)
        return [.firstScreen(mix), .gallery(mix), .reader(mix)]
    }
}

/// One option at every size `settings.md` gives, to judge whether it is still recognisable.
private struct PreviewHarnessSizes: View {
    static let sizes: [(String, CGFloat)] = [
        ("Experience row", 38), ("Wizard tiles", 50), ("Experience pictures", 66), ("Four tiles", 80),
        ("Wizard step", 84), ("Summary", 86), ("Options", 95), ("Options", 105), ("Preset tiles", 106),
        ("Stage", 150),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(DesignPart.allCases, id: \.self) { part in
                PreviewHarnessRow(title: part.localizedName, scrolls: true) {
                    ForEach(Self.sizes, id: \.1) { name, width in
                        PreviewHarnessItem(caption: "\(Int(width)) \(name)", size: CGSize(width: width, height: width * 1.6)) {
                            DesignPreview(.option(part, part.options.last ?? .style(.shelf)))
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct PreviewHarnessRow<Content: View>: View {
    let title: String
    var scrolls = false
    @ViewBuilder var content: Content
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.subheadline.bold())
                .foregroundStyle(look.secondaryLabel)
            if scrolls {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) { content }
                }
            } else {
                HStack(alignment: .top, spacing: 10) { content }
            }
        }
    }
}

/// A preview at a fixed size in points, which does not grow with the text size.
struct PreviewHarnessItem<Preview: View>: View {
    let caption: String
    let size: CGSize
    @ViewBuilder var preview: Preview
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 4) {
            preview.frame(width: size.width, height: size.height)
            if !caption.isEmpty {
                Text(verbatim: caption)
                    .font(.caption2)
                    .foregroundStyle(look.secondaryLabel)
                    .lineLimit(1)
                    .frame(width: size.width)
            }
        }
    }
}
#endif
