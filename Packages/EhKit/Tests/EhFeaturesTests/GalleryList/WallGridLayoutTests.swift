import CoreGraphics
import EhModels
import Testing
@testable import EhFeatures

@Suite struct WallGridLayoutTests {
    private func columns(_ width: CGFloat, usesLargeText: Bool = false) -> [Int] {
        [WallDensity.large, .medium, .small].map {
            WallGridLayout.columns(width: width, density: $0, usesLargeText: usesLargeText)
        }
    }

    // MARK: Columns

    @Test(arguments: [375, 390, 393, 402, 414, 428, 430, 440] as [CGFloat])
    func everyPhoneHasTwoThreeAndFiveColumns(width: CGFloat) {
        #expect(columns(width) == [2, 3, 5])
    }

    /// Cut off instead of rounded, a 393 or 402 pt phone would get two columns at Medium.
    @Test func theCountIsRoundedNotCutOff() {
        #expect(WallGridLayout.columns(width: 402, density: .medium) == 3)
        #expect(WallGridLayout.columns(width: 393, density: .small) == 5)
        // 2.5 rounds up.
        #expect(WallGridLayout.columns(width: 340, density: .medium) == 3)
    }

    @Test func aNarrowContainerKeepsThreeDifferentWalls() {
        // Slide Over on an iPad: 320 / 136 rounds to 2, as Large does.
        #expect(columns(320) == [2, 3, 4])
        #expect(columns(280) == [2, 3, 4])
        #expect(columns(0) == [2, 3, 4])
    }

    /// The widths an iPad gives a list: full screen in both orientations, beside Wall's
    /// 372 pt gallery pane, beside Ledger's 280 pt Index, and in Split View.
    @Test(arguments: [
        (744, [4, 5, 9]), (768, [4, 6, 9]), (820, [4, 6, 10]), (834, [4, 6, 10]),
        (1_024, [5, 8, 12]), (1_032, [5, 8, 13]), (1_133, [6, 8, 14]), (1_180, [6, 9, 14]),
        (1_194, [6, 9, 15]), (1_366, [7, 10, 17]), (1_376, [7, 10, 17]),
        // 1,024 and 1,180 beside the gallery pane; 1,180 beside the Index.
        (652, [3, 5, 8]), (808, [4, 6, 10]), (900, [5, 7, 11]),
        // Half and a third of an 11-inch screen in Split View.
        (590, [3, 4, 7]), (507, [3, 4, 6]),
    ] as [(CGFloat, [Int])])
    func iPadWidths(width: CGFloat, expected: [Int]) {
        #expect(columns(width) == expected)
    }

    @Test func columnsNeverDecreaseAsTheContainerWidens() {
        for density in WallDensity.allCases {
            var last = 0
            for width in stride(from: 200, through: 1_400, by: 1) {
                let count = WallGridLayout.columns(width: CGFloat(width), density: density)
                #expect(count >= last)
                last = count
            }
        }
    }

    @Test func accessibilitySizesGiveCaptionsWiderCells() {
        // `wall.md`: Medium becomes two columns and Small three.
        for width in [375, 393, 402, 430, 440] as [CGFloat] {
            #expect(columns(width, usesLargeText: true) == [2, 2, 3])
        }
        #expect(columns(320, usesLargeText: true) == [2, 2, 2])
        #expect(columns(1_024, usesLargeText: true) == [5, 5, 8])
    }

    // MARK: Cells

    @Test func aMediumCellOnA430PointPhoneIs136Wide() {
        let layout = WallGridLayout(width: 430, density: .medium, captionHeight: 34, displayScale: 3)
        #expect(layout.columns == 3)
        #expect(layout.columnSpacing == 5)
        #expect(layout.rowSpacing == 8)
        #expect(layout.cellWidth == 136)
        // 136 × 10 / 7 = 194.2857… → 582.86 px → 583 px.
        #expect(layout.coverHeight == 583.0 / 3)
        #expect(layout.pitch == 583.0 / 3 + 34 + 8)
    }

    @Test func largeHasWiderGapsAndSmallNoCaption() {
        let large = WallGridLayout(width: 430, density: .large, captionHeight: 78, displayScale: 3)
        #expect(large.columnSpacing == 6)
        #expect(large.rowSpacing == 12)
        #expect(large.cellWidth == 206)
        let small = WallGridLayout(width: 430, density: .small, captionHeight: 0, displayScale: 3)
        #expect(small.cellWidth == (430.0 - 12 - 20) / 5)
        #expect(small.pitch == small.coverHeight + 8)
    }

