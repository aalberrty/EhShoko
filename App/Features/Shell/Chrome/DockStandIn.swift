import EhCore
import EhModels
import SwiftUI

// STAND-IN FOR THE DOCK TASK (F8). DELETE THIS FILE WHEN F8 IS MERGED.
//
// Everything here is declared, under the same names and with the same signatures, by F8's
// `App/DesignSystem/Controls/ActionDock.swift` and
// `App/Features/GalleryList/Shared/ListMoreMenu.swift`. The shell hosts whatever a screen
// declares and the bars share the dock's slots, so it needs these names before F8 lands. With
// both merged the names are declared twice and the build fails until this file is deleted;
// nothing else changes, because the shell uses only what F8 declares.
//
// The value types are F8's, copied. The two views are plain: a dock of flat shapes with no
// tinted glass pill, menus without their checked toggles.

// MARK: ActionDock.swift

/// A gallery page's bottom actions, drawn plainly until F8's `ActionDock` replaces this.
struct ActionDock: View {
    static let height: CGFloat = 52
    static let spacing: CGFloat = 8

    private let content: DockContent
    private let perform: (DockAction) -> Void

    @Environment(\.look) private var look
    @Environment(\.onTint) private var onTint
    @Environment(SettingsStore.self) private var settings

    init(content: DockContent, perform: @escaping (DockAction) -> Void) {
        self.content = content
        self.perform = perform
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            if let leading = content.leading {
                round(leading, slot: .leading)
            }
            Button { perform(content.primary.action) } label: {
                HStack(spacing: 6) {
                    if let systemImage = content.primary.systemImage {
                        Image(systemName: systemImage).imageScale(.small)
                    }
                    Text(content.primary.title).fontWeight(.semibold)
                    if let detail = content.primary.detail {
                        Text(detail).monospacedDigit().opacity(0.85)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(onTint)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: Self.height)
                // A flat fill in the look's tint, as a concrete colour: a dynamic accent goes
                // grey in an inspector shown as a sheet (`spikes/S5.md` section 5). F8's pill
                // is the prominent, tinted glass.
                .background(look.tint(for: settings.accentColor).tint, in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(!content.primary.isEnabled)
            .chromeShape(.centre, in: .capsule)
            trailing
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var trailing: some View {
        switch content.trailing {
        case .buttons(let items):
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                round(item, slot: index == items.count - 1 ? .trailing : .extra(index))
            }
        case .menu(let title, let systemImage, let menu):
            Menu {
                ForEach(Array(menu.sections.enumerated()), id: \.offset) { _, section in
                    Section {
                        ForEach(section.entries) { entry in
                            Button(entry.title) { perform(entry.action) }
                                .disabled(!entry.isEnabled)
                        }
                    }
                }
            } label: {
                symbol(systemImage)
            }
            .buttonStyle(.plain)
            .chromeShape(.trailing, in: .circle)
            .accessibilityLabel(title)
        case nil:
            EmptyView()
        }
    }

    private func round(_ item: DockItem, slot: ChromeSlot) -> some View {
        Button { perform(item.action) } label: { symbol(item.systemImage ?? "circle") }
            .buttonStyle(.plain)
            .disabled(!item.isEnabled)
            .chromeShape(slot, in: .circle)
            .accessibilityLabel(item.title)
    }

    private func symbol(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title3)
            .foregroundStyle(look.label)
            .frame(width: Self.height, height: Self.height)
            .contentShape(.circle)
    }
}

/// The slots the command bar and the dock share. A shape keeps its slot across the change
/// between them, which is what the morph matches.
nonisolated enum ChromeSlot: Hashable, Sendable {
    case leading, centre, trailing
    /// A further dock button before the trailing one. It has no counterpart in the bar.
    case extra(Int)
}

extension EnvironmentValues {
    /// The namespace the bottom chrome's shapes morph in. Set by the shell's bottom chrome
    /// around the command bar and the dock; `nil` elsewhere, where the shapes do not morph.
    @Entry var chromeNamespace: Namespace.ID? = nil
}

extension View {
    /// One shape of the bottom chrome in `slot`: interactive glass in `shape` (thin material
    /// on iOS 18), tagged so that it morphs with the shape in the same slot.
    func chromeShape(_ slot: ChromeSlot, in shape: some Shape) -> some View {
        glassSurface(in: shape, isInteractive: true, fallback: .thin)
            .chromeMorph(slot)
    }

    /// Tags a shape that brings its own glass with its chrome slot.
    func chromeMorph(_ slot: ChromeSlot) -> some View {
        modifier(ChromeMorphStandIn(slot: slot))
    }
}

private struct ChromeMorphStandIn: ViewModifier {
    let slot: ChromeSlot
    @Environment(\.chromeNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.glassMorphID(slot, in: namespace)
        } else {
            content
        }
    }
}

// MARK: ListMoreMenu.swift

/// What a list's More menu offers: every list control of `Design/designs/README.md`
/// section 5.3 but the design's own `form`. `nil` or `false` leaves an entry out.
nonisolated struct ListMenuControls: Equatable, Sendable {
    var filterSummary: FilterSummary?
    var sort: ListMenuPicker?
    var period: ListMenuPicker?
    var page: ListMenuPage?
    var quickSearch = false
    var find = false
    /// Clear History: `true` offers it, `false` shows it disabled, `nil` leaves it out.
    var clear: Bool?
    var reload = false

    init(
        filterSummary: FilterSummary? = nil, sort: ListMenuPicker? = nil, period: ListMenuPicker? = nil,
        page: ListMenuPage? = nil, quickSearch: Bool = false, find: Bool = false, clear: Bool? = nil,
        reload: Bool = false
    ) {
        self.filterSummary = filterSummary
        self.sort = sort
        self.period = period
        self.page = page
        self.quickSearch = quickSearch
        self.find = find
        self.clear = clear
        self.reload = reload
    }
}

/// One choice among a few, shown as a submenu with the current one checked. Options are
/// identified by an `Int` the list maps back.
nonisolated struct ListMenuPicker: Equatable, Sendable {
    struct Option: Equatable, Sendable, Identifiable {
        let id: Int
        let title: String

        init(id: Int, title: String) {
            self.id = id
            self.title = title
        }
    }

    var title: String
    var systemImage: String
    var options: [Option]
    var selection: Int?

    init(title: String, systemImage: String, options: [Option], selection: Int?) {
        self.title = title
        self.systemImage = systemImage
        self.options = options
        self.selection = selection
    }
}

/// Where a paged list (Toplists) is: "Yesterday · page 1 of 200".
nonisolated struct ListMenuPage: Equatable, Sendable {
    var title: String
    var current: Int
    var maximum: Int

    init(title: String, current: Int, maximum: Int) {
        self.title = title
        self.current = current
        self.maximum = maximum
    }
}

nonisolated enum ListMenuAction: Hashable, Sendable {
    case filters
    case sort(Int)
    case period(Int)
    case nextPage
    case previousPage
    case jumpToPage
    case quickSearch
    case find
    case clear
    case reload
}

/// The trailing "More" menu in a list screen's top bar, plainly, until F8's replaces it.
struct ListMoreMenu<Form: View>: View {
    private let controls: ListMenuControls
    private let perform: (ListMenuAction) -> Void
    private let form: Form

    init(
        controls: ListMenuControls, perform: @escaping (ListMenuAction) -> Void, @ViewBuilder form: () -> Form
    ) {
        self.controls = controls
        self.perform = perform
        self.form = form()
    }

    var body: some View {
        Menu {
            ListMenuEntries(controls: controls, perform: perform)
            form
        } label: {
            Label(L10n.Localizable.List.Action.more, systemImage: "ellipsis")
        }
    }
}

extension ListMoreMenu where Form == EmptyView {
    init(controls: ListMenuControls, perform: @escaping (ListMenuAction) -> Void) {
        self.init(controls: controls, perform: perform) { EmptyView() }
    }
}
