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
/// Nothing here observes anything but the Favourite tip's anchor, which reads the folder a tap
/// saves to: the dock changes only when its content value does, so it adds no work while the
/// screen under it scrolls. Menus build their entries when opened.
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
        // The command bar's rule, for the shapes it morphs into: the dock keeps its height, its
        // text and symbols stop growing at the largest standard size, and a long press shows
        // any button in the large content viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
            .menuOrder(.fixed)
            .buttonStyle(.plain)
            .chromeShape(.trailing, in: .circle)
            .accessibilityLabel(title)
            .walkIdentifier("dock.menu")
            .accessibilityShowsLargeContentViewer { Label(title, systemImage: systemImage) }
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

    /// An identifier the UI walks find a control by (`UITests/`), where its label is not enough
    /// (Wall's More beside a list's More, the reader's Close over a gallery page's); only in
    /// builds with the harness.
    @ViewBuilder
    func walkIdentifier(_ identifier: String) -> some View {
        #if DEBUG || HARNESS
        accessibilityIdentifier(identifier)
        #else
        self
        #endif
    }

    /// The button the Favourite tip points at (`README.md` section 5.4): the tip's
    /// `popoverTip` is attached here when `isAnchor` (`FavoriteTip`).
    fileprivate func favoriteTipAnchor(_ isAnchor: Bool) -> some View {
        accessibilityIdentifier(isAnchor ? "dock.favorite.tip-anchor" : "dock.favorite")
            .favoriteTip(isAnchor: isAnchor)
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
            .accessibilityShowsLargeContentViewer {
                Label(item.title, systemImage: item.systemImage ?? "circle")
            }
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
            // Menus open upward from the dock, where the system would list them bottom-up;
            // fixed keeps the order the design wrote (folder 0 at the top).
            .menuOrder(.fixed)
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

/// The tinted pill, taking the width the round buttons leave and never more: when the title
/// and the detail do not fit (a 372 pt side pane), it shows the title alone, and VoiceOver
/// still reads both. A design that wants a shorter detail there passes one ("23 / 48").
///
/// A pill that opens a reader marks its label as where the reader zooms out of; the marker
/// goes inside the glass, where it takes effect (`spikes/S4.md`).
private struct DockPill: View {
    let item: DockItem
    let perform: (DockAction) -> Void
    @Environment(\.lookTint) private var tint

    /// The label's height inside the prominent style's padding at the large control size
    /// (measured: about 27 pt in all), so that the pill is as tall as the round buttons.
    private static let labelHeight: CGFloat = ActionDock.height - 27
    /// A dimmed pill's tint and label. Glass ignores `opacity` on the button, so the pill is
    /// dimmed through its tint, which the glass and iOS 18's filled pill both follow.
    private static let dimmedTint = 0.4
    private static let dimmedLabel = 0.75

    var body: some View {
        Button { perform(item.action) } label: { markedLabel }
            .glassProminentButtonStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            // The concrete colour, not the inherited accent, which turns grey in an
            // inspector shown as a sheet on iOS 26.
            .tint(item.isDimmed ? tint.opacity(Self.dimmedTint) : tint)
            .accessibilityLabel([item.title, item.spokenDetail ?? item.detail].compactMap(\.self).joined(separator: ", "))
            .walkIdentifier("dock.pill")
            .accessibilityShowsLargeContentViewer {
                Text([item.title, item.detail].compactMap(\.self).joined(separator: " "))
            }
            .disabled(!item.isEnabled)
            .chromeMorph(.centre)
    }

    @ViewBuilder
    private var markedLabel: some View {
        if let gid = item.readerGalleryID {
            label.readerSource(.dock(gid: gid))
        } else {
            label
        }
    }

    private var label: some View {
        ViewThatFits(in: .horizontal) {
            line(showsDetail: true)
            line(showsDetail: false)
        }
        .font(.body)
        .lineLimit(1)
        .opacity(item.isDimmed ? Self.dimmedLabel : 1)
        .padding(.horizontal, Tokens.Spacing.xSmall)
        .frame(maxWidth: .infinity, minHeight: Self.labelHeight)
        .contentTransition(.interpolate)
    }

    private func line(showsDetail: Bool) -> some View {
        HStack(spacing: Tokens.Spacing.xSmall + 2) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(item.title)
                .fontWeight(.semibold)
            if showsDetail, let detail = item.detail {
                Text(detail)
                    .monospacedDigit()
                    .opacity(0.85)
            }
        }
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
