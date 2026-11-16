import EhCore
import EhFeatures
import SwiftUI
import UIKit

/// More: v3's reader menu. The actions of the page on screen (Share has its own button beside
/// this one), Live Text and, where two pages can show, the two-page settings, then "Retry
/// failed pages" and "Reload all pages".
///
/// A UIKit button whose menu is made each time it opens, as the engine makes a page's
/// long-press menu. What a page offers depends on whether its image has arrived, which the
/// model keeps out of observation; SwiftUI's `Menu` keeps the content it made on its first
/// opening until something it observes changes, so it would go on offering Reload alone for a
/// page that has since loaded.
struct ShelfReaderMoreMenu: UIViewRepresentable {
    let model: ReaderModel
    /// In landscape, in a paged direction: where v3 offered the two-page settings.
    let offersDualPage: Bool

    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look

    func makeCoordinator() -> ShelfReaderMoreMenuItems {
        ShelfReaderMoreMenuItems(model: model, settings: settings)
    }

    func makeUIView(context: Context) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "ellipsis")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body)
            .applying(UIImage.SymbolConfiguration(weight: .medium))
        let button = UIButton(configuration: configuration)
        button.showsMenuAsPrimaryAction = true
        let items = context.coordinator
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { completion in
                MainActor.assumeIsolated { completion(items.make()) }
            }
        ])
        button.accessibilityLabel = L10n.Localizable.List.Action.more
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.model = model
        context.coordinator.settings = settings
        context.coordinator.offersDualPage = offersDualPage
        button.tintColor = look.uiLabel
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: ReaderMetrics.closeSize, height: ReaderMetrics.closeSize)
    }
}

/// Makes More's menu from the state of the moment it opens.
final class ShelfReaderMoreMenuItems {
    var model: ReaderModel
    var settings: SettingsStore
    var offersDualPage = false

    private typealias Strings = L10n.Localizable.ReadingView.ToolbarItem

    init(model: ReaderModel, settings: SettingsStore) {
        self.model = model
        self.settings = settings
    }

    func make() -> [UIMenuElement] {
        [pageActions(), options(), reloads()]
    }

    /// Reload always; Copy, Save and Save original once the page has its image
    /// (`ReaderModel.imageActions(for:)`).
    private func pageActions() -> UIMenu {
        let model = model
        let page = model.currentPage
        let actions = model.imageActions(for: page).filter { $0 != .share }.map { action in
            UIAction(title: action.localizedName, image: UIImage(systemName: action.symbolName)) { [weak model] _ in
                model?.perform(action, page: page)
            }
        }
        return UIMenu(title: L10n.Localizable.Reader.Page.label(page), options: .displayInline, children: actions)
    }

    private func options() -> UIMenu {
        let model = model
        let settings = settings
        let liveText = UIAction(
            title: L10n.Localizable.Reader.liveText, image: UIImage(systemName: "text.viewfinder"),
            // The system analyzer is missing on some devices and in the simulator.
            attributes: ReaderLiveText.isSupported ? [] : .disabled,
            state: model.isLiveTextEnabled ? .on : .off
        ) { [weak model] _ in
            model?.isLiveTextEnabled.toggle()
        }
        var children: [UIMenuElement] = [liveText]
        if offersDualPage {
            children.append(UIAction(
                title: Strings.Title.dualPageMode, image: UIImage(systemName: "rectangle.split.2x1"),
                state: settings.enablesDualPageMode ? .on : .off
            ) { _ in
                settings.enablesDualPageMode.toggle()
            })
            children.append(UIAction(
                title: Strings.Title.exceptTheCover, image: UIImage(systemName: "book.closed"),
                attributes: settings.enablesDualPageMode ? [] : .disabled,
                state: settings.exceptCover ? .on : .off
            ) { _ in
                settings.exceptCover.toggle()
            })
        }
        return UIMenu(options: .displayInline, children: children)
    }

    private func reloads() -> UIMenu {
        let model = model
        return UIMenu(options: .displayInline, children: [
            UIAction(
                title: Strings.Button.retryAllFailedImages,
                image: UIImage(systemName: "exclamationmark.arrow.triangle.2.circlepath")
            ) { [weak model] _ in
                model?.retryAllFailedImages()
            },
            UIAction(title: Strings.Button.reloadAllImages, image: UIImage(systemName: "arrow.counterclockwise")) { [weak model] _ in
                model?.reloadAllImages()
            }
        ])
    }
}
