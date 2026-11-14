import EhModels

// The names a preview is read by. The option card and the Experience rows (F9) can use the
// same names for their own text.

extension DesignPreview.Subject {
    /// What the picture shows: the page, the choice and its description for an option; the
    /// page and the preset's name (or "Custom") for a set of choices.
    var accessibilityLabel: String {
        switch self {
        case .option(let part, let option):
            [part.localizedName, option.localizedName, part.localizedDescription(of: option)]
                .compactMap(\.self).joined(separator: ", ")
        case .firstScreen(let choices): Self.label(L10n.Localizable.Settings.Design.Part.start, choices)
        case .gallery(let choices): Self.label(L10n.Localizable.Settings.Design.Part.gallery, choices)
        case .reader(let choices): Self.label(L10n.Localizable.Settings.Design.Part.reader, choices)
        }
    }

    private static func label(_ part: String, _ choices: DesignChoices) -> String {
        let name = choices.preset?.localizedName ?? L10n.Localizable.Settings.Design.custom
        return "\(part), \(name)"
    }
}

extension DesignPart {
    /// The page's name: "Bottom bar", "Lists", "Colours and type".
    var localizedName: String {
        typealias Part = L10n.Localizable.Settings.Design.Part
        return switch self {
        case .bar: Part.bar
        case .start: Part.start
        case .list: Part.list
        case .gallery: Part.gallery
        case .reader: Part.reader
        case .search: Part.search
        case .library: Part.library
        case .look: Part.look
        }
    }

    /// The one-line description of `option` on this page (`settings.md`'s table), or `nil`
    /// for an option the page cannot take.
    func localizedDescription(of option: DesignOption) -> String? {
        typealias Desc = L10n.Localizable.Settings.Design.Desc
        switch (self, option) {
        case (.bar, .bar(.tabs)): return Desc.Bar.tabs
        case (.bar, .bar(.command)): return Desc.Bar.command
        case (.bar, .style), (_, .bar): return nil
        case (_, .style(let style)):
            let descriptions: (shelf: String, wall: String, ledger: String) = switch self {
            case .start: (Desc.Start.shelf, Desc.Start.wall, Desc.Start.ledger)
            case .list: (Desc.List.shelf, Desc.List.wall, Desc.List.ledger)
            case .gallery: (Desc.Gallery.shelf, Desc.Gallery.wall, Desc.Gallery.ledger)
            case .reader: (Desc.Reader.shelf, Desc.Reader.wall, Desc.Reader.ledger)
            case .search: (Desc.Search.shelf, Desc.Search.wall, Desc.Search.ledger)
            case .library: (Desc.Library.shelf, Desc.Library.wall, Desc.Library.ledger)
            case .look, .bar: (Desc.Look.shelf, Desc.Look.wall, Desc.Look.ledger)
            }
            return switch style {
            case .shelf: descriptions.shelf
            case .wall: descriptions.wall
            case .ledger: descriptions.ledger
            }
        }
    }
}

extension DesignOption {
    /// The option's name: Tabs, Menu & search, or a design's name, which is not translated.
    var localizedName: String {
        switch self {
        case .bar(.tabs): L10n.Localizable.Settings.Design.Bar.tabs
        case .bar(.command): L10n.Localizable.Settings.Design.Bar.command
        case .style(let style): style.localizedName
        }
    }
}

extension DesignStyle {
    /// Shelf, Wall and Ledger stay as they are in every language (`strings.md`).
    var localizedName: String {
        switch self {
        case .shelf: "Shelf"
        case .wall: "Wall"
        case .ledger: "Ledger"
        }
    }
}
