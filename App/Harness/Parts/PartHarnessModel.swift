#if DEBUG || HARNESS
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The part harness's state: its options, its own settings and app model, the fixtures, and the
/// scripted checks.
@Observable
final class PartHarnessModel {
    var options: PartHarnessOptions {
        didSet { apply(from: oldValue) }
    }
    private(set) var isReady = false
    /// Changes when the stage must be built again.
    private(set) var stageID = 0

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let app = AppModel()
    @ObservationIgnored let continueModel = ContinueModel()
    @ObservationIgnored let fixtures = PartHarnessFixtures()

    private static let settingsSuite = "app.ehshoko.part-harness"

    init(options: PartHarnessOptions) {
        self.options = options
        // The installed settings were set up from the launch's options when they were made:
        // SwiftUI evaluates the view's `@State` initial value again whenever its parent is
        // drawn, and a model made then and thrown away must not write them back.
        settings = PartHarnessDependencies.settings ?? Self.makeSettings(for: options, translatesTags: false)
        fixtures.state = options.state
        selectPartTab()
    }

    /// Settings of the harness's own, empty at each start (launch arguments such as
    /// `-settings.readingDirection` still apply) and set to `options`, so nothing the user
    /// chose changes. `translatesTags`: the rich page's chips show the stored translations.
    static func makeSettings(for options: PartHarnessOptions, translatesTags: Bool) -> SettingsStore {
        let defaults = UserDefaults(suiteName: settingsSuite) ?? .standard
        defaults.removePersistentDomain(forName: settingsSuite)
        let settings = SettingsStore(defaults: defaults)
        settings.designChoices = options.choices
        settings.preferredColorScheme = options.scheme.preferredColorScheme
        settings.showsTagsInList = options.showsTags
        settings.wallDensity = options.density
        if translatesTags {
            settings.enablesTagsExtension = true
            settings.translatesTags = true
        }
        return settings
    }

    /// The settings were changed from inside the app (the wizard's Apply, Experience's presets,
    /// Settings' Theme): the options follow, so the panel shows them and a part's stage is built
    /// again for another bar, as the options' own change does.
    func settingsChanged() {
        var options = options
        options.choices = settings.designChoices
        options.scheme = PartHarnessScheme(settings.preferredColorScheme)
        if options != self.options {
            self.options = options
        }
    }

    func prepare() async {
        guard !isReady else { return }
        await fixtures.prepare()
        await PartHarnessDependencies.seed(with: fixtures.entries)
        isReady = true
    }

    /// The scripted memory check (`-HarnessMemoryCheck`): what is alive under the designs the
    /// harness started on, then, after switching to another preset, what is alive under that.
    func runMemoryCheck() async {
        guard let preset = options.memoryCheckPreset else { return }
        do {
            try await Task.sleep(for: .seconds(25))
            PartHarnessHeap.writeReport(named: "part-harness-heap-1.txt")
            options.choices = DesignChoices(preset: preset)
            try await Task.sleep(for: .seconds(10))
            PartHarnessHeap.writeReport(named: "part-harness-heap-2.txt")
        } catch {
            return
        }
    }

    /// Under `tabs`, selects the tab the part is in before the stage is drawn; resetting the
    /// navigation selects Home.
    private func selectPartTab() {
        guard options.part != .shell, options.choices.bar == .tabs, app.router.selectedTab != options.tab else { return }
        app.router.select(options.tab)
    }

    /// Opens what the options ask to see over the stage's root. (Under `command` the search
    /// part's surface is opened by the stage's command stack.)
    func open() {
        let router = app.router
        switch options.part {
        case .gallery:
            guard let gallery = fixtures.gallery else { return }
            switch options.presentation {
            case .pushed: router.home.push(.detail(gallery))
            case .pane: router.home.open(gallery, inSidePane: true)
            case .sheet: router.present(gallery)
            }
        case .shell, .list, .start, .search, .library:
            break
        }
    }

    private func apply(from old: PartHarnessOptions) {
        guard options != old else { return }
        if options.choices != old.choices {
            settings.designChoices = options.choices
        }
        if options.state != old.state {
            fixtures.state = options.state
        }
        if options.showsTags != old.showsTags {
            settings.showsTagsInList = options.showsTags
        }
        if options.density != old.density {
            settings.wallDensity = options.density
        }
        if options.scheme != old.scheme {
            settings.preferredColorScheme = options.scheme.preferredColorScheme
        }
        // The whole shell follows its settings by itself. A part's stage is built again when
        // what it is built from changes: the part, the bar, how it is presented.
        var structure = options
        structure.state = old.state
        structure.scheme = old.scheme
        structure.usesLargestText = old.usesLargestText
        structure.showsPanelButton = old.showsPanelButton
        structure.memoryCheckPreset = old.memoryCheckPreset
        structure.showsTags = old.showsTags
        structure.density = old.density
        structure.choices = old.choices
        let barChanged = options.part != .shell && options.choices.bar != old.choices.bar
        if structure != old || barChanged {
            app.router.resetNavigation()
            app.router.dismissPresentedGallery()
            selectPartTab()
            stageID += 1
        }
    }
}
#endif
