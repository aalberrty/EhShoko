import EhModels

extension StageBeat {
    /// The caption under the stage, naming what the beat shows.
    var caption: String {
        typealias Stage = L10n.Localizable.Settings.Design.Stage
        let captions = switch style {
        case .shelf: [Stage.Shelf._1, Stage.Shelf._2, Stage.Shelf._3, Stage.Shelf._4]
        case .wall: [Stage.Wall._1, Stage.Wall._2, Stage.Wall._3, Stage.Wall._4]
        case .ledger: [Stage.Ledger._1, Stage.Ledger._2, Stage.Ledger._3, Stage.Ledger._4]
        }
        return captions[min(max(beat, 0), captions.count - 1)]
    }
}

extension DesignStyle {
    /// What the preset's animation shows, in a sentence: the stage's value for VoiceOver.
    /// Shelf's names the tab bar tucking away only where the playback shows it
    /// (`StagePlayback.tabBarTucks`).
    func stageSummary(tabBarTucks: Bool) -> String {
        typealias Summary = L10n.Localizable.Settings.Design.Stage.A11y
        return switch self {
        case .shelf: tabBarTucks ? Summary.shelf : Summary.Shelf.still
        case .wall: Summary.wall
        case .ledger: Summary.ledger
        }
    }
}
