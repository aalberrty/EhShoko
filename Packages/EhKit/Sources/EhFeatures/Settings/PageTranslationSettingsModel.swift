import Dependencies
import EhCore
import EhModels
import Foundation
import Observation

/// Settings › Translation and the screens pushed from it: where the models of the current
/// choices stand, the four choices with what was measured for each, storage, the private
/// model source and the credits.
///
/// The model store owns downloads, files and the token; the settings own the four choices
/// and the address. This model decides what a tap means and turns both into values the
/// views lay out. Opening a screen reads nothing from disk on the main actor: `load()` asks
/// the store to look at its folder, which it does elsewhere, and the figures are a static
/// table.
///
/// Choosing a model that is installed applies at once. Choosing one that is not starts its
/// download while the current models keep working, and applies when its install finishes
/// (`pending`). When nothing works yet, there is nothing to keep working: the choice
/// applies at once and becomes part of the set the top card downloads. A pending choice is
/// kept in the settings too, so one whose install ends after the app was closed still applies
/// when the screen next loads (`restorePendingChoices()`).
@Observable
public final class PageTranslationSettingsModel {
    /// What the top card's button does.
    public enum TopAction: Hashable, Sendable {
        case download(bytes: Int64)
        case pause
        case resume
        case retry
    }

    /// A choice of each kind that waits for its install; the current one is used until then.
    /// Every change is written to the settings, so it is cleared there wherever it is here.
    public internal(set) var pending: [ModelRole: PageTranslationChoice] = [:] {
        didSet { persistPending(changedFrom: oldValue) }
    }

    @ObservationIgnored @Dependency(\.pageTranslationModelStore) var store
    @ObservationIgnored @Dependency(\.settings) var settings
    @ObservationIgnored @Dependency(\.appLogger) var logger
    // The page cache's two shared objects, read only when the translated pages are measured
    // or cleared; the first read makes them.
    @ObservationIgnored @Dependency(\.pageTranslationPatchStore) var patchStore
    @ObservationIgnored @Dependency(\.pageTranslationResultWriter) var resultWriter

    /// The private store's address as it is typed. `commitAddress()` writes it to the settings.
    public var addressDraft = ""
    /// The bytes the translated pages' patch files take, once measured. Their text rows are
    /// small and not counted.
    public internal(set) var translatedPagesBytes: Int64?
    public internal(set) var isClearingTranslatedPages = false
    /// A licence's full text, from the file beside its model, shown in a sheet.
    public var licence: LicenceText?
    /// The notices of llama.cpp and the fonts, read when Models and licences first opens.
    public internal(set) var notices: [PageTranslationNotice] = []

    /// Keeps the model while a pending choice waits for its install (`watchPending()`).
    @ObservationIgnored private var pendingWatch: Task<Void, Never>?

    public init() {
        addressDraft = settings.pageTranslationSourceAddress
    }

    /// Looks at the store's folder (off the main actor, in the store), picks up a choice
    /// whose download was under way, and measures the translated pages. Called from the
    /// Translation screen's `task`.
    public func load() async {
        await store.refresh()
        restorePendingChoices()
        adoptDownloadsUnderWay()
        await measureTranslatedPages()
    }

    // MARK: The top card

    /// Where the models of the current choices stand together.
    public var setState: ModelSetState { store.requiredModelsState }

    /// Whether there is a network; a download waits for one by itself.
    public var isConnected: Bool { store.isConnected }

    /// What was measured for the current detector and reader together.
    public var pair: MeasuredFigure {
        PageTranslationMeasurements.linesReadExactly(detector: detector, reader: reader)
    }

    public var topAction: TopAction? {
        switch setState {
        case .missing(let bytes): .download(bytes: bytes)
        case .downloading, .waitingForConnection: .pause
        case .paused: .resume
        case .failed: .retry
        case .unavailable, .preparing, .ready: nil
        }
    }

    public func performTopAction() {
        switch topAction {
        case .download, .retry: store.downloadRequiredModels()
        case .pause: store.pause()
        case .resume: store.resume()
        case nil: break
        }
    }

    // MARK: The current choices

    /// The detector pages are translated with: the chosen one, or the best one this user
    /// can have when the chosen one cannot be had.
    public var detector: TextDetectorChoice { store.resolvedDetector ?? settings.pageTranslationDetector }
    public var reader: TextReaderChoice { store.resolvedReader ?? settings.pageTranslationReader }
    public var translator: TranslatorChoice { store.resolvedTranslator ?? settings.pageTranslationTranslator }
    public var repaint: RepaintChoice { store.resolvedRepaint }

    /// The choice of a kind pages are translated with now.
    public func current(_ role: ModelRole) -> PageTranslationChoice {
        switch role {
        case .detector: .detector(detector)
        case .reader: .reader(reader)
        case .translator: .translator(translator)
        case .repaint: .repaint(repaint)
        }
    }

    /// The cards of a selection screen: every choice of the kind that the catalog lists, and
    /// repaint off, which needs nothing.
    public func cards(for role: ModelRole) -> [PageTranslationChoiceCard] {
        let current = current(role)
        let defaultChoice = resolvedDefault(role)
        return PageTranslationChoice.all(for: role).filter(isListed).map { choice in
            PageTranslationChoiceCard(
                choice: choice,
                isSelected: choice == current,
                isDefault: choice == defaultChoice,
                isPending: pending[role] == choice,
                availability: availability(of: choice),
                isPrivateOnly: choice.artifact.flatMap { store.catalog.artifact($0)?.sharing } == .privateOnly,
                figureGroups: MeasuredFigureGroup.grouping(choice.figures)
            )
        }
    }

