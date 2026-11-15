import EhModels
import SwiftUI

/// The three presets as small still tiles under the stage. The one playing has a grey ring;
/// the selected one has the tint's ring and a check instead. A tap selects a preset.
///
/// Compared without its action, so the stage's beats, which run through it every two
/// seconds, draw the tiles again only when the preset playing or the selection changes.
struct StageTiles: View, Equatable {
    static let size = CGSize(width: 50, height: 80)

    let selection: DesignStyle?
    let playing: DesignStyle
    let choose: (DesignStyle) -> Void

    nonisolated static func == (lhs: StageTiles, rhs: StageTiles) -> Bool {
        lhs.selection == rhs.selection && lhs.playing == rhs.playing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(StagePlayback.order, id: \.self) { style in
                StageTile(style: style, isSelected: style == selection, isPlaying: style == playing) {
                    choose(style)
                }
            }
        }
    }
}

private struct StageTile: View {
    let style: DesignStyle
    let isSelected: Bool
    let isPlaying: Bool
    let action: () -> Void

    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let gap: CGFloat = 3
    private static let ringWidth: CGFloat = 2

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                DesignPreview(.firstScreen(DesignChoices(preset: style)), look: style)
                    .frame(width: StageTiles.size.width, height: StageTiles.size.height)
                    .accessibilityHidden(true)
                    .overlay { playingRing }
                    .overlay { SelectionRing(isSelected: isSelected, width: StageTiles.size.width) }
                    .padding(Self.gap + Self.ringWidth)
                Text(style.localizedName)
                    .font(.footnote.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? look.label : look.secondaryLabel)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(style.localizedName))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var playingRing: some View {
        let outset = Self.gap + Self.ringWidth
        let radius = StageTiles.size.width * SchematicRenderer.cornerRadius / SchematicRenderer.gridWidth + outset
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(look.secondaryLabel, lineWidth: Self.ringWidth)
            .padding(-outset)
            .opacity(isPlaying && !isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }
}
