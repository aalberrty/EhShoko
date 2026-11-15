import SwiftUI

/// One chip of the folder row: "All 1,284", or a folder's colour dot, name and count.
nonisolated struct ShelfLibraryChip: Identifiable, Equatable, Sendable {
    /// 0 to 9, or -1 for every folder.
    let folder: Int
    let name: String
    /// Formatted; `nil` while the count is unknown.
    let count: String?

    var id: Int { folder }
}

/// The scrolling row of folder chips at the top of Shelf's library (`shelf.md` section 7),
/// 34 pt high, the chosen one filled with the tint. It scrolls with the list, so it is drawn
/// with the look's fills and nothing in it is glass (`Design/designs/README.md` section 13).
struct ShelfLibraryFolderChips: View {
    let chips: [ShelfLibraryChip]
    let selection: Int
    let select: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        ShelfLibraryChipButton(chip: chip, isSelected: chip.folder == selection) {
                            select(chip.folder)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // A folder chosen earlier may lie past the screen's edge.
                if selection != chips.first?.folder { proxy.scrollTo(selection, anchor: .center) }
            }
            .onChange(of: selection) { _, selection in
                withAnimation { proxy.scrollTo(selection, anchor: .center) }
            }
        }
        // With the chips' own 5 pt above, 12 pt under the Library tab's switch, as drawn.
        .padding(.top, 1)
    }
}

private struct ShelfLibraryChipButton: View {
    let chip: ShelfLibraryChip
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.look) private var look
    @Environment(\.onTint) private var onTint

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if chip.folder >= 0 {
                    Circle()
                        .fill(FolderColor.color(forFolder: chip.folder))
                        .frame(width: 9, height: 9)
                }
                Text(chip.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? onTint : look.label)
                if let count = chip.count {
                    Text(count)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? onTint.opacity(0.8) : look.secondaryLabel)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(look.surface), in: .capsule)
            // A 44 pt target around the 34 pt chip.
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
