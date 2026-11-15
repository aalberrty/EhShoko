import EhFeatures
import SwiftUI

/// The command bar's leading capsule: where the user is, and the menu of the places to go to
/// (`wall.md` section 1). Its label slides sideways when the place changes, the way the place
/// lies in the menu's order, and gives way under a finger that swipes the bar.
struct CommandBarPlaceMenu: View {
    let places: CommandBarPlaces
    /// The place the bar names.
    let place: Place
    /// How far the label is pulled aside by a swipe in progress.
    let offset: CGFloat
    /// Whether the capsule may show the place's name. Without it, or where the name does not
    /// fit beside the field, it shows the symbol alone.
    let showsName: Bool
    let choose: (Place) -> Void
    let openSettings: () -> Void

    @State private var slide: CommandBarSlide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        places: CommandBarPlaces, place: Place, offset: CGFloat, showsName: Bool,
        choose: @escaping (Place) -> Void, openSettings: @escaping () -> Void
    ) {
        self.places = places
        self.place = place
        self.offset = offset
        self.showsName = showsName
        self.choose = choose
        self.openSettings = openSettings
        _slide = State(initialValue: CommandBarSlide(shown: place))
    }

    var body: some View {
        label
            // VoiceOver gets the menu, which carries the place's name.
            .accessibilityHidden(true)
            // The menu lies over the label and has no drawing of its own: a menu's label is
            // the system's to animate, and this one has to slide.
            .overlay { menu }
            .chromeShape(.leading, in: .capsule)
            .onChange(of: place) { _, place in
                slide.aim(at: place, direction: places.direction(from: slide.shown, to: place))
            }
            // One update after the direction: the label that leaves has then been drawn with
            // the way it leaves, which a view takes from the last time it was drawn.
            .onChange(of: slide.target) { _, target in
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3)) {
                    slide.shown = target
                }
            }
    }

    @ViewBuilder
    private var label: some View {
        if showsName {
            ViewThatFits(in: .horizontal) {
                placeLabel(showsName: true)
                placeLabel(showsName: false)
            }
        } else {
            placeLabel(showsName: false)
        }
    }

    private func placeLabel(showsName: Bool) -> some View {
        CommandBarPlaceLabel(
            place: slide.shown, title: places.title(of: slide.shown),
            systemImage: places.systemImage(of: slide.shown),
            direction: reduceMotion ? 0 : slide.direction, offset: reduceMotion ? 0 : offset, showsName: showsName
        )
    }

    private var menu: some View {
        Menu {
            Section {
                ForEach(places.entries, id: \.self) { entry in
                    Toggle(isOn: Binding(get: { places.isCurrent(entry, at: place) }, set: { _ in choose(entry) })) {
                        Label(places.title(of: entry), systemImage: places.systemImage(of: entry))
                    }
                }
            }
            Section {
                Button(L10n.Localizable.SettingView.Title.setting, systemImage: "gearshape", action: openSettings)
            }
        } label: {
            Color.clear.contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // The menu opens upward, and in this order the system lists it from the bar: the
        // first place nearest the thumb, Settings at the far end, above the divider. In the
        // written order Settings would be the entry under the thumb.
        .menuOrder(.priority)
        .accessibilityLabel(places.title(of: place))
        .accessibilityShowsLargeContentViewer {
            Label(places.title(of: place), systemImage: places.systemImage(of: place))
        }
    }
}

/// Which label the capsule draws and the way the next one comes in.
nonisolated struct CommandBarSlide: Equatable {
    /// The place whose label is drawn. It follows `target` one update later.
    var shown: Place
    /// The place the label is changing to.
    var target: Place
    /// 1: the next label comes in from the trailing side; -1: from the leading side; 0: it
    /// fades in place.
    var direction = 0

    init(shown: Place) {
        self.shown = shown
        target = shown
    }

    mutating func aim(at place: Place, direction: Int) {
        self.direction = direction
        target = place
    }
}

/// The capsule's content: the place's symbol and name, which slide, and the chevron, which
/// stays.
private struct CommandBarPlaceLabel: View {
    let place: Place
    let title: String
    let systemImage: String
    let direction: Int
    let offset: CGFloat
    let showsName: Bool

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                HStack(spacing: 7) {
                    Image(systemName: systemImage)
                        .font(.title3)
                    if showsName {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                .id(place)
                .transition(transition)
            }
            .offset(x: offset)
            .padding(.leading, showsName ? 14 : 0)
            .frame(minWidth: showsName ? nil : ActionDock.height)
            // A label on its way out ends at the capsule's edge and before the chevron.
            .clipped()
            if showsName {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(look.secondaryLabel)
            }
        }
        .foregroundStyle(look.label)
        // The field takes the width that is left, so the place's name keeps its own.
        .fixedSize()
        .padding(.trailing, showsName ? 13 : 0)
        .frame(minWidth: ActionDock.height, minHeight: ActionDock.height)
    }

    private var transition: AnyTransition {
        switch direction {
        case 1: .push(from: .trailing)
        case -1: .push(from: .leading)
        default: .opacity
        }
    }
}
