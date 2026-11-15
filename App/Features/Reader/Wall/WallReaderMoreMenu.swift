import EhCore
import EhFeatures
import EhModels
import SwiftUI
import UIKit

/// More, the cluster's trailing circle: everything the reader offers besides scrubbing. From
/// the button upwards: Auto-play, the reading direction and the reading settings; Live Text
/// and, where two pages can show, the two-page settings; "Retry failed pages" and "Reload all
/// pages"; then the actions of the page on screen (Reload, Copy, Save, Share).
///
/// A UIKit button whose menu is made each time it opens. What a page offers depends on
/// whether its image has arrived, which the model keeps out of observation; SwiftUI's `Menu`
/// keeps the content of its first opening until something it observes changes, so it would
/// go on offering Reload alone for a page that has since loaded.
struct WallReaderMoreMenu: UIViewRepresentable {
    let model: ReaderModel
    /// In landscape, in a paged direction: where v3 offered the two-page settings.
    let offersDualPage: Bool

    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look

    func makeCoordinator() -> WallReaderMoreMenuItems {
        WallReaderMoreMenuItems(model: model, settings: settings)
    }

    func makeUIView(context: Context) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "ellipsis")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body)
            .applying(UIImage.SymbolConfiguration(weight: .semibold))
        let button = UIButton(configuration: configuration)
        button.showsMenuAsPrimaryAction = true
        // The menu opens upwards from the bottom of the screen. Its order is kept as written,
        // so what is used most is nearest the thumb whichever way the system would sort it.
        button.preferredMenuElementOrder = .fixed
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
        CGSize(width: WallReaderMetrics.clusterHeight, height: WallReaderMetrics.clusterHeight)
    }
}

/// Makes More's menu from the state of the moment it opens.
final class WallReaderMoreMenuItems {
    var model: ReaderModel
    var settings: SettingsStore
    var offersDualPage = false

    private typealias Strings = L10n.Localizable.ReadingView.ToolbarItem

    init(model: ReaderModel, settings: SettingsStore) {
        self.model = model
        self.settings = settings
    }

    /// From the top of the menu down, so the last group is the one next to the button.
    func make() -> [UIMenuElement] {
        [pageActions(), reloads(), options(), reading()]
    }

    /// Reload always; Copy, Save, Save original and Share once the page has its image
    /// (`ReaderModel.imageActions(for:)`). On the closing page, the last page's.
    private func pageActions() -> UIMenu {
        let model = model
        let page = model.currentPage
        let actions = model.imageActions(for: page).map { action in
            UIAction(title: action.localizedName, image: UIImage(systemName: action.symbolName)) { [weak model] _ in
                model?.perform(action, page: page)
            }
        }
        return UIMenu(title: L10n.Localizable.Reader.Page.label(page), options: .displayInline, children: actions)
    }

    private func reloads() -> UIMenu {
        let model = model
        return UIMenu(options: .displayInline, children: [
            UIAction(title: Strings.Button.reloadAllImages, image: UIImage(systemName: "arrow.counterclockwise")) { [weak model] _ in
                model?.reloadAllImages()
            },
            UIAction(
                title: Strings.Button.retryAllFailedImages,
                image: UIImage(systemName: "exclamationmark.arrow.triangle.2.circlepath")
            ) { [weak model] _ in
                model?.retryAllFailedImages()
            },
        ])
    }

    private func options() -> UIMenu {
        let model = model
        let settings = settings
        // No localized name exists; "Live Text" is the system's own term, as in v3.
        let liveText = UIAction(
            title: "Live Text", image: UIImage(systemName: "text.viewfinder"),
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

    /// The reading settings, the reading direction and Auto-play, each of the last two a menu
    /// of its choices that names the current one.
    private func reading() -> UIMenu {
        let model = model
        let settings = UIAction(title: Strings.Button.readingSetting, image: UIImage(systemName: "gearshape")) { [weak model] _ in
            model?.showSettings()
        }
        return UIMenu(options: .displayInline, children: [settings, direction(), autoPlay()])
    }

    private func direction() -> UIMenu {
        let settings = settings
        let current = settings.readingDirection
        let choices = ReadingDirection.allCases.map { direction in
            UIAction(
                title: direction.localizedName, image: UIImage(systemName: direction.wallSymbol),
                state: direction == current ? .on : .off
            ) { _ in
                settings.readingDirection = direction
            }
        }
        let menu = UIMenu(
            title: L10n.Localizable.ReadingSettingView.Title.direction,
            image: UIImage(systemName: current.wallSymbol), options: .singleSelection, children: choices
        )
        menu.subtitle = current.localizedName
        return menu
    }

    private func autoPlay() -> UIMenu {
        let model = model
        let current = model.autoPlay
        let choices = ReaderAutoPlayPolicy.allCases.map { policy in
            UIAction(title: policy.localizedName, state: policy == current ? .on : .off) { [weak model] _ in
                model?.setAutoPlay(policy)
            }
        }
        let menu = UIMenu(
            title: L10n.Localizable.Reader.autoplay, image: UIImage(systemName: "timer"),
            options: .singleSelection, children: choices
        )
        menu.subtitle = current.localizedName
        return menu
    }
}

private extension ReadingDirection {
    var wallSymbol: String {
        switch self {
        case .leftToRight: "arrow.right"
        case .rightToLeft: "arrow.left"
        case .vertical: "arrow.down"
        }
    }
}
