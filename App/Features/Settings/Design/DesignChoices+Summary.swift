import EhModels
import Foundation

// The words Experience uses for a set of choices (`settings.md`, "The page, top to bottom"
// and "The Experience screen"). The package decides which preset is nearest and which parts
// differ; these only put that into words.

extension DesignChoices {
    /// The state's name: the preset's, or "Custom".
    var localizedStateName: String {
        preset?.localizedName ?? L10n.Localizable.Settings.Design.custom
    }

    /// One line on the current state: "Shelf on every page" for a preset; for a mix, what
    /// differs from the nearest preset ("Lists from Ledger and reader from Wall"), or
    /// "5 pages changed from Shelf" when more than two differ.
    var localizedSummary: String {
        typealias Design = L10n.Localizable.Settings.Design
        if let preset {
            return Design.everyPage(preset.localizedName)
        }
        let nearest = nearestPreset
        let parts = differences(from: nearest)
        guard parts.count <= 2 else {
            return Design.changed(parts.count, nearest.localizedName)
        }
        let items = parts.enumerated().map { index, part in
            let name = index == 0 ? part.localizedName : part.localizedName.lowercasingFirstLetter
            return Design.from(name, self[part].sourceDesign.localizedName)
        }
        return ListFormatter.localizedString(byJoining: items)
    }

    /// Whether `part`'s choice differs from the nearest preset's, which the Experience screen
    /// marks in the tint.
    func differsFromNearestPreset(_ part: DesignPart) -> Bool {
        self[part] != DesignChoices(preset: nearestPreset)[part]
    }
}

extension DesignOption {
    /// The design an option comes from: a design is its own; the tab bar is Shelf's and the
    /// bar with the list menu is Wall's (`README.md` section 1). "Bottom bar from Wall".
    var sourceDesign: DesignStyle {
        switch self {
        case .bar(.tabs): .shelf
        case .bar(.command): .wall
        case .style(let style): style
        }
    }
}

private extension String {
    /// "Reader" → "reader", for a part named after the first in a sentence. Languages
    /// without case are unchanged.
    var lowercasingFirstLetter: String {
        guard let first else { return self }
        return String(first).lowercased(with: .current) + dropFirst()
    }
}
