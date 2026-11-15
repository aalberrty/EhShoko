#if DEBUG || HARNESS
import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The part harness (`Design/designs/README.md` section 11.3): one part, in the design under
/// test, inside each variant of its surroundings that the contract distinguishes, so that a
/// part proves it meets the contract without running every combination of designs.
///
/// It is the real shell around the part: the same stack, bottom chrome host, side pane, bars
/// and presentations, on routers and settings of its own, so nothing the user chose changes.
/// Lists are fixtures in whichever state is asked for. Launched as the whole app
/// (`-Harness part`) it also has a database of its own, seeded, and an offline client, so a
/// gallery page shows a stored page and nothing leaves the device; opened from Laboratory it
/// uses the app's own database and client for everything but lists.
struct PartHarnessView: View {
    @State private var model: PartHarnessModel
    @State private var showsPanel = false
    @Namespace private var zoom
    @Environment(\.dismiss) private var dismiss
    private let isClosable: Bool

    @Dependency(\.filterStore) private var filterStore
    @Dependency(\.userStore) private var userStore
    @Dependency(\.tagTranslationService) private var tagTranslationService
    @Dependency(\.accountSession) private var accountSession

    init(options: PartHarnessOptions = .atLaunch, isClosable: Bool = false) {
        _model = State(initialValue: PartHarnessModel(options: options))
        self.isClosable = isClosable
    }

    var body: some View {
        let options = model.options
        ZStack {
            Look(options.choices.look).surface.ignoresSafeArea()
            if model.isReady {
                PartHarnessStage(model: model)
                    .frame(maxWidth: options.width > 0 ? CGFloat(options.width) : .infinity)
                    .modifier(PartHarnessWidthClass(width: options.width))
                    // Another part, bar or presentation is another stage, built from scratch.
                    .id(model.stageID)
            } else {
                ProgressView()
            }
        }
        // At the top centre, clear of the top bar's buttons at both ends.
        .overlay(alignment: .top) {
            if options.showsPanelButton {
                Button { showsPanel = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.footnote)
                        .padding(8)
                        .glassSurface(in: .circle, isInteractive: true)
                }
                .accessibilityLabel(Text(verbatim: "Harness options"))
            }
        }
        .sheet(isPresented: $showsPanel) {
            PartHarnessPanel(model: model, close: isClosable ? { dismiss() } : nil)
                .presentationDetents([.medium, .large])
        }
        .lookEnvironment(Look(options.choices.look), accent: model.settings.accentColor)
        .preferredColorScheme(options.scheme == .system ? nil : (options.scheme == .dark ? .dark : .light))
        .dynamicTypeSize(options.usesLargestText ? DynamicTypeSize.accessibility5...DynamicTypeSize.accessibility5 : DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5)
        .environment(\.zoomNamespace, zoom)
        .environment(\.listFixtures, model.fixtures)
        .environment(model.settings)
        .environment(model.app.router)
        .environment(model.continueModel)
        .environment(filterStore)
        .environment(userStore)
        .environment(tagTranslationService)
        .environment(accountSession)
        .task { await model.prepare() }
        .task { await model.continueModel.observe() }
        .task { await model.runMemoryCheck() }
    }
}

/// The contract's size class follows the container, which the harness narrows.
private struct PartHarnessWidthClass: ViewModifier {
    let width: Int

    func body(content: Content) -> some View {
        if width > 0 {
            content.environment(\.horizontalSizeClass, width >= 700 ? .regular : .compact)
        } else {
            content
        }
    }
}

/// The part in its surroundings: the chosen bar's shell around one stack whose root is the
/// part, or what the part is opened from.
private struct PartHarnessStage: View {
    let model: PartHarnessModel

    @State private var search = CommandBarSearch()

    var body: some View {
        let options = model.options
        let router = model.app.router
        if options.part == .shell {
            // The whole shell, on the harness's settings: changing a part's design on the
            // panel is the change a user makes in Settings, under the real switch points.
            ShellRoot(model: model.app)
        } else {
            part(options: options, router: router)
        }
    }

