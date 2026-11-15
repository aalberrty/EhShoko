import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The command bar: the place menu, the search field and one trailing control, three glass
/// shapes in the bottom chrome's container (`wall.md` section 1). Each shape is tagged with
/// its slot, which is what lets it turn into the dock's shape in the same slot.
///
/// The bar draws the shapes and moves between places; the bottom chrome places it, keeps it
/// across pushes and decides when it gives way to a gallery's dock. It reads the router only
/// for the place and the top route, so it is drawn again when the user navigates and never
/// while a list scrolls under it.
struct CommandBar: View {
    let router: AppRouter
    /// What the top screen put in the trailing circle, if anything.
    let control: BarControl?
    let perform: (BarAction) -> Void
    let openSearch: (SearchScope) -> Void

    /// The sideways travel of a swipe in progress along the bar. It goes back to zero when
    /// the finger lifts, and when the system takes the touch away.
    @GestureState(resetTransaction: Transaction(animation: .snappy(duration: 0.25))) private var pull: CGFloat = 0
    /// Counts the places changed by a swipe, for the tick that confirms each.
    @State private var steps = 0

    @Environment(SettingsStore.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let places = CommandBarPlaces(
            start: StartStructure.style(settings),
            hasLeadingColumn: StartStructure.hasLeadingColumn(settings) && sizeClass == .regular
        )
        let top = router.home.path.last
        let place = places.shown(router.place)
        let field = places.field(top: top, place: router.place)
        let showsMenu = places.showsMenu(isAtRoot: top == nil)
        HStack(spacing: ActionDock.spacing) {
            if showsMenu {
                CommandBarPlaceMenu(
                    places: places, place: place, offset: labelOffset(in: places, at: place),
                    // Under very large text the capsule shows its symbol only.
                    showsName: !typeSize.isAccessibilitySize,
                    choose: { go(to: $0, in: places) }, openSettings: { router.presentSettings() }
                )
                // The place's name is offered what the field can spare before the field
                // takes the rest: it is shown whole or not at all, never squeezed.
                .layoutPriority(1)
            }
            CommandBarSearchField(field: field) { openSearch(field.scope) }
            if let control {
                CommandBarTrailingControl(control: control, perform: perform)
            }
        }
        .frame(height: ActionDock.height)
        // The bar keeps its height, as the system's bars do: its text stops growing here, and
        // a long press shows any of the three in the large content viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // The gaps between the shapes belong to the bar too, so a swipe may start on them.
        .contentShape(.rect)
        // High priority: as a plain gesture the field's tap wins and the swipe never
        // starts; as a simultaneous one a swipe on the field also opens search.
        .highPriorityGesture(swipe(in: places, from: place))
        // The menu comes and goes with Ledger's Index, a navigation later than the bottom
        // chrome's own change of the trailing control, and in step with it.
        .animation(.smooth(duration: 0.4), value: showsMenu)
        .sensoryFeedback(.selection, trigger: steps)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Localizable.Shell.Bar.accessibility)
    }

    // MARK: Moving between places

    private func go(to entry: Place, in places: CommandBarPlaces) {
        router.go(to: places.destination(for: entry, from: router.place), start: places.start)
    }

    private var isRightToLeft: Bool { layoutDirection == .rightToLeft }

    private func swipe(in places: CommandBarPlaces, from place: Place) -> some Gesture {
        DragGesture(minimumDistance: CommandBarSwipe.minimumDistance)
            .updating($pull) { value, pull, _ in
                pull = CommandBarSwipe.pull(value.translation)
            }
            .onEnded { value in
                guard
                    let step = CommandBarSwipe.step(predictedEnd: value.predictedEndTranslation, isRightToLeft: isRightToLeft),
                    let next = places.neighbour(of: place, by: step)
                else { return }
                steps += 1
                go(to: next, in: places)
            }
    }

    private func labelOffset(in places: CommandBarPlaces, at place: Place) -> CGFloat {
        guard pull != 0 else { return 0 }
        let heading = CommandBarSwipe.heading(pull: pull, isRightToLeft: isRightToLeft)
        return CommandBarSwipe.labelOffset(pull: pull, hasNeighbour: places.neighbour(of: place, by: heading) != nil)
    }
}
