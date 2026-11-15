import EhFeatures
import EhModels
import SwiftUI

/// The advanced options other than the rating and the page range, pushed from the sheet's
/// card: what the search looks in, and the account's default filters it skips. Like every
/// advanced option they apply only while advanced settings are on, and are disabled otherwise.
struct FiltersAdvancedScreen: View {
    @Bindable var model: FiltersModel

    var body: some View {
        Form {
            Section {
                toggle(L10n.Localizable.FiltersView.Title.searchGalleryName, \.galleryName)
                toggle(L10n.Localizable.FiltersView.Title.searchGalleryTags, \.galleryTags)
                toggle(L10n.Localizable.FiltersView.Title.searchGalleryDescription, \.galleryDesc)
                toggle(L10n.Localizable.FiltersView.Title.searchTorrentFilenames, \.torrentFilenames)
                toggle(L10n.Localizable.FiltersView.Title.onlyShowGalleriesWithTorrents, \.onlyWithTorrents)
                toggle(L10n.Localizable.FiltersView.Title.searchLowPowerTags, \.lowPowerTags)
                toggle(L10n.Localizable.FiltersView.Title.searchDownvotedTags, \.downvotedTags)
                toggle(L10n.Localizable.FiltersView.Title.searchExpungedGalleries, \.expungedGalleries)
            }
            Section {
                toggle(L10n.Localizable.FiltersView.Title.disableLanguageFilter, \.disableLanguage)
                toggle(L10n.Localizable.FiltersView.Title.disableUploaderFilter, \.disableUploader)
                toggle(L10n.Localizable.FiltersView.Title.disableTagsFilter, \.disableTags)
            } header: {
                Text(L10n.Localizable.FiltersView.Section.Title.defaultFilter)
                    .filtersSectionHeader()
            }
        }
        .disabled(!model.filter.advanced)
        .filtersFormStyle()
        .navigationTitle(L10n.Localizable.FiltersView.Section.Title.advanced)
        .toolbarTitleDisplayMode(.inline)
    }

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<Filter, Bool>) -> some View {
        Toggle(title, isOn: $model.filter[dynamicMember: keyPath])
            .filtersRow()
    }
}
