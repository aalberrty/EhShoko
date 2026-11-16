#if DEBUG || HARNESS
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The part in its surroundings: the chosen bar's shell around one stack whose root is the
/// part, or what the part is opened from.
struct PartHarnessStage: View {
    let model: PartHarnessModel

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
                tabs(options: options, router: router)
            case .command:
                PartHarnessCommandStack(model: model, router: router)
            }
        }
        .environment(\.chrome, ChromeContext(bar: options.choices.bar))
        .modifier(ShellPresentations(model: model.app, bar: options.choices.bar))
        .onAppear { model.open() }
    }

    /// Under `tabs`, the part is in the tab the shell puts it in, on that tab's stack and with
    /// what the shell adds around it (`TabsShell`): so the accessory, the capsule, the account
    /// button and re-selection follow that tab's rules. One other tab stands beside it.
    private func tabs(options: PartHarnessOptions, router: AppRouter) -> some View {
        let tab = options.tab
        return TabView(selection: tabSelection) {
            Tab(options.part.rawValue.capitalized, systemImage: "square.dashed", value: tab, role: tab == .search ? .search : nil) {
                tabStack(tab, router: router)
                    .modifier(TabsBarStack(tab: tab))
                    // Continue is not on the search surface, only on the results pushed over it.
                    .environment(\.tabsBarHoldsSearchSurface, tab == .search)
            }
            Tab("Other", systemImage: "circle", value: tab == .home ? AppTab.watched : AppTab.home) {
                Color.clear
            }
        }
        .modifier(TabsBarAccessoryHost(router: router, hasLeadingColumn: StartStructure.hasLeadingColumn(model.settings)))
        .environment(\.tabsBarKeepsLegacyAccessory, true)
    }

    @ViewBuilder
    private func tabStack(_ tab: AppTab, router: AppRouter) -> some View {
        switch tab {
        case .home where model.options.part == .start:
            HomeStackHost(router: router.home)
        case .library:
            StackHost(router: router.library) { PartHarnessLibraryTab().tabsAccountButton() }
        case .search, .top:
            // No account button: the shell gives these two none.
            StackHost(router: router.stack(for: tab)) { PartHarnessRoot(model: model) }
        case .home, .watched:
            StackHost(router: router.stack(for: tab)) { PartHarnessRoot(model: model).tabsAccountButton() }
        }
    }

    /// Through the app's model, as the shell's selection: re-selecting the tab pops it to its
    /// root, or reloads the root.
    private var tabSelection: Binding<AppTab> {
        Binding(get: { model.app.router.selectedTab }, set: { model.app.selectTab($0) })
    }

}

/// The part's stack under `command`, with the search surface the bar opens. The surface's
/// state is here rather than on the stage, so it lives only while the `command` bar does, as
/// the shell's own (`CommandShell`): the memory check finds none of it under `tabs`.
private struct PartHarnessCommandStack: View {
    let model: PartHarnessModel
    let router: AppRouter

    @State private var search = CommandBarSearch()

    var body: some View {
        stack
            .searchSurfaceCover(scope: $search.scope, over: router.home)
            .onAppear {
                // The search part opens on the surface, in the scope asked for.
                if model.options.part == .search {
                    search.scope = model.options.scope
                }
            }
    }

    @ViewBuilder
    private var stack: some View {
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

/// The Library tab's root under `tabs`: its switch over the library part and History. The
/// switch lives only while the Library tab does, so the memory check never finds it under
/// another part or bar.
private struct PartHarnessLibraryTab: View {
    @State private var library = TabsBarLibrarySwitch()

    var body: some View {
        TabsBarLibraryTab(library: library)
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
            // Under `tabs` the Library tab's root holds it (`PartHarnessStage`).
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
#endif