    /// Whether this user can choose it: it needs no model, or its model is installed or
    /// offered by one of the user's sources.
    public func canChoose(_ choice: PageTranslationChoice) -> Bool {
        choice.artifact.map(store.isAvailable) ?? true
    }

    private func isListed(_ choice: PageTranslationChoice) -> Bool {
        choice.artifact.map { store.catalog.artifact($0) != nil } ?? true
    }

    /// "Default" is the best model this user's sources offer (`README.md` section 15.4):
    /// the settings' default when it can be had, else the first of its kind that can.
    private func resolvedDefault(_ role: ModelRole) -> PageTranslationChoice {
        let preferred = PageTranslationChoice.preferredDefault(for: role)
        if canChoose(preferred) { return preferred }
        let all = PageTranslationChoice.all(for: role).filter(isListed)
        return all.first { $0.artifact != nil && canChoose($0) } ?? all.first { $0.artifact == nil } ?? preferred
    }

    private func availability(of choice: PageTranslationChoice) -> PageTranslationChoiceCard.Availability {
        guard let id = choice.artifact else { return .noDownload }
        let offered = store.isAvailable(id)
        switch store.state(of: id) {
        case .installed: return .installed
        case .waiting:
            let total = store.catalog.artifact(id)?.downloadSize ?? 0
            let left = store.bytesToDownload(for: [id])
            return .downloading(ModelTransferProgress(completedBytes: total - left, totalBytes: total))
        case .downloading(let progress): return .downloading(progress)
        case .paused(let progress): return .paused(progress)
        case .installing, .preparing: return .preparing
        case .failed(let failure): return offered ? .failed(failure) : .notOffered
        case .missing: return offered ? .needs(bytes: store.bytesToDownload(for: [id])) : .notOffered
        }
    }

    // MARK: Choosing

    /// Chooses a model of one kind. A choice that cannot be had does nothing.
    public func choose(_ choice: PageTranslationChoice) async {
        guard canChoose(choice) else { return }
        let role = choice.role
        let replaced = current(role)
        let wasDownloading = isSetDownloading
        // One download for each kind: a choice that was waiting is given up.
        if let superseded = pending.removeValue(forKey: role), superseded != choice {
            await cancelDownload(of: superseded)
        }
        if choice == replaced || choice.artifact.map({ store.state(of: $0) == .installed }) ?? true {
            apply(choice)
        } else if setWorks, let id = choice.artifact {
            pending[role] = choice
            store.download([id])
            watchPending()
        } else if let id = choice.artifact {
            apply(choice)
            await cancelDownload(of: replaced)
            // The set was being downloaded: the new model joins it.
            if wasDownloading { store.download([id]) }
        }
        stopWatchingIfSettled()
    }

    /// Whether the current models are installed, so that they keep working while another
    /// one downloads.
    private var setWorks: Bool {
        switch store.requiredModelsState {
        case .ready, .preparing: true
        default: false
        }
    }

    private var isSetDownloading: Bool {
        switch store.requiredModelsState {
        case .downloading, .waitingForConnection: true
        default: false
        }
    }

    func apply(_ choice: PageTranslationChoice) {
        switch choice {
        case .detector(let detector): settings.pageTranslationDetector = detector
        case .reader(let reader): settings.pageTranslationReader = reader
        case .translator(let translator): settings.pageTranslationTranslator = translator
        case .repaint(let repaint): settings.pageTranslationRepaint = repaint
        }
    }

    /// Stops the download of a choice nobody waits for any more and removes what it left.
    /// An installed model, or one the current choices need, is left alone.
    private func cancelDownload(of choice: PageTranslationChoice) async {
        guard let id = choice.artifact, isDownloading(id), !store.requiredArtifacts.contains(id) else { return }
        await store.delete([id])
    }

    private func isDownloading(_ id: ModelArtifactID) -> Bool {
        switch store.state(of: id) {
        case .waiting, .downloading, .paused: true
        default: false
        }
    }

    // MARK: Waiting for an install

    /// A download of a model that is not the current one of its kind was under way when the
    /// screen opened: it was chosen before, on a screen that has since closed. It is taken
    /// as that choice again, so it still applies when its install finishes.
    private func adoptDownloadsUnderWay() {
        for role in ModelRole.allCases where pending[role] == nil {
            let current = current(role)
            let underWay = PageTranslationChoice.all(for: role).first { choice in
                choice != current && choice.artifact.map(isDownloading) == true
            }
            if let underWay { pending[role] = underWay }
        }
        watchPending()
    }

    /// Watches the pending choices' models until each is installed (and applied) or its
    /// download ends without an install.
    ///
    /// The watch holds the model, on purpose: a choice still applies when its install
    /// finishes after the screen was closed. It ends, and lets the model go, once nothing is
    /// pending.
    func watchPending() {
        guard pendingWatch == nil, !pending.isEmpty else { return }
        pendingWatch = Task {
            await forEachObservedValue(of: { self.pendingStates }) { states in
                self.settle(states)
            }
        }
    }

    private var pendingStates: [ModelRole: ModelArtifactState] {
        pending.compactMapValues { choice in choice.artifact.map(store.state(of:)) }
    }

    private func settle(_ states: [ModelRole: ModelArtifactState]) {
        for (role, state) in states {
            guard let choice = pending[role] else { continue }
            switch state {
            case .installed:
                pending[role] = nil
                apply(choice)
            case .missing, .failed:
                // The download ended without an install; choosing it again tries again.
                pending[role] = nil
            case .waiting, .downloading, .paused, .installing, .preparing:
                break
            }
        }
        stopWatchingIfSettled()
    }

    private func stopWatchingIfSettled() {
        guard pending.isEmpty, let watch = pendingWatch else { return }
        watch.cancel()
        pendingWatch = nil
    }
}
