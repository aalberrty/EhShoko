import EhModels
import Foundation
import Testing

@Suite struct DesignChoicesTests {
    @Test func presetsFollowTheTable() {
        let shelf = DesignChoices(preset: .shelf)
        #expect(shelf.bar == .tabs)
        #expect(DesignChoices(preset: .wall).bar == .command)
        #expect(DesignChoices(preset: .ledger).bar == .command)
        for style in DesignStyle.allCases {
            let choices = DesignChoices(preset: style)
            for part in DesignPart.allCases where part != .bar {
                #expect(choices[part] == .style(style))
            }
        }
    }

    @Test(arguments: DesignStyle.allCases)
    func aPresetIsRecognised(style: DesignStyle) {
        let choices = DesignChoices(preset: style)
        #expect(choices.preset == style)
        #expect(choices.nearestPreset == style)
        #expect(choices.differences(from: style).isEmpty)
    }

    @Test func oneChangedPartIsCustom() {
        var choices = DesignChoices(preset: .wall)
        choices.reader = .ledger
        #expect(choices.preset == nil)
        #expect(choices.differences(from: .wall) == [.reader])
    }

    @Test func theBarAloneMakesAMix() {
        var choices = DesignChoices(preset: .shelf)
        choices.bar = .command
        #expect(choices.preset == nil)
        #expect(choices.nearestPreset == .shelf)
        #expect(choices.differences(from: .shelf) == [.bar])
    }

    @Test(arguments: DesignPart.allCases)
    func everyPartAndOptionRoundTripsThroughTheSubscript(part: DesignPart) {
        for option in part.options {
            var choices = DesignChoices(preset: .shelf)
            choices[part] = option
            #expect(choices[part] == option)
            let others = DesignPart.allCases.filter { $0 != part }
            for other in others {
                #expect(choices[other] == DesignChoices(preset: .shelf)[other])
            }
        }
    }

    @Test func optionCounts() {
        #expect(DesignPart.bar.options == [.bar(.tabs), .bar(.command)])
        for part in DesignPart.allCases where part != .bar {
            #expect(part.options == [.style(.shelf), .style(.wall), .style(.ledger)])
        }
    }

    @Test func anOptionOfTheWrongKindChangesNothing() {
        var choices = DesignChoices(preset: .ledger)
        choices[.bar] = .style(.shelf)
        choices[.list] = .bar(.tabs)
        #expect(choices == DesignChoices(preset: .ledger))
    }

    @Test func nearestPresetCountsParts() {
        // The command bar, Wall in five parts, Ledger in two: Wall has six in common, Ledger three.
        let choices = DesignChoices(
            bar: .command, start: .wall, list: .wall, gallery: .wall,
            reader: .wall, search: .wall, library: .ledger, look: .ledger
        )
        #expect(choices.nearestPreset == .wall)
        #expect(choices.differences(from: .wall) == [.library, .look])
        #expect(choices.differences(from: .ledger) == [.start, .list, .gallery, .reader, .search])
    }

    @Test func singleSwapsStayNearTheirPreset() {
        for style in DesignStyle.allCases {
            for part in DesignPart.allCases {
                for option in part.options {
                    var choices = DesignChoices(preset: style)
                    choices[part] = option
                    #expect(choices.nearestPreset == style)
                }
            }
        }
    }

    @Test func tiesGoToShelfThenWall() {
        // Shelf and Wall: four parts in common each.
        let shelfWall = DesignChoices(
            bar: .tabs, start: .shelf, list: .shelf, gallery: .shelf,
            reader: .wall, search: .wall, library: .wall, look: .wall
        )
        #expect(shelfWall.differences(from: .shelf).count == shelfWall.differences(from: .wall).count)
        #expect(shelfWall.nearestPreset == .shelf)

        // Wall and Ledger: four parts in common each (the command bar counts for both).
        let wallLedger = DesignChoices(
            bar: .command, start: .wall, list: .wall, gallery: .wall,
            reader: .ledger, search: .ledger, library: .ledger, look: .shelf
        )
        #expect(wallLedger.differences(from: .wall).count == wallLedger.differences(from: .ledger).count)
        #expect(wallLedger.nearestPreset == .wall)

        // Shelf and Ledger: three parts in common each, Wall two.
        let shelfLedger = DesignChoices(
            bar: .tabs, start: .shelf, list: .shelf, gallery: .ledger,
            reader: .ledger, search: .ledger, library: .wall, look: .wall
        )
        #expect(shelfLedger.differences(from: .shelf).count == 5)
        #expect(shelfLedger.differences(from: .ledger).count == 5)
        #expect(shelfLedger.differences(from: .wall).count == 6)
        #expect(shelfLedger.nearestPreset == .shelf)
    }

    @Test func differencesAreInPartOrder() {
        let choices = DesignChoices(
            bar: .command, start: .shelf, list: .ledger, gallery: .shelf,
            reader: .wall, search: .shelf, library: .shelf, look: .ledger
        )
        #expect(choices.differences(from: .shelf) == [.bar, .list, .reader, .look])
    }

    @Test func choosableListsEveryPartInOrder() {
        #expect(DesignPart.choosable == DesignPart.allCases)
    }

    @Test func codableRoundTrip() throws {
        let choices = DesignChoices(
            bar: .command, start: .shelf, list: .ledger, gallery: .wall,
            reader: .wall, search: .shelf, library: .ledger, look: .ledger
        )
        let decoded = try JSONDecoder().decode(DesignChoices.self, from: JSONEncoder().encode(choices))
        #expect(decoded == choices)
    }
}
