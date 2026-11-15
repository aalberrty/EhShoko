import EhFeatures
import EhModels
import Foundation

// The words the setup wizard uses for its draft (`settings.md`, "The setup wizard"). The model
// decides the state and which pages differ; these only put that into words.

extension DesignChoices {
    /// What follows "So far:" in a page's step: "Shelf", "Shelf with Ledger's colours",
    /// "Custom · 3 pages changed from Shelf", "Custom · 1 page changed from Shelf".
    var localizedSoFar: String {
        typealias Design = L10n.Localizable.Settings.Design
        switch DesignSetupModel.state(of: self) {
        case .preset(let style):
            return style.localizedName
        case .presetWithLook(let style, let look):
            return Design.Setup.withColours(style.localizedName, look.localizedName)
        case .custom(let changed, let nearest):
            return changed.count == 1
                ? Design.Setup.CustomChanged.one(nearest.localizedName)
                : Design.Setup.customChanged(changed.count, nearest.localizedName)
        }
    }
}

extension DesignChoices {
    /// The summary's sentence: "Shelf on every page" for a preset; for a mix, the pages that
    /// differ from the nearest preset: "2 pages differ from Shelf: lists from Ledger and
    /// reader from Wall."
    var localizedSetupSentence: String {
        typealias Design = L10n.Localizable.Settings.Design
        if let preset {
            return Design.everyPage(preset.localizedName)
        }
        let nearest = nearestPreset
        let parts = differences(from: nearest)
        let items = parts.map { part in
            Design.from(part.localizedName.lowercasedFirstLetter, self[part].sourceDesign.localizedName)
        }
        let list = ListFormatter.localizedString(byJoining: items)
        return parts.count == 1
            ? Design.Setup.Differ.one(nearest.localizedName, list)
            : Design.Setup.Differ.many(parts.count, nearest.localizedName, list)
    }
}

private extension String {
    /// "Reader" → "reader", for a page named inside a sentence. Languages without case are
    /// unchanged.
    var lowercasedFirstLetter: String {
        guard let first else { return self }
        return String(first).lowercased(with: .current) + dropFirst()
    }
}