    @Test func coverHeightsAreWholePixels() {
        for width in [320, 393, 402, 652, 1_024] as [CGFloat] {
            for density in WallDensity.allCases {
                for scale in [1, 2, 3] as [CGFloat] {
                    let layout = WallGridLayout(width: width, density: density, captionHeight: 0, displayScale: scale)
                    let pixels = layout.coverHeight * scale
                    #expect(abs(pixels - pixels.rounded()) < 0.000_1)
                    // Within a pixel of 7:10.
                    #expect(abs(layout.coverHeight - layout.cellWidth * 10 / 7) <= 1 / scale)
                }
            }
        }
    }

    @Test func cellsFillTheWidthBetweenTheMargins() {
        for width in [320, 393, 430, 652, 1_024, 1_366] as [CGFloat] {
            for density in WallDensity.allCases {
                let layout = WallGridLayout(width: width, density: density, captionHeight: 0)
                let used = layout.cellWidth * CGFloat(layout.columns)
                    + layout.columnSpacing * CGFloat(layout.columns - 1) + WallGridLayout.margin * 2
                #expect(abs(used - width) < 0.000_1)
            }
        }
    }

    @Test func aContainerWithoutWidthHasPositiveCells() {
        let layout = WallGridLayout(width: 0, density: .small, captionHeight: -4, displayScale: 0)
        #expect(layout.cellWidth == 1)
        #expect(layout.captionHeight == 0)
        #expect(layout.pitch > 0)
    }
}

@Suite struct WallGridMapTests {
    /// Medium: three columns, rows 200 apart, the cells starting 40 down.
    private func map(sections: [Int] = [20], top: CGFloat = 40, divider: CGFloat = 0) -> WallGridMap {
        WallGridMap(layout: layout(.medium), sections: sections, top: top, dividerHeight: divider)
    }

    /// Layouts 300 pt wide whose pitch is a round number: Large 2 columns and 300, Medium 3
    /// and 200, Small 4 and 150.
    private func layout(_ density: WallDensity) -> WallGridLayout {
        let base = WallGridLayout(width: 300, density: density, captionHeight: 0)
        let pitch: CGFloat = switch density {
        case .large: 300
        case .medium: 200
        case .small: 150
        }
        return WallGridLayout(width: 300, density: density, captionHeight: pitch - base.pitch)
    }

    @Test func theTestLayoutsHaveRoundPitches() {
        #expect(layout(.large).pitch == 300)
        #expect(layout(.large).columns == 2)
        #expect(layout(.medium).pitch == 200)
        #expect(layout(.medium).columns == 3)
        #expect(layout(.small).pitch == 150)
        #expect(layout(.small).columns == 4)
    }

    @Test func rowsFollowTheTop() {
        let map = map()
        #expect(map.rowTop(ofEntry: 0) == 40)
        #expect(map.rowTop(ofEntry: 2) == 40)
        #expect(map.rowTop(ofEntry: 3) == 240)
        #expect(map.rowTop(ofEntry: 19) == 1_240)
        // Out of range: the nearest entry's row.
        #expect(map.rowTop(ofEntry: -5) == 40)
        #expect(map.rowTop(ofEntry: 99) == 1_240)
    }

    @Test func theAnchorIsTheFirstEntryOfTheNearestRow() {
        let map = map()
        #expect(map.anchor(at: 40) == 0)
        #expect(map.anchor(at: 139) == 0)
        #expect(map.anchor(at: 141) == 3)
        #expect(map.anchor(at: 650) == 9)
        // Past the end: the last row.
        #expect(map.anchor(at: 5_000) == 18)
    }

    @Test func nothingIsAnchoredWhileWhatIsAboveTheCellsIsAtTheTop() {
        let map = map(top: 500)
        #expect(map.anchor(at: 0) == nil)
        #expect(map.anchor(at: 399) == nil)
        // Less than half a row of it left: the first row counts as at the top.
        #expect(map.anchor(at: 401) == 0)
        #expect(WallGridMap(layout: layout(.medium), sections: [], top: 0).anchor(at: 100) == nil)
        #expect(WallGridMap(layout: layout(.medium), sections: [0], top: 0).anchor(at: 100) == nil)
    }

