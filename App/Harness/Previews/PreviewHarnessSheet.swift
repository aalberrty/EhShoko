#if DEBUG || HARNESS
import EhCore
import EhModels
import os
import SwiftUI

/// The harness's sheet: the gallery of previews, like a Settings sheet holds them.
///
/// With `-HarnessScroll YES` it scrolls itself to the end and back twice, inside a
/// `PreviewHarnessScroll` signpost interval, and then shows the sizes page: a recording of
/// `SchematicDraw` signposts shows whether scrolling draws the previews again (it should not)
/// and, as the control, that the sizes page draws its own.
struct PreviewHarnessSheet: View {
    @Binding var page: PreviewHarnessPage
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss

    private static let signposter = OSSignposter(
        subsystem: PerformanceSignposts.subsystem, category: PerformanceSignposts.category
    )

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear.frame(height: 0).id(ScrollMark.top)
                    switch page {
                    case .options: PreviewHarnessGallery()
                    case .sizes: PreviewHarnessSizes()
                    case .stage: PreviewHarnessStage()
                    }
                    Color.clear.frame(height: 0).id(ScrollMark.bottom)
                }
                .task { await scrollIfAsked(proxy) }
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

private enum ScrollMark: Hashable { case top, bottom }

extension PreviewHarnessSheet {
    private func scrollIfAsked(_ proxy: ScrollViewProxy) async {
        guard UserDefaults.standard.bool(forKey: "HarnessScroll") else { return }
        try? await Task.sleep(for: .seconds(5))
        let interval = Self.signposter.beginInterval("PreviewHarnessScroll")
        for mark in [ScrollMark.bottom, .top, .bottom, .top] {
            withAnimation(.linear(duration: 1.5)) { proxy.scrollTo(mark, anchor: mark == .top ? .top : .bottom) }
            try? await Task.sleep(for: .seconds(2.5))
        }
        Self.signposter.endInterval("PreviewHarnessScroll", interval)
        try? await Task.sleep(for: .seconds(2))
        page = .sizes
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
///
/// With `-HarnessControl YES` a plain rounded rectangle stands in for every preview: the
/// control for the allocations check, which tells what the sheet itself leaves behind.
struct PreviewHarnessItem<Preview: View>: View {
    let caption: String
    let size: CGSize
    @ViewBuilder var preview: Preview
    @Environment(\.look) private var look

    private static var isControl: Bool { UserDefaults.standard.bool(forKey: "HarnessControl") }

    var body: some View {
        VStack(spacing: 4) {
            if Self.isControl {
                RoundedRectangle(cornerRadius: 9).fill(look.surface).frame(width: size.width, height: size.height)
            } else {
                preview.frame(width: size.width, height: size.height)
            }
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
