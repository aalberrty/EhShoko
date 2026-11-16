#if DEBUG || HARNESS
import EhFeatures
import EhModels
import Foundation

/// How the part harness is set up: the part under test, the design of every part, and the
/// surroundings the contract distinguishes (`Design/designs/README.md` section 11.3). From
/// Laboratory every field starts at its default and is changed on the harness's panel; a
/// launch with `-Harness part` reads them from the launch arguments, so a walk can be
/// scripted:
///
/// | Argument | Default | Values |
/// |---|---|---|
/// | `-HarnessPart` | `shell` | `shell` (the whole shell, to switch designs under), `list`, `gallery`, `start`, `search`, `library` |
/// | `-HarnessPreset` | `shelf` | `shelf`, `wall`, `ledger`: every part's design at once |
/// | `-HarnessBar` | the preset's | `tabs`, `command` |
/// | `-HarnessStart`, `-HarnessList`, `-HarnessGallery`, `-HarnessReader`, `-HarnessSearch`, `-HarnessLibrary`, `-HarnessLook` | the preset's | `shelf`, `wall`, `ledger`: one part's design |
/// | `-HarnessWidth` | 0 | the container's width in points; 0 is the window's (320, 430, 1000) |
/// | `-HarnessHeader` | `none` | `none`: a list of its own, with no header (its states take the screen); `empty`: an empty header, as a first screen with nothing above the rows passes; `YES` or `tall`: a tall header |
/// | `-HarnessTags YES` | NO | lists show their tag line (`showsTagsInList`) |
/// | `-HarnessDensity` | `medium` | `large`, `medium`, `small`: Wall's density |
/// | `-HarnessKind` | `frontpage` | `frontpage`, `popular`, `watched`, `toplists`, `history`, `folder`, `search`, `scoped` |
/// | `-HarnessState` | `content` | `content`, `loading`, `empty`, `failed`, `signedOut`, `stale`, `nextLoading`, `nextFailed`, `end` |
/// | `-HarnessPresentation` | `pushed` | `pushed`, `pane`, `sheet`: how the gallery opens |
/// | `-HarnessScope` | `everywhere` | `everywhere`, `favorites`, `watched`: the search surface's scope |
/// | `-HarnessScheme` | the system's | `light`, `dark` |
/// | `-HarnessTextSize max` | the system's | the largest Dynamic Type size |
/// | `-HarnessPanel NO` | YES | hides the panel's button, for screenshots |
/// | `-HarnessMemoryCheck` | none | `shelf`, `wall`, `ledger`: the scripted memory check. 25 s after launch (time to visit screens) the live per-design objects are written to `Documents/part-harness-heap-1.txt`, the designs switch to this preset, and 10 s later they are written to `part-harness-heap-2.txt` (`PartHarnessHeap`) |
nonisolated struct PartHarnessOptions: Equatable, Sendable {
    var part = PartHarnessPart.shell
    /// The design of every part. The part under test takes its own; the others are its
    /// surroundings.
    var choices = DesignChoices(preset: .shelf)
    var width = 0
    var header = PartHarnessHeaderMode.absent
    var showsTags = false
    var density = WallDensity.medium
    var kind = PartHarnessListKind.frontpage
    var state = PartHarnessListState.content
    var presentation = PartHarnessPresentation.pushed
    var scope = SearchScope.everywhere
    var scheme = PartHarnessScheme.system
    var usesLargestText = false
    var showsPanelButton = true
    /// The preset the scripted memory check switches to; `nil` for no check.
    var memoryCheckPreset: DesignStyle?

    static let `default` = PartHarnessOptions()

    static var atLaunch: PartHarnessOptions {
        let defaults = UserDefaults.standard
        var options = PartHarnessOptions()
        func value<Value: RawRepresentable>(_ key: String) -> Value? where Value.RawValue == String {
            defaults.string(forKey: key).flatMap(Value.init(rawValue:))
        }
        options.part = value("HarnessPart") ?? options.part
        if let preset: DesignStyle = value("HarnessPreset") {
            options.choices = DesignChoices(preset: preset)
        }
        options.choices.bar = value("HarnessBar") ?? options.choices.bar
        options.choices.start = value("HarnessStart") ?? options.choices.start
        options.choices.list = value("HarnessList") ?? options.choices.list
        options.choices.gallery = value("HarnessGallery") ?? options.choices.gallery
        options.choices.reader = value("HarnessReader") ?? options.choices.reader
        options.choices.search = value("HarnessSearch") ?? options.choices.search
        options.choices.library = value("HarnessLibrary") ?? options.choices.library
        options.choices.look = value("HarnessLook") ?? options.choices.look
        options.width = max(defaults.integer(forKey: "HarnessWidth"), 0)
        options.header = PartHarnessHeaderMode(argument: defaults.string(forKey: "HarnessHeader"))
        options.showsTags = defaults.bool(forKey: "HarnessTags")
        options.density = value("HarnessDensity") ?? options.density
        options.kind = value("HarnessKind") ?? options.kind
        options.state = value("HarnessState") ?? options.state
        options.presentation = value("HarnessPresentation") ?? options.presentation
        options.scope = value("HarnessScope") ?? options.scope
        options.scheme = value("HarnessScheme") ?? options.scheme
        options.usesLargestText = defaults.string(forKey: "HarnessTextSize") == "max"
        options.memoryCheckPreset = value("HarnessMemoryCheck")
        if defaults.object(forKey: "HarnessPanel") != nil {
            options.showsPanelButton = defaults.bool(forKey: "HarnessPanel")
        }
        return options
    }
}

nonisolated enum PartHarnessPart: String, CaseIterable, Identifiable, Sendable {
    case shell, list, gallery, start, search, library

    var id: String { rawValue }
}

/// What a list in the part harness has above its rows.
nonisolated enum PartHarnessHeaderMode: String, CaseIterable, Identifiable, Sendable {
    /// No header: a list of its own, whose states take the screen.
    case absent = "none"
    /// A header with nothing in it: the list keeps its states under it, as rows.
    case empty
    /// Two shelves' worth of blocks, so the rows start below the fold on a small phone.
    case tall

    var id: String { rawValue }

    init(argument: String?) {
        switch argument?.lowercased() {
        case "yes", "tall", "true", "1": self = .tall
        case "empty": self = .empty
        default: self = .absent
        }
    }
}

nonisolated enum PartHarnessListKind: String, CaseIterable, Identifiable, Sendable {
    case frontpage, popular, watched, toplists, history, folder, search, scoped

    var id: String { rawValue }
}

nonisolated enum PartHarnessListState: String, CaseIterable, Identifiable, Sendable {
    case content, loading, empty, failed, signedOut, stale, nextLoading, nextFailed, end

    var id: String { rawValue }
}

nonisolated enum PartHarnessPresentation: String, CaseIterable, Identifiable, Sendable {
    case pushed, pane, sheet

    var id: String { rawValue }
}

nonisolated enum PartHarnessScheme: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }
}
#endif
