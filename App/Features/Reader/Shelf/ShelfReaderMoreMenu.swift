import EhCore
import EhFeatures
import SwiftUI

/// More: v3's reader menu. The actions of the page on screen (Share has its own button beside
/// this one), Live Text and, where two pages can show, the two-page settings, then "Retry
/// failed pages" and "Reload all pages".
struct ShelfReaderMoreMenu: View {
    @Bindable var model: ReaderModel
    /// In landscape, in a paged direction: where v3 offered the two-page settings.
    let offersDualPage: Bool

    private typealias Strings = L10n.Localizable.ReadingView.ToolbarItem

    var body: some View {
        Menu {
            ShelfReaderPageActions(model: model)
            Section {
                Toggle(isOn: $model.isLiveTextEnabled) {
                    // No localized name exists; "Live Text" is the system's own term, as in v3.
                    Label { Text(verbatim: "Live Text") } icon: { Image(systemName: "text.viewfinder") }
                }
                // The system analyzer is missing on some devices and in the simulator.
                .disabled(!ReaderLiveText.isSupported)
                if offersDualPage {
                    ShelfReaderDualPageToggles()
                }
            }
            Section {
                Button(Strings.Button.retryAllFailedImages, systemImage: "exclamationmark.arrow.triangle.2.circlepath") {
                    model.retryAllFailedImages()
                }
                Button(Strings.Button.reloadAllImages, systemImage: "arrow.counterclockwise") {
                    model.reloadAllImages()
                }
            }
        } label: {
            // The symbol carries the system's localized "More" label for VoiceOver.
            Image(systemName: "ellipsis")
                .frame(width: ReaderMetrics.closeSize, height: ReaderMetrics.closeSize)
                .contentShape(.rect)
        }
    }
}

/// What the page on screen offers (`ReaderModel.imageActions(for:)`): Reload always; Copy,
/// Save and Save original once it has an image.
private struct ShelfReaderPageActions: View {
    let model: ReaderModel

    var body: some View {
        let page = model.currentPage
        Section(L10n.Localizable.Reader.Page.label(page)) {
            ForEach(model.imageActions(for: page).filter { $0 != .share }, id: \.self) { action in
                Button(action.localizedName, systemImage: action.symbolName) {
                    model.perform(action, page: page)
                }
            }
        }
    }
}

/// The two settings v3 offered only here, in landscape.
private struct ShelfReaderDualPageToggles: View {
    @Environment(SettingsStore.self) private var settings

    private typealias Strings = L10n.Localizable.ReadingView.ToolbarItem.Title

    var body: some View {
        @Bindable var settings = settings
        Toggle(isOn: $settings.enablesDualPageMode) {
            Label(Strings.dualPageMode, systemImage: "rectangle.split.2x1")
        }
        Toggle(isOn: $settings.exceptCover) {
            Label(Strings.exceptTheCover, systemImage: "book.closed")
        }
        .disabled(!settings.enablesDualPageMode)
    }
}
