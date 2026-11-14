import Foundation

/// One of the three designs a part can take.
public enum DesignStyle: String, Codable, Sendable, Hashable, CaseIterable {
    case shelf, wall, ledger
}

/// The two bottom bars.
public enum BarStyle: String, Codable, Sendable, Hashable, CaseIterable {
    case tabs, command
}

/// A thing the user chooses a design for. The order is the order Settings and the wizard
/// show the parts in, and the order `DesignChoices.differences(from:)` reports them in.
public enum DesignPart: String, Sendable, Hashable, CaseIterable {
    case bar, start, list, gallery, reader, search, library, look

    /// The parts the Experience screens and the wizard offer, in order.
    ///
    /// If colours and type should follow the first screen instead of being chosen, `.look`
    /// leaves this list and `SettingsStore.look` returns `designStart`; nothing else changes.
    public static let choosable: [DesignPart] = allCases

    /// Every value this part can take: two for the bar, three for every other part.
    public var options: [DesignOption] {
        switch self {
        case .bar: BarStyle.allCases.map(DesignOption.bar)
        default: DesignStyle.allCases.map(DesignOption.style)
        }
    }
}

/// A value a part can take: the bar has two, every other part three.
public enum DesignOption: Sendable, Hashable {
    case bar(BarStyle)
    case style(DesignStyle)
}

/// One choice per part. Equatable, so "is this a preset" is a comparison.
public struct DesignChoices: Codable, Sendable, Hashable {
    public var bar: BarStyle
    public var start: DesignStyle
    public var list: DesignStyle
    public var gallery: DesignStyle
    public var reader: DesignStyle
    public var search: DesignStyle
    public var library: DesignStyle
    public var look: DesignStyle

    public init(
        bar: BarStyle, start: DesignStyle, list: DesignStyle, gallery: DesignStyle,
        reader: DesignStyle, search: DesignStyle, library: DesignStyle, look: DesignStyle
    ) {
        self.bar = bar
        self.start = start
        self.list = list
        self.gallery = gallery
        self.reader = reader
        self.search = search
        self.library = library
        self.look = look
    }

    /// The choices a preset sets: Shelf uses the tab bar, Wall and Ledger the command bar, and
    /// every other part takes the preset's own design.
    public init(preset: DesignStyle) {
        bar = preset == .shelf ? .tabs : .command
        start = preset
        list = preset
        gallery = preset
        reader = preset
        search = preset
        library = preset
        look = preset
    }

    /// The preset these choices match, or `nil` for a mix ("Custom").
    public var preset: DesignStyle? {
        DesignStyle.allCases.first { DesignChoices(preset: $0) == self }
    }

    /// The preset with the most parts in common; ties go to Shelf, then Wall.
    public var nearestPreset: DesignStyle {
        var nearest = DesignStyle.shelf
        var nearestDifferences = Int.max
        for style in DesignStyle.allCases {
            let count = differences(from: style).count
            if count < nearestDifferences {
                nearest = style
                nearestDifferences = count
            }
        }
        return nearest
    }

    /// The parts whose choice differs from `preset`, in `DesignPart` order.
    public func differences(from preset: DesignStyle) -> [DesignPart] {
        let reference = DesignChoices(preset: preset)
        return DesignPart.allCases.filter { self[$0] != reference[$0] }
    }

    /// The choice for one part.
    ///
    /// Setting an option of the wrong kind (a bar style for a non-bar part, or the reverse)
    /// changes nothing: no part can hold it.
    public subscript(part: DesignPart) -> DesignOption {
        get {
            switch part {
            case .bar: .bar(bar)
            case .start: .style(start)
            case .list: .style(list)
            case .gallery: .style(gallery)
            case .reader: .style(reader)
            case .search: .style(search)
            case .library: .style(library)
            case .look: .style(look)
            }
        }
        set {
            switch (part, newValue) {
            case (.bar, .bar(let value)): bar = value
            case (.start, .style(let value)): start = value
            case (.list, .style(let value)): list = value
            case (.gallery, .style(let value)): gallery = value
            case (.reader, .style(let value)): reader = value
            case (.search, .style(let value)): search = value
            case (.library, .style(let value)): library = value
            case (.look, .style(let value)): look = value
            default: break
            }
        }
    }
}

/// Wall lists' cover size: 2, 3 or 5 columns on a phone.
public enum WallDensity: String, Codable, Sendable, Hashable, CaseIterable {
    case large, medium, small
}
