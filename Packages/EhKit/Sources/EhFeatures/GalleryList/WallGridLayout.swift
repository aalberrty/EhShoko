import CoreGraphics
import EhModels

/// The geometry of Wall's cover wall at one width and density: how many columns, how large a
/// cell is, and how far apart its rows are.
///
/// Every cell of a density has one height, given and not measured, so where a row is down the
/// wall is arithmetic (`WallGridMap`). That is what lets a density change keep the row at the
/// top in place without asking the lazy grid where anything is.
nonisolated public struct WallGridLayout: Sendable, Equatable {
    /// The wall's margin at each side.
    public static let margin: CGFloat = 6
    /// A cover's width over its height.
    public static let coverAspect: CGFloat = 7 / 10

    public let density: WallDensity
    public let columns: Int
    public let columnSpacing: CGFloat
    /// The space under each row. It is part of the cell, so the grid adds none of its own.
    public let rowSpacing: CGFloat
    public let cellWidth: CGFloat
    /// The cover's height, on whole pixels, so that rows add up without rounding.
    public let coverHeight: CGFloat
    /// The caption's height under the cover; 0 where the density has no caption.
    public let captionHeight: CGFloat

    /// From one row's top to the next row's.
    public var pitch: CGFloat { coverHeight + captionHeight + rowSpacing }

    /// - Parameters:
    ///   - width: the container's width.
    ///   - captionHeight: the caption's height at the current text size.
    ///   - usesLargeText: an accessibility text size, where captions need wider cells.
    ///   - displayScale: pixels per point.
    public init(
        width: CGFloat, density: WallDensity, captionHeight: CGFloat, usesLargeText: Bool = false,
        displayScale: CGFloat = 1
    ) {
        self.density = density
        columns = Self.columns(width: width, density: density, usesLargeText: usesLargeText)
        columnSpacing = density == .large ? 6 : 5
        rowSpacing = density == .large ? 12 : 8
        let gaps = CGFloat(columns - 1) * columnSpacing
        cellWidth = max((width - Self.margin * 2 - gaps) / CGFloat(columns), 1)
        let scale = displayScale > 0 ? displayScale : 1
        coverHeight = (cellWidth / Self.coverAspect * scale).rounded() / scale
        self.captionHeight = max(captionHeight, 0)
    }

    /// The width a cell of `density` aims for.
    public static func targetWidth(for density: WallDensity) -> CGFloat {
        switch density {
        case .large: 200
        case .medium: 136
        case .small: 82
        }
    }

    /// The columns of `density` in a container `width` wide: the width divided by the density's
    /// target width, rounded to the nearest whole number, at least two. That is 2, 3 and 5 on
    /// every phone. Where rounding would give two densities the same count (a container under
    /// 340 pt), the denser one gets a column more, so the three stay three.
    ///
    /// At an accessibility text size Medium has Large's columns and Small has Medium's, so the
    /// captions keep a legible width: 2, 2 and 3 on a phone.
    public static func columns(width: CGFloat, density: WallDensity, usesLargeText: Bool = false) -> Int {
        func count(_ density: WallDensity) -> Int {
            max(Int((max(width, 0) / targetWidth(for: density)).rounded()), 2)
        }
        let large = count(.large)
        if usesLargeText {
            return density == .small ? max(count(.medium), large) : large
        }
        let medium = max(count(.medium), large + 1)
        switch density {
        case .large: return large
        case .medium: return medium
        case .small: return max(count(.small), medium + 1)
        }
    }
}

/// Where the rows of a wall are, down its scrolling content: the cells start at `top` and run
/// in sections (one, or one per page of a numbered list), each later section under a divider of
/// a given height.
nonisolated public struct WallGridMap: Sendable, Equatable {
    public let layout: WallGridLayout
    /// The top edge of the first row, in the content's coordinates.
    public let top: CGFloat
    public let dividerHeight: CGFloat
    /// The index of each section's first entry.
    private let starts: [Int]
    /// The top edge of each section's first row.
    private let tops: [CGFloat]
    private let count: Int

    /// - Parameters:
    ///   - sections: how many entries each section holds, in order.
    ///   - top: where the first row starts.
    ///   - dividerHeight: the height of what stands between two sections.
    public init(layout: WallGridLayout, sections: [Int], top: CGFloat, dividerHeight: CGFloat = 0) {
        self.layout = layout
        self.top = top
        self.dividerHeight = dividerHeight
        var starts: [Int] = []
        var tops: [CGFloat] = []
        var index = 0
        var y = top
        for (offset, section) in sections.enumerated() {
            let entries = max(section, 0)
            if offset > 0 { y += dividerHeight }
            starts.append(index)
            tops.append(y)
            index += entries
            y += CGFloat(Self.rows(entries, columns: layout.columns)) * layout.pitch
        }
        self.starts = starts
        self.tops = tops
        count = index
    }

    /// The top edge of the row that holds the entry at `index`.
    public func rowTop(ofEntry index: Int) -> CGFloat {
        guard count > 0, let section = section(ofEntry: index) else { return top }
        let local = min(max(index, 0), count - 1) - starts[section]
        return tops[section] + CGFloat(local / layout.columns) * layout.pitch
    }

    /// The first entry of the row whose top edge is nearest `y`, or `nil` when `y` is above
    /// the first row by more than half a row: what is above the cells is at the top then, and
    /// there is no row to keep in place.
    public func anchor(at y: CGFloat) -> Int? {
        guard count > 0, layout.pitch > 0, y > top - layout.pitch / 2 else { return nil }
        // The last section that starts at or above `y`, counting its divider as its own.
        var section = 0
        for (offset, sectionTop) in tops.enumerated() where offset > 0 && y >= sectionTop - dividerHeight {
            section = offset
        }
        let end = section + 1 < starts.count ? starts[section + 1] : count
        let entries = end - starts[section]
        guard entries > 0 else { return section > 0 ? starts[section] - 1 : nil }
        let rows = Self.rows(entries, columns: layout.columns)
        let row = min(max(Int(((y - tops[section]) / layout.pitch).rounded()), 0), rows - 1)
        return starts[section] + row * layout.columns
    }

    /// The scroll offset under `other`'s layout that shows the anchor row where it is at
    /// `offset` under this one, with the entry that was kept: the first entry of the row
    /// nearest the top edge, or `kept` when a change before this one already chose it.
    /// Without a row to keep, the offset stays.
    public func offset(
        keeping kept: Int? = nil, from offset: CGFloat, in other: WallGridMap
    ) -> (offset: CGFloat, anchor: Int?) {
        guard let anchor = kept ?? anchor(at: offset) else { return (offset, nil) }
        return (max(offset - rowTop(ofEntry: anchor) + other.rowTop(ofEntry: anchor), 0), anchor)
    }

    private func section(ofEntry index: Int) -> Int? {
        guard !starts.isEmpty else { return nil }
        let clamped = min(max(index, 0), count - 1)
        var found = 0
        for (offset, start) in starts.enumerated() where start <= clamped {
            found = offset
        }
        return found
    }

    private static func rows(_ entries: Int, columns: Int) -> Int {
        (entries + columns - 1) / max(columns, 1)
    }
}