    @Test func aDensityChangeKeepsTheAnchorRowWhereItIs() {
        let medium = map(sections: [500])
        let small = WallGridMap(layout: layout(.small), sections: [500], top: 40)
        // The row of entry 30 starts at 2,040: 10 pt below the top edge.
        let change = medium.offset(from: 2_030, in: small)
        #expect(change.anchor == 30)
        // Entry 30 is in Small's eighth row, at 1,090: the same 10 pt below the top edge.
        #expect(change.offset == 1_080)
        #expect(small.rowTop(ofEntry: 30) - change.offset == medium.rowTop(ofEntry: 30) - 2_030)
    }

    @Test func aKeptAnchorDoesNotDriftOverSeveralChanges() {
        let maps = [WallDensity.medium, .small, .medium, .large, .medium].map {
            WallGridMap(layout: layout($0), sections: [500], top: 40)
        }
        var offset: CGFloat = 4_440
        var kept: Int?
        for (old, new) in zip(maps, maps.dropFirst()) {
            let change = old.offset(keeping: kept, from: offset, in: new)
            offset = change.offset
            kept = change.anchor
        }
        #expect(kept == 66)
        #expect(offset == 4_440)
        // Taking the top row's first entry again at each step lets the place slip back
        // (`spikes/S1.md`): 66, 64, 63, 62.
        var drifting: CGFloat = 4_440
        var last: Int?
        for (old, new) in zip(maps, maps.dropFirst()) {
            let change = old.offset(from: drifting, in: new)
            drifting = change.offset
            last = change.anchor
        }
        #expect(last == 62)
        #expect(drifting == 4_040)
    }

    @Test func withoutARowToKeepTheOffsetStays() {
        let medium = map(sections: [500], top: 600)
        let small = WallGridMap(layout: layout(.small), sections: [500], top: 600)
        let change = medium.offset(from: 120, in: small)
        #expect(change.anchor == nil)
        #expect(change.offset == 120)
    }

    @Test func theOffsetNeverGoesAboveTheTop() {
        let small = WallGridMap(layout: layout(.small), sections: [500], top: 0)
        let large = WallGridMap(layout: layout(.large), sections: [500], top: 0)
        // Entry 4 is in Small's second row and Large's third, kept 30 pt above the top edge.
        let change = small.offset(from: 180, in: large)
        #expect(change.anchor == 4)
        #expect(change.offset == 630)
        // The other way a row can ask for an offset above the content's top.
        #expect(large.offset(keeping: 2, from: 150, in: small).offset == 0)
        #expect(large.offset(keeping: 0, from: 150, in: small).offset == 150)
    }

    // MARK: Pages of a numbered list

    @Test func laterSectionsStartUnderTheirDivider() {
        // 7 entries are three rows of three; the next page starts under a 30 pt divider.
        let map = map(sections: [7, 7, 2], divider: 30)
        #expect(map.rowTop(ofEntry: 6) == 440)
        #expect(map.rowTop(ofEntry: 7) == 670)
        #expect(map.rowTop(ofEntry: 13) == 1_070)
        #expect(map.rowTop(ofEntry: 14) == 1_300)
        #expect(map.rowTop(ofEntry: 15) == 1_300)
    }

    @Test func anchorsAcrossSections() {
        let map = map(sections: [7, 7, 2], divider: 30)
        #expect(map.anchor(at: 450) == 6)
        // Past the first page's last row: that row still.
        #expect(map.anchor(at: 630) == 6)
        // In the divider above the second page: its first row.
        #expect(map.anchor(at: 645) == 7)
        #expect(map.anchor(at: 1_080) == 13)
        #expect(map.anchor(at: 1_305) == 14)
    }

    @Test func aDensityChangeInANumberedListKeepsTheRow() {
        let sections = [50, 50, 50]
        let medium = WallGridMap(layout: layout(.medium), sections: sections, top: 40, dividerHeight: 30)
        let large = WallGridMap(layout: layout(.large), sections: sections, top: 40, dividerHeight: 30)
        // Entry 62 is on the second page: in Medium's fifth row there, in Large's seventh.
        // 40, a page of 17 rows, the divider, four rows; and with 25 rows a page, six rows.
        #expect(medium.rowTop(ofEntry: 62) == 4_270)
        #expect(large.rowTop(ofEntry: 62) == 9_370)
        let change = medium.offset(from: medium.rowTop(ofEntry: 62) - 12, in: large)
        #expect(change.anchor == 62)
        #expect(large.rowTop(ofEntry: 62) - change.offset == 12)
    }

    @Test func anEmptySectionTakesNoRows() {
        let map = map(sections: [3, 0, 3], top: 0, divider: 30)
        #expect(map.rowTop(ofEntry: 3) == 260)
        #expect(map.anchor(at: 250) == 3)
    }
}
