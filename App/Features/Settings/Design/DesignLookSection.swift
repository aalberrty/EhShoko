import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Look: the three settings that together decide the colours, each changing one thing, in
/// this order: colours and type pick the palette and the typefaces, the theme its light or
/// dark version, the accent replaces the look's own colour.
struct DesignLookSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Section {
            if DesignPart.choosable.contains(.look) {
                DesignPartRow(part: .look, choices: settings.designChoices)
            }
            DesignThemeRow()
            DesignAccentRow()
        } header: {
            Text(L10n.Localizable.Settings.Design.look).settingsSectionHeader()
        } footer: {
            Text(L10n.Localizable.Settings.Design.Look.footer).settingsFootnote()
        }
        .settingsRow()
    }
}

/// The pages: one row per part other than the look, each pushing that page's options.
struct DesignPagesSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let choices = settings.designChoices
        Section {
            ForEach(DesignPart.choosable.filter { $0 != .look }, id: \.self) { part in
                DesignPartRow(part: part, choices: choices)
            }
        } header: {
            Text(L10n.Localizable.Settings.Design.pages).settingsSectionHeader()
        } footer: {
            Text(L10n.Localizable.Settings.Design.footer).settingsFootnote()
        }
        .settingsRow()
    }
}

/// One page: a thumbnail of the current choice, the page's name, the choice's description,
/// and its name, in the tint when it differs from the nearest preset. To VoiceOver: the page,
/// the choice and its description.
private struct DesignPartRow: View {
    let part: DesignPart
    let choices: DesignChoices

    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let thumbnail = CGSize(width: 38, height: 61)

    var body: some View {
        let option = choices[part]
        NavigationLink(value: Route.settings(.designPart(part))) {
            HStack(spacing: Tokens.Spacing.medium) {
                DesignPreview(.option(part, option))
                    .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
                    Text(part.localizedName)
                        .foregroundStyle(look.label)
                    if let description = part.localizedDescription(of: option) {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(look.secondaryLabel)
                    }
                    if typeSize.isAccessibilitySize {
                        choiceName(option)
                    }
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: Tokens.Spacing.small)
                    choiceName(option)
                }
            }
            .padding(.vertical, Tokens.Spacing.xSmall)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(DesignPreview.Subject.option(part, option).accessibilityLabel))
        }
    }

    private func choiceName(_ option: DesignOption) -> some View {
        Text(option.localizedName)
            .foregroundStyle(choices.differsFromNearestPreset(part) ? AnyShapeStyle(.tint) : AnyShapeStyle(look.secondaryLabel))
    }
}

/// System, Light or Dark, in the row (`preferredColorScheme`); under the label at the
/// accessibility sizes.
private struct DesignThemeRow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        @Bindable var settings = settings
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.small))
            : AnyLayout(HStackLayout(spacing: Tokens.Spacing.medium))
        layout {
            Text(L10n.Localizable.AppearanceSettingView.Title.theme)
                .foregroundStyle(look.label)
                .accessibilityHidden(true)
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            Picker(L10n.Localizable.AppearanceSettingView.Title.theme, selection: $settings.preferredColorScheme) {
                ForEach(PreferredColorScheme.allCases) { scheme in
                    Text(scheme.localizedName).tag(scheme)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
        }
    }
}

/// The accent: a swatch of the tint in use and a menu, "Look's own" or "Custom…", which opens
/// the system's colour picker. A chosen colour replaces every look's own accent until "Look's
/// own" stores system blue again (`README.md` section 7).
private struct DesignAccentRow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @State private var isPicking = false

    var body: some View {
        let isOwn = settings.accentColor.isDefaultAccent
        HStack(spacing: Tokens.Spacing.small) {
            Text(L10n.Localizable.Settings.Design.accent)
                .foregroundStyle(look.label)
            Spacer(minLength: Tokens.Spacing.small)
            Circle()
                .fill(tint)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Menu {
                Button {
                    settings.accentColor = .systemBlue
                } label: {
                    if isOwn {
                        Label(L10n.Localizable.Settings.Design.Accent.own, systemImage: "checkmark")
                    } else {
                        Text(L10n.Localizable.Settings.Design.Accent.own)
                    }
                }
                Button(L10n.Localizable.Settings.Design.Accent.custom) { isPicking = true }
            } label: {
                HStack(spacing: Tokens.Spacing.xSmall) {
                    Text(isOwn ? L10n.Localizable.Settings.Design.Accent.own : L10n.Localizable.Settings.Design.custom)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(look.secondaryLabel)
            }
            .accessibilityLabel(Text(L10n.Localizable.Settings.Design.accent))
            .accessibilityValue(Text(isOwn ? L10n.Localizable.Settings.Design.Accent.own : L10n.Localizable.Settings.Design.custom))
        }
        .sheet(isPresented: $isPicking) {
            SystemColorPicker(initial: UIColor(tint)) { color in
                if let rgb = RGBColor(Color(uiColor: color)) { settings.accentColor = rgb }
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
        }
    }
}