    private func part(options: PartHarnessOptions, router: AppRouter) -> some View {
        Group {
            switch options.choices.bar {
            case .tabs:
                TabView {
                    Tab(options.part.rawValue.capitalized, systemImage: "square.dashed") {
                        if options.part == .start {
                            HomeStackHost(router: router.home)
                        } else {
                            StackHost(router: router.home) { PartHarnessRoot(model: model).tabsAccountButton() }
                        }
                    }
                    Tab("Other", systemImage: "circle") {
                        Color.clear
                    }
                }
                .modifier(TabsBarAccessoryHost(router: router, hasLeadingColumn: StartStructure.hasLeadingColumn(model.settings)))
                .environment(\.tabsBarKeepsLegacyAccessory, options.part != .search)
            case .command:
                commandStack(router: router)
                    .searchSurfaceCover(scope: $search.scope, over: router.home)
            }
        }
        .environment(\.chrome, ChromeContext(bar: options.choices.bar))
        .modifier(ShellPresentations(model: model.app, bar: options.choices.bar))
        .onAppear { model.open(search: $search) }
    }

    @ViewBuilder
    private func commandStack(router: AppRouter) -> some View {
        let bar: (BarControl?, @escaping (BarAction) -> Void) -> CommandBar = { control, perform in
            CommandBar(router: router, control: control, perform: perform) { search.scope = $0 }
        }
        if model.options.part == .start {
            HomeStackHost(router: router.home, hasBar: true, bar: bar)
        } else {
            StackHost(router: router.home, hasBar: true, root: { PartHarnessRoot(model: model) }, bar: bar)
        }
    }
}

/// The root of the stage's stack.
private struct PartHarnessRoot: View {
    let model: PartHarnessModel

    var body: some View {
        let options = model.options
        switch options.part {
        case .list:
            switch options.header {
            case .absent:
                GalleryListScreen(context: options.kind.context)
            case .empty, .tall:
                GalleryListScreen(context: options.kind.context) {
                    PartHarnessHeader(isTall: options.header == .tall)
                }
            }
        case .gallery, .start, .shell:
            // What a gallery is opened from: a list, whose covers are the zoom's sources.
            GalleryListScreen(context: .place(.frontpage))
        case .search:
            if options.choices.bar == .tabs {
                SearchSurface(scope: options.scope)
            } else {
                GalleryListScreen(context: .place(.frontpage))
            }
        case .library:
            LibraryScreen()
        }
    }
}

/// What a first screen or a library puts above a list's rows: here, two shelves' worth of
/// flat blocks, tall enough that the rows start below the fold on a small phone.
private struct PartHarnessHeader: View {
    let isTall: Bool
    @Environment(\.look) private var look

    var body: some View {
        if isTall {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: "Header")
                    .font(.title.bold())
                    .foregroundStyle(look.label)
                ForEach(0..<2, id: \.self) { _ in
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(0..<8, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 16).fill(look.surface).frame(width: 150, height: 104)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

extension PartHarnessListKind {
    var context: ListContext {
        switch self {
        case .frontpage: .place(.frontpage)
        case .popular: .place(.popular)
        case .watched: .place(.watched)
        case .toplists: .top
        case .history: .place(.history)
        case .folder: ListContext(kind: .folder(3), title: "Favorites 3")
        case .search: ListContext(kind: .search(keyword: "glacier", recordsHistory: false), title: "glacier")
        case .scoped: ListContext(kind: .scopedSearch(.favorites, keyword: "glacier"), title: "glacier")
        }
    }
}

// MARK: Model

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
        let defaults = UserDefaults(suiteName: Self.settingsSuite) ?? .standard
        defaults.removePersistentDomain(forName: Self.settingsSuite)
        settings = SettingsStore(defaults: defaults)
        settings.designChoices = options.choices
        settings.showsTagsInList = options.showsTags
        settings.wallDensity = options.density
        fixtures.state = options.state
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

    /// Opens what the options ask to see over the stage's root.
    func open(search: Binding<CommandBarSearch>) {
        let router = app.router
        switch options.part {
        case .gallery:
            guard let gallery = fixtures.gallery else { return }
            switch options.presentation {
            case .pushed: router.home.push(.detail(gallery))
            case .pane: router.home.open(gallery, inSidePane: true)
            case .sheet: router.present(gallery)
            }
        case .search where options.choices.bar == .command:
            search.wrappedValue.scope = options.scope
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
            stageID += 1
        }
    }
}

/// The harness's row in Laboratory.
struct PartHarnessLauncher: View {
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: { Text(verbatim: "Part harness") }
            .fullScreenCover(isPresented: $isPresented) {
                PartHarnessView(options: .default, isClosable: true)
            }
    }
}
#endif
