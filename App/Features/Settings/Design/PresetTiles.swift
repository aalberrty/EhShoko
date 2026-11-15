import EhCore
import EhModels
import SwiftUI

/// The preset tiles of the Settings page: Shelf, Wall and Ledger, each a still preview of its
/// first screen and bar in its own colours, and Custom once a mix has been made. A tap
/// applies at once. The tiles do not move: this page is passed through for other settings.
struct PresetTiles: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var taps = 0

    var body: some View {
        let current = settings.designChoices
        let preset = current.preset
        // The Custom tile shows the current mix, or the remembered one while a preset is on.
        let custom = preset == nil ? current : settings.designCustom
        let tiles = DesignStyle.allCases.map(PresetTile.Kind.preset) + (custom.map { [.custom($0)] } ?? [])
        let size = tiles.count > 3 ? CGSize(width: 80, height: 128) : CGSize(width: 106, height: 170)
        let rows = typeSize.isAccessibilitySize ? stride(from: 0, to: tiles.count, by: 2).map {
            Array(tiles[$0..<min($0 + 2, tiles.count)])
        } : [tiles]
        VStack(spacing: Tokens.Spacing.medium) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(row, id: \.self) { kind in
                        PresetTile(kind: kind, size: size, isSelected: kind.isSelected(by: preset)) {
                            apply(kind)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.vertical, Tokens.Spacing.small)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    private func apply(_ kind: PresetTile.Kind) {
        taps += 1
        switch kind {
        case .preset(let style): settings.applyDesignPreset(style)
        case .custom: settings.restoreCustomDesign()
        }
    }
}

/// One tile: the preview with its name under it; the selected one has a ring in the tint and
/// a check. To VoiceOver it is one button: "Shelf, Preset, selected".
private struct PresetTile: View {
    enum Kind: Hashable {
        case preset(DesignStyle)
        /// A mix: the current one, or the one remembered in `designCustom`.
        case custom(DesignChoices)

        func isSelected(by preset: DesignStyle?) -> Bool {
            switch self {
            case .preset(let style): style == preset
            case .custom: preset == nil
            }
        }
    }

    let kind: Kind
    let size: CGSize
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: Tokens.Spacing.small) {
                preview
                    .frame(width: size.width, height: size.height)
                    .overlay { SelectionRing(isSelected: isSelected, width: size.width) }
                Text(name)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? look.label : look.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(detail))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var preview: some View {
        switch kind {
        // A preset is drawn in its own colours, because choosing it changes them too.
        case .preset(let style): DesignPreview(.firstScreen(DesignChoices(preset: style)), look: style)
        case .custom(let choices): DesignPreview(.firstScreen(choices))
        }
    }

    private var name: String {
        switch kind {
        case .preset(let style): style.localizedName
        case .custom: L10n.Localizable.Settings.Design.custom
        }
    }

    private var detail: String {
        switch kind {
        case .preset: L10n.Localizable.Settings.Design.preset
        case .custom: L10n.Localizable.Settings.Design.ownMix
        }
    }
}
