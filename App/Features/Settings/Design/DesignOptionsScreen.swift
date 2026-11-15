import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Experience › one page's options (`settings.md`, "One page's options"): the page's caption,
/// a card per choice, and, for Lists and the gallery page, the settings that only affect them.
/// A tap on a card applies at once and the screen stays.
struct DesignOptionsScreen: View {
    let part: DesignPart

    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look
    @State private var choices = 0

    var body: some View {
        let selected = settings.designChoices[part]
        List {
            Section {
                ForEach(part.options, id: \.self) { option in
                    DesignOptionCard(part: part, option: option, isSelected: option == selected) {
                        choices += 1
                        settings.setDesign(option, for: part)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }
            } header: {
                Text(part.localizedCaption)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
                    .textCase(nil)
                    .padding(.bottom, Tokens.Spacing.xSmall)
            } footer: {
                Text(part == .look ? L10n.Localizable.Settings.Design.Look.note : L10n.Localizable.Settings.Design.Option.applies)
                    .settingsFootnote()
            }
            switch part {
            case .list: DesignListSettings()
            case .gallery: DesignGallerySettings()
            default: EmptyView()
            }
        }
        .settingsFormStyle()
        .navigationTitle(part.localizedName)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: choices)
    }
}

/// "In lists": the tag settings v3 had under Appearance. Ledger's rows never show tags, so the
/// group is dimmed while Lists is Ledger.
private struct DesignListSettings: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look

    var body: some View {
        @Bindable var settings = settings
        let isDimmed = settings.designList == .ledger
        Section {
            Toggle(isOn: $settings.showsTagsInList) {
                Text(L10n.Localizable.AppearanceSettingView.Title.showsTagsInList)
                    .foregroundStyle(isDimmed ? look.tertiaryLabel : look.label)
            }
            Picker(selection: $settings.listTagsNumberMaximum) {
                // 0 means no limit.
                Text(L10n.Localizable.AppearanceSettingView.Menu.Title.infite).tag(0)
                ForEach(Array(stride(from: 5, through: 20, by: 5)), id: \.self) { number in
                    Text(number, format: .number).tag(number)
                }
            } label: {
                Text(L10n.Localizable.AppearanceSettingView.Title.maximumNumberOfTags)
                    .foregroundStyle(isDimmed || !settings.showsTagsInList ? look.tertiaryLabel : look.label)
            }
            .pickerStyle(.menu)
            .disabled(!settings.showsTagsInList)
        } header: {
            Text(L10n.Localizable.Settings.Design.Lists.header).settingsSectionHeader()
        } footer: {
            Text(L10n.Localizable.Settings.Design.Lists.tagsNote).settingsFootnote()
        }
        .settingsRow()
        .disabled(isDimmed)
    }
}

/// "On this page": the Japanese title, shown on the gallery page.
private struct DesignGallerySettings: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle(L10n.Localizable.AppearanceSettingView.Title.displaysJapaneseTitle, isOn: $settings.displaysJapaneseTitle)
        } header: {
            Text(L10n.Localizable.Settings.Design.Gallery.header).settingsSectionHeader()
        }
        .settingsRow()
    }
}

extension DesignPart {
    /// The sentence under a page's name saying what it covers; the wizard's steps use it too.
    var localizedCaption: String {
        typealias Caption = L10n.Localizable.Settings.Design.Caption
        return switch self {
        case .bar: Caption.bar
        case .start: Caption.start
        case .list: Caption.list
        case .gallery: Caption.gallery
        case .reader: Caption.reader
        case .search: Caption.search
        case .library: Caption.library
        case .look: Caption.look
        }
    }
}
