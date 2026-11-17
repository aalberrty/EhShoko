import EhFeatures
import Foundation
import Testing

/// Ledger's Index beside the list on regular width: where the list starts, and when the shell
/// hides or shows the Index itself. Widths are a 13-inch iPad's (a 320 pt Index in a 330 pt
/// column) unless a test says otherwise.
@Suite struct LeadingColumnLayoutTests {
    static let column: CGFloat = 320
    static let inset: CGFloat = 330

    /// The split view as the host sees it: a width is reported only when it changes, as
    /// `onGeometryChange` does.
    struct Host {
        var layout = LeadingColumnLayout()
        var split: CGFloat = 0
        var list: CGFloat = 0

        init(column: CGFloat = LeadingColumnLayoutTests.column) {
            _ = layout.measured(column: column)
        }

        /// One layout of the split view, `split` wide, with the list `list` wide; returns the
        /// change it asks for.
        @discardableResult
        mutating func layOut(split: CGFloat, list: CGFloat) -> LeadingColumnVisibility? {
            var change: LeadingColumnVisibility?
            if split != self.split {
                self.split = split
                change = layout.measured(split: split) ?? change
            }
            if list != self.list {
                self.list = list
                change = layout.measured(list: list) ?? change
            }
            return change
        }
    }

    /// Launched in portrait (1032 pt) with the Index beside the list.
    private func besideInPortrait() -> Host {
        var host = Host()
        host.layOut(split: 1032, list: 1032 - Self.inset)
        return host
    }

    // MARK: Measuring

    @Test func theListStartsPastTheIndexBesideIt() {
        let host = besideInPortrait()
        #expect(host.layout.listInset == Self.inset)
        #expect(!host.layout.isColumnOverList)
    }

    @Test func nothingIsDecidedBeforeBothWidthsAreKnown() {
        var layout = LeadingColumnLayout()
        #expect(layout.measured(column: Self.column) == nil)
        #expect(layout.measured(split: 1032) == nil)
        #expect(layout.listInset == 0)
        #expect(!layout.isColumnOverList)
    }

    @Test func aListWiderThanTheSplitViewIsAWidthAheadAndIgnored() {
        var host = besideInPortrait()
        // The list column has grown to the next layout's width before the split view has.
        #expect(host.layout.measured(list: 1100) == nil)
        #expect(host.layout.listInset == Self.inset)
    }

    @Test func anIndexLaidOverTheListAtLaunchCoversTheList() {
        // iOS 18 in portrait: the system lays the Index over the list from the start.
        var host = Host()
        #expect(host.layOut(split: 1032, list: 1032) == nil)
        #expect(host.layout.listInset == 0)
        #expect(host.layout.isColumnOverList)
    }

    // MARK: Losing the room beside the list

    @Test func theIndexIsHiddenWhenTheSystemLaysItOverTheList() {
        var host = besideInPortrait()
        // The split view narrows and the system lays the Index over the list.
        #expect(host.layOut(split: 578, list: 578) == .hidden)
        #expect(host.layout.listInset == 0)
        #expect(!host.layout.isColumnOverList)
    }

    @Test func aScreenPushedOntoTheListAtTheSplitViewsWidthKeepsTheIndex() {
        var host = besideInPortrait()
        // Search results pushed onto the list: laid out once as wide as the split view.
        #expect(host.layOut(split: 1032, list: 1032) == nil)
        #expect(host.layout.listInset == Self.inset)
        #expect(!host.layout.isColumnOverList)
        #expect(host.layOut(split: 1032, list: 1032 - Self.inset) == nil)
        #expect(host.layout.listInset == Self.inset)
    }

    // MARK: Showing it again

    @Test func theIndexComesBackAsWideAsItHasBeenBesideTheList() {
        var host = besideInPortrait()
        host.layOut(split: 578, list: 578)
        #expect(host.layOut(split: 1032, list: 1032) == .shown)
        // Coming back in beside the list, the list still measures its full width for a layout.
        #expect(!host.layout.isColumnOverList)
        #expect(host.layOut(split: 1032, list: 1032 - Self.inset) == nil)
        #expect(host.layout.listInset == Self.inset)
    }

    @Test func theIndexComesBackWhereAListAsWideAsTheIndexFits() {
        // First seen beside the list in a 1376 pt landscape split view, then hidden at 578.
        var host = Host()
        host.layOut(split: 1376, list: 1376 - Self.inset)
        #expect(host.layOut(split: 578, list: 578) == .hidden)
        // Narrower than any split it has been beside the list in, but room for both: 2 × 344.
        #expect(host.layOut(split: 700, list: 700) == .shown)
    }

    @Test func theIndexStaysHiddenWhereThereIsNoRoomForBoth() {
        var host = Host()
        host.layOut(split: 1376, list: 1376 - Self.inset)
        host.layOut(split: 578, list: 578)
        #expect(host.layOut(split: 650, list: 650) == nil)
        #expect(host.layout.listInset == 0)
    }

    @Test func aNarrowerSplitViewThanWhereItWasHiddenIsNoRoom() {
        var host = besideInPortrait()
        host.layOut(split: 578, list: 578)
        #expect(host.layOut(split: 560, list: 560) == nil)
        #expect(host.layout.listInset == 0)
    }

    @Test func anIndexShownAgainButLaidOverTheListIsHiddenAgain() {
        var host = besideInPortrait()
        host.layOut(split: 578, list: 578)
        host.layOut(split: 1032, list: 1032)
        // The next layout of the list: the system has laid the Index over it after all.
        #expect(host.layout.measured(list: 1032) == .hidden)
        #expect(!host.layout.isColumnOverList)
    }

    // MARK: The user's choice

