import SwiftUI

/// A gallery page's bottom actions: a round Favourite button, the tinted pill, and what follows
/// it (`Design/designs/README.md` section 5.4). It draws a `DockContent` and reports taps;
/// the page that declared the content performs them.
///
/// The shell's bottom chrome places it, once per stack, in the bar's place: inside the same
/// `GlassGroup` as the command bar, with each shape tagged by the bar's slot (`chromeShape`),
/// so under `command` the bar's three shapes morph into these three (`spikes/S2.md`). It
/// creates no container of its own: two containers could not morph into each other. On
/// iOS 26 the round buttons are interactive glass and the pill the prominent glass in the
/// tint; on iOS 18, material circles and a pill filled with the tint.
///
/// Nothing here observes anything: the dock changes only when its content value does, so it
/// adds no work while the screen under it scrolls. Menus build their entries when opened.
struct ActionDock: View {
    /// The dock's height, the command bar's: the morph keeps the shapes on one line.
    static let height: CGFloat = 52
    static let spacing: CGFloat = 8

    private let content: DockContent
    private let perform: (DockAction) -> Void

    init(content: DockContent, perform: @escaping (DockAction) -> Void) {
        self.content = content
        self.perform = perform
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            if let leading = content.leading {
                DockRoundButton(item: leading, slot: .leading, perform: perform)
                    .favoriteTipAnchor(content.anchorsFavoriteTip)
            }
            DockPill(item: content.primary, perform: perform)
            trailing
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var trailing: some View {
        switch content.trailing {
        case .buttons(let items):
            // The last button holds the trailing slot, so it is the one that morphs into the
            // command bar's trailing circle; any before it (Ledger's Rate) come and go.
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let slot: ChromeSlot = index == items.count - 1 ? .trailing : .extra(index)
                DockRoundButton(item: item, slot: slot, perform: perform)
            }
        case .menu(let title, let systemImage, let menu):
            Menu {
                DockMenuContent(menu: menu, perform: perform)
            } label: {
                DockSymbol(systemImage: systemImage, isDimmed: false)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .chromeShape(.trailing, in: .circle)
            .accessibilityLabel(title)
        case nil:
            EmptyView()
        }
    }
}

// MARK: The shapes

/// The slots the command bar and the dock share. A shape keeps its slot across the change
/// between them, which is what the morph matches.
nonisolated enum ChromeSlot: Hashable, Sendable {
    case leading, centre, trailing
    /// A further dock button before the trailing one (Ledger's Rate on regular width). It has
    /// no counterpart in the bar, so it dissolves in and out.
    case extra(Int)
}

extension EnvironmentValues {
    /// The namespace the bottom chrome's shapes morph in. Set by the shell's bottom chrome
    /// around the command bar and the dock; `nil` elsewhere, where the shapes do not morph.
    @Entry var chromeNamespace: Namespace.ID? = nil
}

extension View {
    /// One shape of the bottom chrome in `slot`: interactive glass in `shape` (thin material
    /// on iOS 18, as the command bar's capsules), tagged so that it morphs with the shape in
    /// the same slot of the bar or the dock (`glassMorphID`).
    func chromeShape(_ slot: ChromeSlot, in shape: some Shape) -> some View {
        glassSurface(in: shape, isInteractive: true, fallback: .thin)
            .chromeMorph(slot)
    }

    /// Tags a shape that brings its own glass (the pill's prominent button style) with its
    /// chrome slot.
    func chromeMorph(_ slot: ChromeSlot) -> some View {
        modifier(ChromeMorph(slot: slot))
    }

    /// The button the Favourite tip points at (`README.md` section 5.4): the tip's
    /// `popoverTip` is attached here when `isAnchor`.
    fileprivate func favoriteTipAnchor(_ isAnchor: Bool) -> some View {
        accessibilityIdentifier(isAnchor ? "dock.favorite.tip-anchor" : "dock.favorite")
    }
}

private struct ChromeMorph: ViewModifier {
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

// MARK: The buttons

/// A round button: a tap performs its action; with a menu, a long press opens the menu
/// (Favourite: a tap saves to the folder used last, a long press chooses the folder).
private struct DockRoundButton: View {
    let item: DockItem
    let slot: ChromeSlot
    let perform: (DockAction) -> Void

    var body: some View {
        control
            .buttonStyle(.plain)
            .disabled(!item.isEnabled)
            .chromeShape(slot, in: .circle)
            .accessibilityLabel(item.title)
    }

    @ViewBuilder
    private var control: some View {
        let symbol = DockSymbol(systemImage: item.systemImage ?? "circle", isDimmed: item.isDimmed)
        if let menu = item.menu {
            Menu {
                DockMenuContent(menu: menu, perform: perform)
            } label: {
                symbol
            } primaryAction: {
                perform(item.action)
            }
            .menuStyle(.button)
        } else {
            Button { perform(item.action) } label: { symbol }
        }
    }
}

private struct DockSymbol: View {
    let systemImage: String
    let isDimmed: Bool
    @Environment(\.look) private var look
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3)
            .foregroundStyle(isDimmed || !isEnabled ? look.tertiaryLabel : look.label)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: ActionDock.height, height: ActionDock.height)
            .contentShape(.circle)
    }
}

/// The tinted pill, taking the width the round buttons leave.
private struct DockPill: View {
    let item: DockItem
    let perform: (DockAction) -> Void

    /// The label's height inside the prominent style's padding, so that the pill is as tall as
    /// the round buttons.
    private static let labelHeight: CGFloat = 38

    var body: some View {
        Button { perform(item.action) } label: { label }
            .glassProminentButtonStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(!item.isEnabled)
            .opacity(item.isDimmed ? 0.6 : 1)
            .chromeMorph(.centre)
    }

    private var label: some View {
        HStack(spacing: Tokens.Spacing.xSmall + 2) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(item.title)
                .fontWeight(.semibold)
            if let detail = item.detail {
                Text(detail)
                    .monospacedDigit()
                    .opacity(0.85)
            }
        }
        .font(.body)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, Tokens.Spacing.xSmall)
        .frame(maxWidth: .infinity, minHeight: Self.labelHeight)
        .contentTransition(.interpolate)
    }
}

/// A dock menu's entries, built when the menu opens. A selected entry is a checked toggle, as
/// the system marks the current choice in a menu.
private struct DockMenuContent: View {
    let menu: DockMenu
    let perform: (DockAction) -> Void

    var body: some View {
        ForEach(Array(menu.sections.enumerated()), id: \.offset) { _, section in
            if let title = section.title {
                Section(title) { entries(section.entries) }
            } else {
                Section { entries(section.entries) }
            }
        }
    }

    private func entries(_ entries: [DockMenuEntry]) -> some View {
        ForEach(entries) { entry in
            Group {
                if entry.isSelected {
                    Toggle(isOn: Binding(get: { true }, set: { _ in perform(entry.action) })) {
                        DockMenuLabel(entry: entry)
                    }
                } else {
                    Button(role: entry.isDestructive ? .destructive : nil) {
                        perform(entry.action)
                    } label: {
                        DockMenuLabel(entry: entry)
                    }
                }
            }
            .disabled(!entry.isEnabled)
        }
    }
}

private struct DockMenuLabel: View {
    let entry: DockMenuEntry

    var body: some View {
        if let systemImage = entry.systemImage {
            Label(entry.title, systemImage: systemImage)
        } else {
            Text(entry.title)
        }
    }
}
