/// Every walk, by set (`PLAN.md`, the walk under I5):
///
/// | Set | Walks |
/// |---|---|
/// | `presets` | The plan's walk under each preset: `preset-shelf`, `preset-wall`, `preset-ledger`. |
/// | `swaps` | From each preset, each other part set to each of its other values (15 per preset, 45): `swap-<preset>-<part>-<value>`, e.g. `swap-shelf-list-wall`. |
/// | `mixes` | The six heaviest mixes of the plan's table: `mix-1` … `mix-6`. |
/// | `device` | The steps done once per device, not per walk: `device-options`, `device-wizard-apply`, `device-wizard-close`, `device-storyboards`, `device-offer`, `device-closing`. |
/// | `all` | All of them. |
///
/// `WALKS` takes set names and walk ids, comma-separated: `presets,mix-3,device-offer`.
enum WalkCatalogue {
    static func selected(by environment: WalkEnvironment) -> [Walk] {
        var ids: [String] = []
        for word in environment.selection {
            let found = set(named: word) ?? [word]
            ids += found.filter { !ids.contains($0) }
        }
        return ids.compactMap { walk(id: $0, in: environment) }
    }

    /// The walk ids of a set, or `nil` when the word names no set.
    static func set(named name: String) -> [String]? {
        switch name {
        case "presets": Style.allCases.map { "preset-\($0.rawValue)" }
        case "swaps": swaps.map(\.id)
        case "mixes": mixes.indices.map { "mix-\($0 + 1)" }
        case "device": DeviceWalks.ids
        case "all": ["presets", "swaps", "mixes", "device"].flatMap { set(named: $0) ?? [] }
        default: nil
        }
    }

    static func walk(id: String, in environment: WalkEnvironment) -> Walk? {
        if id.hasPrefix("preset-"), let style = Style(rawValue: String(id.dropFirst("preset-".count))) {
            return PlanWalk(id: id, title: "\(style.name) preset", choices: Choices(preset: style), environment: environment).walk
        }
        if let swap = swaps.first(where: { $0.id == id }) {
            return PlanWalk(id: id, title: swap.title, choices: swap.choices, environment: environment).walk
        }
        if id.hasPrefix("mix-"), let number = Int(id.dropFirst("mix-".count)), mixes.indices.contains(number - 1) {
            let choices = mixes[number - 1]
            return PlanWalk(id: id, title: "Mix \(number)", choices: choices, environment: environment).walk
        }
        return DeviceWalks.walk(id: id, in: environment)
    }

    // MARK: Single swaps

    struct Swap: Sendable {
        var id: String
        var title: String
        var choices: Choices
    }

    /// From each preset, each of the seven other parts set to each of its other values: the
    /// bar has one other value, the six design parts and the look two each, 15 per preset.
    /// (The search part follows the list in the plan's mixes but is swapped on its own here.)
    static var swaps: [Swap] {
        var swaps: [Swap] = []
        for preset in Style.allCases {
            let base = Choices(preset: preset)
            for part in Part.allCases {
                for value in Choices.values(of: part) where value != base[part] {
                    var choices = base
                    choices[part] = value
                    swaps.append(Swap(
                        id: "swap-\(preset.rawValue)-\(part.rawValue)-\(value)",
                        title: "\(preset.name) with \(part.settingsTitle.lowercased()) \(value)",
                        choices: choices
                    ))
                }
            }
        }
        return swaps.filter { $0.choices.preset == nil }
    }

    // MARK: The six heaviest mixes

    /// The plan's table; search and library follow the list's design.
    static let mixes: [Choices] = [
        mix(.command, start: .shelf, list: .wall, gallery: .wall, reader: .ledger, look: .wall, density: .large),
        mix(.tabs, start: .wall, list: .wall, gallery: .shelf, reader: .wall, look: .shelf, density: .small),
        mix(.command, start: .ledger, list: .wall, gallery: .ledger, reader: .shelf, look: .ledger, density: .medium),
        mix(.tabs, start: .shelf, list: .ledger, gallery: .wall, reader: .wall, look: .ledger),
        mix(.command, start: .wall, list: .shelf, gallery: .ledger, reader: .shelf, look: .shelf, tags: true),
        mix(.tabs, start: .ledger, list: .shelf, gallery: .wall, reader: .ledger, look: .wall),
    ]

    private static func mix(
        _ bar: Bar, start: Style, list: Style, gallery: Style, reader: Style, look: Style,
        density: WallDensity? = nil, tags: Bool = false
    ) -> Choices {
        var choices = Choices(preset: .shelf)
        choices.bar = bar
        choices.start = start
        choices.list = list
        choices.gallery = gallery
        choices.reader = reader
        choices.search = list
        choices.library = list
        choices.look = look
        choices.density = density
        choices.showsTags = tags
        return choices
    }
}
