import EhCore
import EhModels

/// One choice of one of the four kinds of page translation model, as the selection screens
/// list them.
nonisolated public enum PageTranslationChoice: Hashable, Sendable {
    case detector(TextDetectorChoice)
    case reader(TextReaderChoice)
    case translator(TranslatorChoice)
    case repaint(RepaintChoice)

    public var role: ModelRole {
        switch self {
        case .detector: .detector
        case .reader: .reader
        case .translator: .translator
        case .repaint: .repaint
        }
    }

    /// The model it needs, or `nil` for a choice that needs no download (repaint off).
    public var artifact: ModelArtifactID? {
        switch self {
        case .detector(let choice): choice.artifact
        case .reader(let choice): choice.artifact
        case .translator(let choice): choice.artifact
        case .repaint(let choice): choice.artifact
        }
    }

    /// What was measured for it, in the table's order.
    public var figures: [MeasuredFigure] {
        switch self {
        case .detector(let choice): PageTranslationMeasurements.figures(for: choice)
        case .reader(let choice): PageTranslationMeasurements.figures(for: choice)
        case .translator(let choice): PageTranslationMeasurements.figures(for: choice)
        case .repaint(let choice): PageTranslationMeasurements.figures(for: choice)
        }
    }

    /// Every choice of a kind, in the order the settings know them. Models come in the
    /// catalog's order, which is also the order a choice falls back in.
    public static func all(for role: ModelRole) -> [PageTranslationChoice] {
        switch role {
        case .detector: TextDetectorChoice.allCases.map(Self.detector)
        case .reader: TextReaderChoice.allCases.map(Self.reader)
        case .translator: TranslatorChoice.allCases.map(Self.translator)
        case .repaint: RepaintChoice.allCases.map(Self.repaint)
        }
    }

    /// The settings' default of a kind.
    public static func preferredDefault(for role: ModelRole) -> PageTranslationChoice {
        switch role {
        case .detector: .detector(.default)
        case .reader: .reader(.default)
        case .translator: .translator(.default)
        case .repaint: .repaint(.default)
        }
    }

    /// The choice that downloads `artifact`.
    public static func choice(downloading artifact: ModelArtifactID) -> PageTranslationChoice? {
        ModelRole.allCases.lazy.flatMap(all(for:)).first { $0.artifact == artifact }
    }
}

/// One card of a selection screen: a choice, where it stands on this device, and what was
/// measured for it. A value, so a card reads no store.
nonisolated public struct PageTranslationChoiceCard: Equatable, Sendable, Identifiable {
    /// Where a choice's model stands for this user.
    public enum Availability: Hashable, Sendable {
        /// Needs nothing downloaded (repaint off).
        case noDownload
        case installed
        /// Can be downloaded; `bytes` is what is left to fetch.
        case needs(bytes: Int64)
        case downloading(ModelTransferProgress)
        case paused(ModelTransferProgress)
        /// Downloaded and being checked, compiled or loaded once.
        case preparing
        /// Its download stopped; choosing it again tries again.
        case failed(ModelStoreFailure)
        /// None of this user's sources offers it ("Not in the public store"). It is listed
        /// with its figures and cannot be chosen.
        case notOffered
    }

    public var choice: PageTranslationChoice
    /// The choice pages are translated with now.
    public var isSelected: Bool
    /// The best choice of its kind that this user's sources offer.
    public var isDefault: Bool
    /// Chosen, and applied once its install finishes; until then the selected one is used.
    public var isPending: Bool
    public var availability: Availability
    /// Its licence does not let the project pass it on: only a private store can have it.
    /// Says why a choice that is `notOffered` is, where the reason is its licence.
    public var isPrivateOnly: Bool
    /// Its figures grouped by what they were measured on, in the table's order.
    public var figureGroups: [MeasuredFigureGroup]

    public var id: PageTranslationChoice { choice }

    public var canBeChosen: Bool { availability != .notOffered }
}

/// Figures measured on the same thing, under one heading.
nonisolated public struct MeasuredFigureGroup: Equatable, Sendable {
    public var basis: MeasuredFigure.Basis
    public var figures: [MeasuredFigure]

    public init(basis: MeasuredFigure.Basis, figures: [MeasuredFigure]) {
        self.basis = basis
        self.figures = figures
    }

    /// Consecutive figures with the same basis, keeping their order. A basis that comes back
    /// after another starts a group of its own, so the table's order is never changed.
    public static func grouping(_ figures: [MeasuredFigure]) -> [MeasuredFigureGroup] {
        var groups: [MeasuredFigureGroup] = []
        for figure in figures {
            if groups.last?.basis == figure.basis {
                groups[groups.count - 1].figures.append(figure)
            } else {
                groups.append(MeasuredFigureGroup(basis: figure.basis, figures: [figure]))
            }
        }
        return groups
    }
}

/// A screen pushed from Settings › Translation. It needs the Translation screen's model,
/// which stays alive anyway: that screen is below it in the same stack.
///
/// Two values are equal when they hold the same model instance and the same destination.
nonisolated public struct PageTranslationChildRoute: Hashable, Sendable {
    public enum Destination: Hashable, Sendable {
        /// The selection screen of one kind of model.
        case choices(ModelRole)
        /// Models and licences.
        case licences
    }

    public let parent: PageTranslationSettingsModel
    public let destination: Destination

    public init(parent: PageTranslationSettingsModel, destination: Destination) {
        self.parent = parent
        self.destination = destination
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.parent === rhs.parent && lhs.destination == rhs.destination
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(parent))
        hasher.combine(destination)
    }
}
