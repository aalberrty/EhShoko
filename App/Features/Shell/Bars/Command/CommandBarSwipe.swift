import CoreGraphics

/// The sideways swipe along the command bar, which goes to the next or the previous place
/// (`wall.md` section 1). The numbers are the ones the bottom chrome spike settled on: the
/// drag starts after 14 pt, so a tap on the menu, the field or the trailing control stays a
/// tap, and it changes the place when it would come to rest more than 60 pt away.
nonisolated enum CommandBarSwipe {
    static let minimumDistance: CGFloat = 14
    static let stepDistance: CGFloat = 60

    /// The finger's sideways travel; none for a drag that goes more up or down than sideways.
    static func pull(_ translation: CGSize) -> CGFloat {
        abs(translation.width) > abs(translation.height) ? translation.width : 0
    }

    /// The step a finished drag asks for: 1 for the next place, -1 for the previous one,
    /// `nil` for a drag that was too short or not sideways. The next place lies where the
    /// text runs to, so the finger pulls it in from there.
    static func step(predictedEnd: CGSize, isRightToLeft: Bool) -> Int? {
        let travel = pull(predictedEnd)
        guard abs(travel) > stepDistance else { return nil }
        return (travel < 0) != isRightToLeft ? 1 : -1
    }

    /// The step a pull is heading for, before it has gone far enough to count.
    static func heading(pull: CGFloat, isRightToLeft: Bool) -> Int {
        pull == 0 ? 0 : ((pull < 0) != isRightToLeft ? 1 : -1)
    }

    /// How far the place's label follows the finger. It gives way a little, enough to show
    /// that the bar moves; where there is no place to go to it barely moves at all.
    static func labelOffset(pull: CGFloat, hasNeighbour: Bool) -> CGFloat {
        let limit: CGFloat = hasNeighbour ? 28 : 6
        let follow = pull * (hasNeighbour ? 0.4 : 0.1)
        return min(max(follow, -limit), limit)
    }
}