    @Test func anIndexTheUserHidKeepsHiddenWhenThereIsRoom() {
        var host = besideInPortrait()
        host.layout.userChose(isShown: false)
        host.layOut(split: 1032, list: 1032)
        #expect(host.layOut(split: 1376, list: 1376) == nil)
        #expect(host.layout.listInset == 0)
    }

    @Test func anIndexTheSystemHidMidwayKeepsTheUsersLaterChoice() {
        var host = besideInPortrait()
        host.layOut(split: 578, list: 578)
        // The user hides it themselves (dismissing it), then the room comes back.
        host.layout.userChose(isShown: false)
        #expect(host.layOut(split: 1032, list: 1032) == nil)
    }

    @Test func anIndexTheUserLaysOverTheListCoversItAndStays() {
        var host = besideInPortrait()
        host.layOut(split: 578, list: 578)
        // The sidebar button shows it over the list: the host neither hides it nor counts it
        // beside the list.
        host.layout.userChose(isShown: true)
        #expect(host.layout.measured(list: 578) == nil)
        #expect(host.layout.isColumnOverList)
        #expect(host.layout.listInset == 0)
    }

    // MARK: Resizing a window

    @Test func aWidthBetweenLayoutsDoesNotCountAsBesideTheList() {
        var host = besideInPortrait()
        // A resize passes a layout where the list starts 165 pt in: not the Index beside it.
        host.layOut(split: 650, list: 485)
        #expect(host.layout.listInset == 165)
        #expect(host.layOut(split: 578, list: 578) == .hidden)
        // Had 650 counted as beside the list, 660 would show the Index again; room for both is 688.
        #expect(host.layOut(split: 660, list: 660) == nil)
    }

    @Test func theNarrowestSplitBesideTheListIsRemembered() {
        var host = Host()
        host.layOut(split: 680, list: 680 - Self.inset)
        host.layOut(split: 578, list: 578)
        // Narrower than room for both (688), but the Index has been beside the list at 680.
        #expect(host.layOut(split: 680, list: 680) == .shown)
    }

    // MARK: A side pane opening

    @Test func aPaneThatLeavesNoRoomHidesTheIndexBeforeTheSplitViewNarrows() {
        var host = besideInPortrait()
        #expect(host.layout.sidePane(width: 454) == .hidden)
        #expect(host.layout.listInset == 0)
        #expect(!host.layout.isColumnOverList)
    }

    @Test func theOldWidthsWhileThePaneOpensDoNotShowTheIndexAgain() {
        var host = besideInPortrait()
        host.layout.sidePane(width: 454)
        // The system hides the Index before the pane has taken its room.
        #expect(host.layOut(split: 1032, list: 1032) == nil)
        #expect(host.layOut(split: 800, list: 800) == nil)
        #expect(host.layOut(split: 578, list: 578) == nil)
        #expect(host.layout.listInset == 0)
    }

    @Test func theIndexComesBackWhenThePaneCloses() {
        var host = besideInPortrait()
        host.layout.sidePane(width: 454)
        host.layOut(split: 1032, list: 1032)
        host.layOut(split: 578, list: 578)
        #expect(host.layout.sidePane(width: 0) == nil)
        #expect(host.layOut(split: 1032, list: 1032) == .shown)
    }

    @Test func theIndexComesBackInLandscapeWithThePaneOpen() {
        var host = besideInPortrait()
        host.layout.sidePane(width: 454)
        host.layOut(split: 578, list: 578)
        // Rotated: 1376 − 520 leaves room for both.
        #expect(host.layOut(split: 856, list: 856) == .shown)
    }

    @Test func aPaneThatClosesBeforeTakingItsRoomGivesTheIndexBack() {
        var host = besideInPortrait()
        host.layout.sidePane(width: 454)
        host.layOut(split: 1032, list: 1032)
        #expect(host.layout.sidePane(width: 0) == .shown)
        #expect(!host.layout.isColumnOverList)
        #expect(host.layOut(split: 1032, list: 1032 - Self.inset) == nil)
        #expect(host.layout.listInset == Self.inset)
    }

    @Test func aPaneThatLeavesRoomForBothKeepsTheIndex() {
        // The iPad mini in landscape: a 270 pt Index, a 498 pt pane in 1133 leaves 635 ≥ 588.
        var host = Host(column: 270)
        host.layOut(split: 1133, list: 1133 - 280)
        #expect(host.layout.sidePane(width: 498) == nil)
        #expect(host.layOut(split: 635, list: 635 - 280) == nil)
        #expect(host.layout.listInset == 280)
    }

    @Test func aPaneWhereTheIndexHasBeenBesideTheListKeepsIt() {
        var host = Host()
        host.layOut(split: 600, list: 600 - Self.inset)
        host.layOut(split: 1032, list: 1032 - Self.inset)
        #expect(host.layout.sidePane(width: 432) == nil)
    }

    @Test func aPaneChangesNothingWhileTheIndexIsNotBesideTheList() {
        var hidden = besideInPortrait()
        hidden.layout.userChose(isShown: false)
        hidden.layOut(split: 1032, list: 1032)
        #expect(hidden.layout.sidePane(width: 454) == nil)

        var over = Host()
        over.layOut(split: 1032, list: 1032)
        #expect(over.layout.sidePane(width: 454) == nil)
        #expect(over.layout.isColumnOverList)
    }

    @Test func theUsersChoiceWhileThePaneOpensWins() {
        var host = besideInPortrait()
        host.layout.sidePane(width: 454)
        host.layOut(split: 1032, list: 1032)
        // The sidebar button: the Index over the list, kept there as the pane takes its room.
        host.layout.userChose(isShown: true)
        #expect(host.layOut(split: 578, list: 578) == nil)
        #expect(host.layout.isColumnOverList)
        #expect(host.layout.sidePane(width: 0) == nil)
    }
}
