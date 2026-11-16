import Foundation

/// Whether the shell asks for the leading column (Ledger's Index beside the list on regular
/// width) to be shown or hidden. The app maps it to the split view's own visibility.
public nonisolated enum LeadingColumnVisibility: Equatable, Sendable {
    case shown
    case hidden
}

/// Where the list column of Ledger's split view starts, from the split view's width and the
/// list column's rather than from the column's visibility, which says "shown" both when the
/// Index is beside the list and when it lies over it.
///
/// When the list loses the room beside the Index without a size transition (a side pane
/// opening in portrait), the system lays the Index over the list and keeps the visibility at
/// "shown", so the list's chrome stays covered until the Index is dismissed. The host hides the
/// Index instead, as the system does itself on a rotation, and shows it again when the split
/// view is wide enough: as wide as the Index has been beside the list in, or wide enough for a
/// list as wide as the Index (where the system has been seen to tile them: a 355 pt list beside
/// the iPad mini's 280 pt Index, never a 248 pt one beside the 13-inch's 330). If the system
/// lays it over the list all the same, it is hidden again. A choice the user makes with the
/// column's button stays as they made it. While a window is resized the two widths pass
/// through values that belong to no layout, so only an inset as wide as the Index counts as
/// the Index beside the list.
///
/// A side pane that is about to open is known before the split view narrows: when the room it
/// leaves is too small by the same rule, the Index is hidden in the same update that opens the
/// pane, so it is never laid over the list for a layout.
public nonisolated struct LeadingColumnLayout: Equatable, Sendable {
    private var split: CGFloat = 0
    private var list: CGFloat = 0
    /// The Index's content, which is as wide as its column without the margins around it.
    private var column: CGFloat = 0
    /// How far the list starts from the split view's leading edge in the last layout whose two
    /// widths agree.
    private var measuredInset: CGFloat = 0
    private var isMeasured = false
    private var isShown = true
    /// The narrowest split view the Index has been beside the list in.
    private var narrowestBeside = CGFloat.infinity
    /// The split view's width when the host hid the Index for want of room, until it shows it
    /// again or the user changes the column.
    private var hiddenAt: CGFloat?
    /// The host has just shown the Index again, and it is coming in beside the list.
    private var isReturning = false
    /// The host hid the Index for a side pane that is opening, and the split view has not yet
    /// narrowed to the width the pane leaves it: its wider widths are the old layout's.
    private var awaitsPane = false

    /// What the system puts around the Index's content: 10 pt for iOS 26's floating sidebar.
    static let columnMargins: CGFloat = 24

    public init() {}

    /// How far the list column starts from the split view's leading edge: the Index's width
    /// while it is beside the list, zero while it is hidden or over the list.
    public var listInset: CGFloat { isShown ? measuredInset : 0 }

    /// The Index is shown but lies over the list.
    public var isColumnOverList: Bool { isShown && isMeasured && measuredInset == 0 && !isReturning }

    /// The split view, the list column or the Index was laid out. Each returns the visibility
    /// the host sets, if it changes it.
    public mutating func measured(split: CGFloat) -> LeadingColumnVisibility? {
        self.split = split
        return settle()
    }

    public mutating func measured(list: CGFloat) -> LeadingColumnVisibility? {
        self.list = list
        return settle()
    }

    public mutating func measured(column: CGFloat) -> LeadingColumnVisibility? {
        self.column = column
        return settle()
    }

    /// The user showed or hid the Index: with the column's button, or by dismissing the Index
    /// laid over the list.
    public mutating func userChose(isShown: Bool) {
        self.isShown = isShown
        hiddenAt = nil
        awaitsPane = false
    }

    /// The side pane beside the split view opens `width` wide, or closes (zero). Returns
    /// `.hidden` when the Index is beside the list and the room the pane leaves would not hold
    /// both.
    public mutating func sidePane(width: CGFloat) -> LeadingColumnVisibility? {
        guard width > 0 else {
            guard awaitsPane else { return nil }
            // The pane closed before it took its room: the Index never lacked it.
            awaitsPane = false
            hiddenAt = nil
            isShown = true
            isReturning = true
            return .shown
        }
        let isBeside = isMeasured && isShown && measuredInset > 0
        guard isBeside, column > 0, split > width else { return nil }
        let room = split - width
        guard room < narrowestBeside, room < Self.roomForBoth(column: column) else { return nil }
        isShown = false
        hiddenAt = room
        awaitsPane = true
        return .hidden
    }

    /// A split view wide enough for a list as wide as the Index.
    private static func roomForBoth(column: CGFloat) -> CGFloat {
        2 * (column + columnMargins)
    }

    private mutating func settle() -> LeadingColumnVisibility? {
        // The two are measured in separate layouts: a list wider than the split view is one
        // width ahead of the other.
        guard list > 0, split > 0, list <= split + 1 else { return nil }
        let inset = split - list > 1 ? split - list : 0
        let wasBeside = isMeasured && isShown && measuredInset > 0
        let wasReturning = isReturning
        isMeasured = true
        isReturning = false
        measuredInset = inset
        if awaitsPane, let hiddenAt, split <= hiddenAt + 1 {
            awaitsPane = false
        }
        if isShown, inset > 0 {
            if abs(inset - column) <= Self.columnMargins {
                narrowestBeside = min(narrowestBeside, split)
            }
        } else if isShown, wasBeside || wasReturning {
            isShown = false
            hiddenAt = split
            return .hidden
        } else if !isShown, !awaitsPane, inset == 0, column > 0, let hiddenAt, split > hiddenAt,
                  split >= min(narrowestBeside, Self.roomForBoth(column: column)) {
            self.hiddenAt = nil
            isShown = true
            isReturning = true
            return .shown
        }
        return nil
    }
}
