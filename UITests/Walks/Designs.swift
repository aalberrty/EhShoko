/// The design choices a walk runs under, mirrored from the app's `DesignChoices`
/// (`EhModels/Settings/Design.swift`; the test target does not link the package). Each walk
/// passes them as the part harness's launch arguments (`-HarnessBar`, `-HarnessStart`, …,
/// `PartHarnessOptions`), or under the `live` fixture as the settings' own
/// (`-settings.designBar command` and so on, read by `SettingsStore` at launch).
enum Style: String, CaseIterable, Sendable {
    case shelf, wall, ledger

    var name: String { rawValue.capitalized }
}

enum Bar: String, CaseIterable, Sendable {
    case tabs, command
}

enum Part: String, CaseIterable, Sendable {
    case bar, start, list, gallery, reader, search, library, look

    /// The row of Experience's "Pages" that opens this part's options screen.
    var settingsTitle: String {
        switch self {
        case .bar: "Bottom bar"
        case .start: "First screen"
        case .list: "Lists"
        case .gallery: "Gallery page"
        case .reader: "Reader"
        case .search: "Search"
        case .library: "Library"
        case .look: "Colors and type"
        }
    }

    /// The part harness's argument for this part.
    var harnessArgument: String { "-Harness" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The setting's key (`SettingKey`), for the `live` fixture.
    var settingArgument: String { "-settings.design" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

enum WallDensity: String, Sendable {
    case large, medium, small
}

struct Choices: Equatable, Sendable {
    var bar: Bar
    var start, list, gallery, reader, search, library, look: Style
    /// Wall's density; the app's default (medium) when `nil`.
    var density: WallDensity?
    /// Lists show their tag line (`showsTagsInList`).
    var showsTags = false
    /// Ledger's rows without covers (`ledgerShowsCovers` off).
    var hidesLedgerCovers = false

    /// A preset, as `DesignChoices(preset:)` sets it (`README.md` section 2).
    init(preset: Style) {
        bar = preset == .shelf ? .tabs : .command
        start = preset
        list = preset
        gallery = preset
        reader = preset
        search = preset
        library = preset
        look = preset
    }

    /// The preset this matches, or `nil` for a mix.
    var preset: Style? {
        Style.allCases.first { var plain = self; plain.density = nil; plain.showsTags = false; plain.hidesLedgerCovers = false; return plain == Choices(preset: $0) }
    }

    subscript(part: Part) -> String {
        get {
            switch part {
            case .bar: bar.rawValue
            case .start: start.rawValue
            case .list: list.rawValue
            case .gallery: gallery.rawValue
            case .reader: reader.rawValue
            case .search: search.rawValue
            case .library: library.rawValue
            case .look: look.rawValue
            }
        }
        set {
            if part == .bar {
                bar = Bar(rawValue: newValue) ?? bar
                return
            }
            guard let style = Style(rawValue: newValue) else { return }
            switch part {
            case .bar: break
            case .start: start = style
            case .list: list = style
            case .gallery: gallery = style
            case .reader: reader = style
            case .search: search = style
            case .library: library = style
            case .look: look = style
            }
        }
    }

    /// The values a part can take.
    static func values(of part: Part) -> [String] {
        part == .bar ? Bar.allCases.map(\.rawValue) : Style.allCases.map(\.rawValue)
    }

    /// The launch arguments that put the app in these choices.
    func arguments(for fixture: WalkEnvironment.Fixture) -> [String] {
        var arguments: [String] = []
        switch fixture {
        case .offline, .signedIn:
            for part in Part.allCases { arguments += [part.harnessArgument, self[part]] }
            if let density { arguments += ["-HarnessDensity", density.rawValue] }
            if showsTags { arguments += ["-HarnessTags", "YES"] }
        case .live:
            for part in Part.allCases { arguments += [part.settingArgument, self[part]] }
            if let density { arguments += ["-settings.wallDensity", density.rawValue] }
            arguments += ["-settings.showsTagsInList", showsTags ? "<true/>" : "<false/>"]
            // The offer would cover the first screen of every walk.
            arguments += ["-settings.experienceOfferShown", "<true/>"]
        }
        if hidesLedgerCovers { arguments += ["-settings.ledgerShowsCovers", "<false/>"] }
        return arguments
    }

    /// "tabs · Shelf start · Wall lists …" for the results table.
    var summary: String {
        var words = [bar.rawValue]
        for part in Part.allCases where part != .bar {
            words.append("\(part.rawValue) \(self[part])")
        }
        if let density { words.append("density \(density.rawValue)") }
        if showsTags { words.append("tags on") }
        if hidesLedgerCovers { words.append("no covers") }
        return words.joined(separator: " · ")
    }
}
